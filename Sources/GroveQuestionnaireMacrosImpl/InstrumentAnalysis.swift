//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRPathParser
import SwiftDiagnostics
import SwiftSyntax


/// Checks one `@Instrument` type: what it declares, where those declarations are placed,
/// and what its declarations reference.
///
/// Everything here is syntactic. A declaration the analysis cannot read is dropped from the
/// checks and reported as a warning; it never stops the expansion.
struct InstrumentAnalysis {
    struct Declaration {
        let name: String
        let role: ComponentRole
        let linkID: String
        let anchor: Syntax
        let initializer: ExprSyntax
    }

    /// The members of a condition that make their receiver a question rather than an option.
    private static let questionMembers: Set<String> = ["selected", "isTrue", "isFalse", "answered"]

    private let typeName: String
    private let attribute: AttributeSyntax
    private let members: MemberBlockItemListSyntax

    private(set) var diagnostics: [Diagnostic] = []
    private(set) var declarations: [Declaration] = []
    private var declarationsByName: [String: Declaration] = [:]
    private var unreadableNames: Set<String> = []
    private var linkIDOccurrences: [(linkID: String, node: ExprSyntax)] = []
    private var placements: [String: [Syntax]] = [:]
    private var initializers: [(name: String, initializer: ExprSyntax)] = []
    private var questionnaires: [FunctionCallExprSyntax] = []
    private var placementIsAnalysable = true

    /// The linkIds the instrument declares, in declaration order, paired with their names.
    var declaredLinkIDs: [(name: String, linkID: String)] {
        declarations.map { ($0.name, $0.linkID) }
    }

    init(typeName: String, attribute: AttributeSyntax, members: MemberBlockItemListSyntax) {
        self.typeName = typeName
        self.attribute = attribute
        self.members = members
    }

    mutating func run() {
        collectDeclarations()
        checkQuestionnaireCount()
        walkPlacements()
        checkUniqueness()
        checkPlacement()
        checkReferenceCycles()
        checkConditionReferences()
        checkExpressionLiterals()
    }

    private mutating func report(
        _ message: String,
        id: String,
        severity: DiagnosticSeverity = .error,
        at node: some SyntaxProtocol,
        note: (message: String, node: Syntax)? = nil
    ) {
        diagnostics.append(
            Diagnostic(
                node: node,
                message: InstrumentDiagnostic(message, id: id, severity: severity),
                notes: note.map { [Note(node: $0.node, message: InstrumentNote($0.message, id: id))] } ?? []
            )
        )
    }


    // MARK: Collection

    private mutating func collectDeclarations() {
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
                continue
            }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let initializer = binding.initializer?.value else {
                    continue
                }
                collect(name: name, initializer: initializer, anchor: Syntax(binding))
            }
        }
    }

    private mutating func collect(name: String, initializer: ExprSyntax, anchor: Syntax) {
        initializers.append((name, initializer))
        guard let call = InstrumentSyntax.baseCall(of: initializer),
              let role = InstrumentSyntax.role(ofCallee: InstrumentSyntax.calleePath(of: call)) else {
            unreadableNames.insert(name)
            return
        }
        guard role != .questionnaire else {
            questionnaires.append(call)
            return
        }
        guard let linkID = InstrumentSyntax.linkID(of: call) else {
            unreadableNames.insert(name)
            report(
                "linkId is not a string literal; '\(name)' is excluded from the checks",
                id: "non-literal-link-id",
                severity: .warning,
                at: call.arguments.first?.expression ?? ExprSyntax(call)
            )
            return
        }
        let declaration = Declaration(
            name: name,
            role: role,
            linkID: linkID.value,
            anchor: anchor,
            initializer: initializer
        )
        declarations.append(declaration)
        declarationsByName[name] = declaration
        linkIDOccurrences.append((linkID.value, linkID.node))
    }

    private mutating func checkQuestionnaireCount() {
        guard questionnaires.count != 1 else {
            return
        }
        report(
            "@Instrument requires exactly one Questionnaire(…) declaration; found \(questionnaires.count)",
            id: "questionnaire-count",
            at: attribute
        )
    }


    // MARK: Placement

    private mutating func walkPlacements() {
        guard let questionnaire = questionnaires.first, let body = InstrumentSyntax.contentBlock(of: questionnaire) else {
            placementIsAnalysable = false
            return
        }
        walk(body)
        for declaration in declarations where declaration.role == .group {
            if let content = InstrumentSyntax.baseCall(of: declaration.initializer).flatMap(InstrumentSyntax.contentBlock) {
                walk(content)
            }
        }
    }

    private mutating func walk(_ block: ClosureExprSyntax) {
        for statement in block.statements {
            guard case .expr(let expression) = statement.item else {
                reportUnanalysable(at: Syntax(statement))
                continue
            }
            place(expression)
        }
    }

    private mutating func place(_ expression: ExprSyntax) {
        for modifier in InstrumentSyntax.modifiers(of: expression) where modifier.name == "followUp" {
            if let content = InstrumentSyntax.contentBlock(of: modifier.call) {
                walk(content)
            }
        }
        let root = InstrumentSyntax.chainRoot(of: expression)
        if let call = root.as(FunctionCallExprSyntax.self) {
            placeInline(call, at: expression)
        } else if let name = localName(of: root) {
            placeHandle(named: name, at: Syntax(expression))
        } else if InstrumentSyntax.dottedName(of: root).isEmpty {
            reportUnanalysable(at: Syntax(expression))
        }
        // A handle from another declaration places nothing of ours, and its linkId is not
        // visible here, so it is neither a placement nor a failure.
    }

    private mutating func placeInline(_ call: FunctionCallExprSyntax, at expression: ExprSyntax) {
        guard let role = InstrumentSyntax.role(ofCallee: InstrumentSyntax.calleePath(of: call)) else {
            reportUnanalysable(at: Syntax(expression))
            return
        }
        if let linkID = InstrumentSyntax.linkID(of: call) {
            linkIDOccurrences.append((linkID.value, linkID.node))
        }
        if role == .section || role == .group, let content = InstrumentSyntax.contentBlock(of: call) {
            walk(content)
        }
    }

    private mutating func placeHandle(named name: String, at node: Syntax) {
        if declarationsByName[name] != nil {
            placements[name, default: []].append(node)
        } else if unreadableNames.contains(name) {
            report(
                "cannot determine the linkId of '\(name)'; it is excluded from the checks",
                id: "unclassifiable-placement",
                severity: .warning,
                at: node,
                note: ("declare it as `static let \(name) = ChoiceQuestion<…>(\"<linkId>\", …)` to have it checked", node)
            )
        }
    }

    /// The name a reference denotes when it belongs to this instrument.
    private func localName(of expression: ExprSyntax) -> String? {
        let path = InstrumentSyntax.dottedName(of: expression)
        switch path.count {
        case 1: return path[0]
        case 2 where path[0] == "Self" || path[0] == typeName: return path[1]
        default: return nil
        }
    }

    private mutating func reportUnanalysable(at node: Syntax) {
        guard placementIsAnalysable else {
            return
        }
        placementIsAnalysable = false
        report(
            "this item cannot be analysed; placement and uniqueness are not checked for this instrument",
            id: "unanalysable-body",
            severity: .warning,
            at: node,
            note: ("the questionnaire still checks its identifiers when it is constructed", node)
        )
    }
}


// MARK: Checks

extension InstrumentAnalysis {
    private mutating func checkUniqueness() {
        var first: [String: ExprSyntax] = [:]
        for occurrence in linkIDOccurrences {
            guard let original = first[occurrence.linkID] else {
                first[occurrence.linkID] = occurrence.node
                continue
            }
            report(
                "linkId \"\(occurrence.linkID)\" is declared twice; every item in a questionnaire needs its own linkId",
                id: "duplicate-link-id",
                at: occurrence.node,
                note: ("\"\(occurrence.linkID)\" is first declared here", Syntax(original))
            )
        }
    }

    private mutating func checkPlacement() {
        guard placementIsAnalysable else {
            return
        }
        for declaration in declarations {
            let placed = placements[declaration.name] ?? []
            switch placed.count {
            case 0:
                report(
                    "'\(declaration.name)' is declared but never placed in the questionnaire",
                    id: "unplaced-declaration",
                    at: declaration.anchor,
                    note: (
                        """
                        add it to a Section or Group, or move it out of the instrument if it is not part of this \
                        questionnaire
                        """,
                        declaration.anchor
                    )
                )
            case 1:
                break
            default:
                report(
                    "'\(declaration.name)' is placed twice; each item appears exactly once",
                    id: "duplicate-placement",
                    at: placed[1],
                    note: ("also placed here", placed[0])
                )
            }
        }
    }

    private mutating func checkReferenceCycles() {
        let known = Set(initializers.map(\.name))
        var edges: [String: Set<String>] = [:]
        for (name, initializer) in initializers {
            edges[name] = Set(
                ReferenceCollector.references(in: initializer)
                    .filter { $0.qualifier == nil || $0.qualifier == "Self" || $0.qualifier == typeName }
                    .map(\.name)
                    .filter { known.contains($0) }
            )
        }
        let cycle = ReferenceCycle.firstCycle(in: edges, startingFrom: initializers.map(\.name))
        guard !cycle.isEmpty else {
            return
        }
        let anchor = initializers.first { $0.name == cycle[0] }.map { Syntax($0.initializer) } ?? Syntax(attribute)
        report(
            cycle.count == 2
                ? "'\(cycle[0])' references itself in its own initializer, which deadlocks on first access"
                : "initializer cycle: \(cycle.map { "'\($0)'" }.joined(separator: " → "))",
            id: "reference-cycle",
            at: anchor,
            note: ("static let initializers run through swift_once; a cycle deadlocks on first access", anchor)
        )
    }

    private mutating func checkConditionReferences() {
        for (_, initializer) in initializers {
            for condition in ConditionCollector.conditions(in: initializer) {
                for reference in ReferenceCollector.references(in: condition) {
                    checkConditionReference(reference)
                }
            }
        }
    }

    private mutating func checkConditionReference(_ reference: InstrumentReference) {
        guard let qualifier = reference.qualifier, qualifier != "Self", qualifier != typeName else {
            guard placementIsAnalysable,
                  declarationsByName[reference.name] != nil,
                  placements[reference.name]?.isEmpty != false else {
                return
            }
            report(
                "condition references '\(reference.name)', which is not part of this questionnaire",
                id: "unplaced-reference",
                at: reference.node
            )
            return
        }
        // Warn only where the reference is used as a question: `Frequency.often` names an
        // option, and mistaking it for a foreign question would be the false positive that
        // makes authors delete the macro.
        guard qualifier.first?.isUppercase == true, isUsedAsQuestion(reference.node) else {
            return
        }
        report(
            """
            '\(qualifier).\(reference.name)' is declared outside this instrument; enableWhen can only reference items \
            of the same questionnaire, so this condition can never hold
            """,
            id: "foreign-reference",
            severity: .warning,
            at: reference.node
        )
    }

    private func isUsedAsQuestion(_ node: ExprSyntax) -> Bool {
        if let parent = node.parent?.as(MemberAccessExprSyntax.self), parent.base == node {
            return Self.questionMembers.contains(parent.declName.baseName.text)
        }
        return node.parent?.is(InfixOperatorExprSyntax.self) == true
    }

    private mutating func checkExpressionLiterals() {
        let declared = Set(declarations.map(\.linkID))
        var seen: Set<String> = []
        for literal in ExpressionLiteralCollector.literals(in: members) {
            guard let text = InstrumentSyntax.literalText(of: literal), seen.insert(text).inserted else {
                continue
            }
            do {
                _ = try FHIRPathExpression.parse(text)
            } catch {
                let detail = if case .syntaxError(let message)? = error as? FHIRPathEvaluationError {
                    message
                } else {
                    "\(error)"
                }
                report("malformed FHIRPath: \(detail)", id: "malformed-fhir-path", at: literal)
                continue
            }
            for linkID in FHIRPathReferences.linkIDs(in: text) where !declared.contains(linkID) {
                let suggestion = declared.filter { EditDistance.between($0, linkID, limit: 2) <= 2 }.min()
                report(
                    "expression references linkId \"\(linkID)\", which this questionnaire does not declare",
                    id: "unknown-link-id",
                    severity: .warning,
                    at: literal,
                    note: suggestion.map { ("did you mean \"\($0)\"?", Syntax(literal)) }
                )
            }
        }
    }
}
