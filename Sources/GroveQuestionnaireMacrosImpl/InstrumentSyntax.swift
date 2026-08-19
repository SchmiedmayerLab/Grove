//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftSyntax


/// What a recognised DSL constructor builds.
enum ComponentRole {
    case questionnaire
    case section
    case group
    case item
}


/// Syntactic recognition of the DSL, which is all a macro can do: it sees names, not types.
enum InstrumentSyntax {
    static let itemConstructors: Set<String> = [
        "Instruction",
        "BooleanQuestion",
        "TextQuestion",
        "NumberQuestion",
        "DateQuestion",
        "ChoiceQuestion",
        "MultiChoiceQuestion",
        "DynamicChoiceQuestion",
        "DynamicMultiChoiceQuestion"
    ]

    static let factories: Set<String> = [
        "NumberQuestion.integer",
        "NumberQuestion.quantity",
        "DateQuestion.time",
        "DateQuestion.dateTime"
    ]

    /// The role of a call, from its callee's dotted name.
    static func role(ofCallee path: [String]) -> ComponentRole? {
        guard let name = path.last else {
            return nil
        }
        if factories.contains(path.suffix(2).joined(separator: ".")) {
            return .item
        }
        // A leading module or namespace qualifier is the only other thing allowed in front.
        guard path.count <= 2 else {
            return nil
        }
        switch name {
        case "Questionnaire": return .questionnaire
        case "Section": return .section
        case "Group": return .group
        case _ where itemConstructors.contains(name): return .item
        default: return nil
        }
    }

    /// The call a modifier chain is applied to: `X(…).readOnly().hidden()` yields `X(…)`.
    static func baseCall(of expression: ExprSyntax) -> FunctionCallExprSyntax? {
        chainRoot(of: expression).as(FunctionCallExprSyntax.self)
    }

    /// The expression a modifier chain is applied to, which may be a bare handle reference.
    static func chainRoot(of expression: ExprSyntax) -> ExprSyntax {
        guard let call = expression.as(FunctionCallExprSyntax.self), let base = modifierReceiver(of: call) else {
            return expression
        }
        return chainRoot(of: base)
    }

    /// The modifier calls applied to an expression, outermost first.
    static func modifiers(of expression: ExprSyntax) -> [(name: String, call: FunctionCallExprSyntax)] {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let base = modifierReceiver(of: call),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return []
        }
        return [(member.declName.baseName.text, call)] + modifiers(of: base)
    }

    /// The receiver of a modifier call, or `nil` when the call is not a modifier.
    ///
    /// Modifiers are lowercase-initial instance methods, which is what separates
    /// `X(…).readOnly()` from the uppercase-initial `NumberQuestion.integer(…)` and
    /// `GroveQuestionnaire.Questionnaire(…)`.
    private static func modifierReceiver(of call: FunctionCallExprSyntax) -> ExprSyntax? {
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base,
              let first = member.declName.baseName.text.first,
              first.isLowercase else {
            return nil
        }
        let name = member.declName.baseName.text
        guard !factories.contains("\(dottedName(of: base).last ?? "").\(name)") else {
            return nil
        }
        return base
    }

    /// The callee of a call as a dotted name, empty when it is not a plain name.
    static func calleePath(of call: FunctionCallExprSyntax) -> [String] {
        dottedName(of: call.calledExpression)
    }

    /// A chain of plain identifiers (`Foo.bar.baz`), ignoring any generic arguments, empty for anything else.
    static func dottedName(of expression: ExprSyntax) -> [String] {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return [reference.baseName.text]
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return dottedName(of: specialization.expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else {
                return []
            }
            let head = dottedName(of: base)
            return head.isEmpty ? [] : head + [member.declName.baseName.text]
        }
        return []
    }

    /// The literal text of a string literal without interpolation.
    static func literalText(of expression: ExprSyntax?) -> String? {
        guard let literal = expression?.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        var text = ""
        for segment in literal.segments {
            guard case .stringSegment(let segment) = segment else {
                return nil
            }
            text += segment.content.text
        }
        return text
    }

    /// A call's first argument as a string literal — the linkId, by DSL convention.
    static func linkID(of call: FunctionCallExprSyntax) -> (value: String, node: ExprSyntax)? {
        guard let first = call.arguments.first, first.label == nil else {
            return nil
        }
        guard let text = literalText(of: first.expression) else {
            return nil
        }
        return (text, first.expression)
    }

    /// The trailing closure of a call, which in this DSL is always its content block.
    static func contentBlock(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.trailingClosure ?? call.arguments.last.flatMap { $0.expression.as(ClosureExprSyntax.self) }
    }
}
