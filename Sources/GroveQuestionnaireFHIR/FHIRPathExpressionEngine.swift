//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRPathParser
import Foundation
public import GroveQuestionnaire
import ModelsR4


/// Holds the most recently encoded response, keyed by the answers it was built from.
@available(iOS 18, macOS 15, watchOS 11, *)
private final class ResponseCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: (responses: QuestionnaireResponses.Responses, node: FHIRPathNode)?

    func node(for responses: QuestionnaireResponses.Responses) -> FHIRPathNode? {
        lock.withLock {
            entry?.responses == responses ? entry?.node : nil
        }
    }

    func store(_ node: FHIRPathNode, for responses: QuestionnaireResponses.Responses) {
        lock.withLock {
            entry = (responses, node)
        }
    }
}


/// Evaluates SDC FHIRPath expressions against the in-progress `QuestionnaireResponse`.
///
/// Created by the FHIR conversion when the source questionnaire uses expression
/// features; the engine captures the questionnaire, its `variable` declarations,
/// and the app-supplied `launchContext` resources.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class FHIRPathExpressionEngine: QuestionnaireExpressionEngine, Sendable {
    struct Variable {
        enum Scope {
            /// A questionnaire-level declaration, visible to every expression in the form.
            case global
            /// An item-level declaration, visible to the declaring item and its descendants.
            case items(Set<String>)
        }

        let name: String
        let expression: String
        let scope: Scope
    }

    private let questionnaireNode: FHIRPathNode
    /// `variable` declarations, in document order.
    private let variables: [Variable]
    /// App-supplied launch-context resources, keyed by their declared name.
    private let launchContext: [String: FHIRPathNode]
    /// The caller-supplied instant used by all clock-sensitive FHIRPath functions.
    private let evaluationInstant: Date
    /// The last encoded response, so a form-wide recalculation encodes it once.
    private let responseCache = ResponseCache()

    init(
        questionnaire: ModelsR4.Questionnaire,
        variables: [Variable],
        launchContext: [String: FHIRPathNode],
        evaluationInstant: Date
    ) throws {
        self.questionnaireNode = try FHIRPathNode.encoding(questionnaire)
        self.variables = variables
        self.launchContext = launchContext
        self.evaluationInstant = evaluationInstant
    }

    public func evaluateBoolean(
        _ expression: String,
        scope: GroveQuestionnaire.Questionnaire.ExpressionScope,
        in responses: QuestionnaireResponses
    ) throws -> GroveQuestionnaire.Questionnaire.ExpressionBoolean {
        let context = try evaluationContext(scope: scope, qrNode: responseNode(for: responses))
        return switch try FHIRPathExpression.evaluateBoolean(expression: expression, context: context) {
        case .true: .true
        case .false: .false
        case .empty: .empty
        }
    }

    public func evaluateValue(
        _ expression: String,
        for task: GroveQuestionnaire.Questionnaire.Task,
        in responses: QuestionnaireResponses
    ) throws -> QuestionnaireResponses.Response.Value? {
        let context = try evaluationContext(scope: .item(task.id), qrNode: responseNode(for: responses))
        let result = try FHIRPathExpression.evaluate(expression: expression, context: context)
        return try Self.responseValue(from: result, for: task)
    }

    /// Evaluates an expression with no response yet (SDC `initialExpression`).
    func evaluateInitialValue(
        _ expression: String,
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> QuestionnaireResponses.Response.Value? {
        let context = try evaluationContext(scope: .item(task.id), qrNode: nil)
        let result = try FHIRPathExpression.evaluate(expression: expression, context: context)
        return try Self.responseValue(from: result, for: task)
    }

    // MARK: Context Assembly

    /// The response the expressions see.
    ///
    /// Encoded best-effort: an answer that cannot be expressed in FHIR yet — a
    /// half-entered number, say — drops out of the tree instead of failing every
    /// expression in the form at once.
    private func responseNode(for responses: QuestionnaireResponses) throws -> FHIRPathNode {
        if let cached = responseCache.node(for: responses.responses) {
            return cached
        }
        let node = try FHIRPathNode.encoding(ModelsR4.QuestionnaireResponse(evaluating: responses))
        responseCache.store(node, for: responses.responses)
        return node
    }

    /// Binds the SDC evaluation environment: `%resource` is the whole response,
    /// `%context` and the focus are the response item(s) carrying the expression, and
    /// `%qitem` is the questionnaire item they answer.
    private func evaluationContext(
        scope: GroveQuestionnaire.Questionnaire.ExpressionScope,
        qrNode: FHIRPathNode?
    ) throws -> FHIRPathEvaluationContext {
        var constants: [String: [FHIRPathValue]] = [:]
        constants["questionnaire"] = [.object(questionnaireNode)]
        for (name, node) in launchContext {
            constants[name] = [.object(node)]
        }
        if let qrNode {
            constants["resource"] = [.object(qrNode)]
            constants["context"] = [.object(qrNode)]
        }
        var context = FHIRPathEvaluationContext(
            focus: qrNode.map { [.object($0)] } ?? [],
            constants: constants,
            evaluationInstant: evaluationInstant
        )
        // `variable`s may reference earlier variables and the response; each is visible
        // only to the item that declares it and that item's descendants.
        for variable in variables where variable.isVisible(to: scope.taskId) {
            context.constants[variable.name] = try FHIRPathExpression.evaluate(expression: variable.expression, context: context)
        }
        guard let taskId = scope.taskId else {
            return context
        }
        context.constants["qitem"] = Self.items(withLinkId: taskId, in: questionnaireNode).map { .object($0) }
        guard let qrNode else {
            return context
        }
        let responseItems = Self.items(withLinkId: taskId, in: qrNode)
        context.constants["context"] = responseItems.map { .object($0) }
        switch scope {
        case .questionnaire:
            break
        case .item:
            context.focus = responseItems.map { .object($0) }
        case .answer:
            context.focus = responseItems.flatMap { item in
                item.children(named: "answer").flatMap { $0.children(named: "value") }.map(Self.value(of:))
            }
        }
        return context
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRPathExpressionEngine.Variable {
    /// Whether the declaration is in scope for an expression on the given item.
    func isVisible(to taskId: GroveQuestionnaire.Questionnaire.Task.ID?) -> Bool {
        switch scope {
        case .global:
            return true
        case .items(let linkIds):
            return taskId.map(linkIds.contains) ?? false
        }
    }
}


// MARK: Node Access

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRPathExpressionEngine {
    /// Promotes a JSON node to a FHIRPath value: leaves become primitives, objects stay nodes.
    private static func value(of node: FHIRPathNode) -> FHIRPathValue {
        switch node {
        case .bool(let value):
            return .boolean(value)
        case .number(let value):
            if value.exponent >= 0, let integer = Int(exactly: NSDecimalNumber(decimal: value)) {
                return .integer(integer)
            }
            return .decimal(value)
        case .string(let value):
            return .string(value)
        case .object, .array, .null:
            return .object(node)
        }
    }

    /// Every item with the given linkId, at any depth (including beneath an answer).
    private static func items(withLinkId linkId: String, in node: FHIRPathNode) -> [FHIRPathNode] {
        var found: [FHIRPathNode] = []
        func visit(_ node: FHIRPathNode) {
            if node.stringMember("linkId") == linkId {
                found.append(node)
            }
            for child in node.children(named: "item") {
                visit(child)
            }
            for answer in node.children(named: "answer") {
                for child in answer.children(named: "item") {
                    visit(child)
                }
            }
        }
        visit(node)
        return found
    }
}


// MARK: Result Mapping

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRPathExpressionEngine {
    /// Maps an evaluation result onto the response value shape of the task's kind.
    private static func responseValue(
        from result: [FHIRPathValue],
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> QuestionnaireResponses.Response.Value? {
        guard let first = result.first else {
            return QuestionnaireResponses.Response.Value.none
        }
        let value: QuestionnaireResponses.Response.Value? = switch task.kind.variant {
        case .boolean:
            boolValue(from: first)
        case .numeric:
            numberValue(from: first)
        case .freeText:
            stringValue(from: first)
        case .dateTime:
            dateValue(from: first)
        case .choice(let config):
            try choiceValue(from: result, options: config.options)
        case .instructional, .fileAttachment, .custom:
            nil
        }
        guard let value else {
            throw FHIRPathEvaluationError.typeMismatch("Cannot express \(first) as a response for task '\(task.id)'")
        }
        return value
    }

    private static func boolValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        guard case .boolean(let value) = value else {
            return nil
        }
        return .bool(value)
    }

    private static func numberValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        switch value {
        case .integer(let value):
            return .number(Double(value))
        case .decimal(let value), .quantity(let value, _):
            return .number(value.doubleValue)
        default:
            return nil
        }
    }

    private static func stringValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        switch value {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .string(String(value))
        case .decimal(let value):
            return .string("\(value)")
        default:
            return nil
        }
    }

    private static func dateValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        switch value {
        case .date(let components), .dateTime(let components), .time(let components):
            return .date(components)
        case .string(let string):
            switch FHIRPathValue.parseTemporal(string) {
            case .date(let components), .dateTime(let components):
                return .date(components)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// Codings (or code strings) select the options they match.
    private static func choiceValue(
        from result: [FHIRPathValue],
        options: [GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option]
    ) throws -> QuestionnaireResponses.Response.Value? {
        var selected: Set<String> = []
        for value in result {
            switch value {
            case .object(let node):
                guard let code = node.stringMember("code") else {
                    continue
                }
                let system = node.stringMember("system").flatMap(URL.init(string:))
                if node.stringMember("system") != nil, system == nil {
                    throw FHIRPathEvaluationError.typeMismatch("Coding.system is not an absolute URI")
                }
                if let match = try ChoiceOptionResolver.coding(system: system, code: code, in: options) {
                    selected.insert(match.id)
                }
            case .string(let string):
                if let match = try ChoiceOptionResolver.token(string, in: options) {
                    selected.insert(match.id)
                }
            default:
                continue
            }
        }
        guard !selected.isEmpty else {
            return nil
        }
        return .choice(.init(selectedOptions: selected))
    }
}
