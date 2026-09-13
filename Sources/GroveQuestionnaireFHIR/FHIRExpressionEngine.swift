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
import Synchronization


/// A parsed expression per source string, so an expression evaluated on every render is parsed once.
@available(iOS 18, macOS 15, watchOS 11, *)
private final class ParsedExpressions: Sendable {
    private let parsed = Mutex<[String: ParsedFHIRPathExpression]>([:])

    /// How many expressions have been parsed, for the tests that hold parsing to once per expression.
    var count: Int {
        parsed.withLock(\.count)
    }

    func expression(_ source: String) throws -> ParsedFHIRPathExpression {
        if let known = parsed.withLock({ $0[source] }) {
            return known
        }
        let expression = try FHIRPathExpression.parse(source)
        parsed.withLock {
            $0[source] = expression
        }
        return expression
    }
}


/// What one state of the answers yields, derived once while the answers stay as they are: the encoded response,
/// its items by linkId, the questionnaire-level variables, and every result already asked of it.
///
/// A form asks for the same conditions on every render and for every task on a page; without this, each ask
/// encoded the response, evaluated every variable and walked the tree again.
@available(iOS 18, macOS 15, watchOS 11, *)
private final class ResponseState: Sendable {
    /// What has been asked of the state so far, by the scope it was asked in and the expression asked.
    private struct Results {
        var globals: [String: [FHIRPathValue]] = [:]
        var hasGlobals = false
        var booleans: [GroveQuestionnaire.Questionnaire.ExpressionScope: [String: GroveQuestionnaire.Questionnaire.ExpressionBoolean]] = [:]
        var values: [GroveQuestionnaire.Questionnaire.ExpressionScope: [String: QuestionnaireResponses.Response.Value?]] = [:]
    }

    let revision: Int
    let node: FHIRPathNode
    let items: [String: [FHIRPathNode]]
    /// The instant every expression of this state reads as `now()`: time moves on with the answers, so a page
    /// asked twice about the same answers hears the same thing.
    let created = Date()
    /// `%resource.descendants()`, walked once for this state; the questionnaire's come from the engine.
    let descendants: FHIRPathDescendantsCache
    private let results = Mutex(Results())

    init(
        revision: Int,
        node: FHIRPathNode,
        items: [String: [FHIRPathNode]],
        questionnaireDescendants: FHIRPathDescendantsCache
    ) {
        self.revision = revision
        self.node = node
        self.items = items
        self.descendants = FHIRPathDescendantsCache(constants: ["resource"], parent: questionnaireDescendants)
    }

    /// The questionnaire-level variables, evaluated on first use and kept for the state's lifetime.
    func globals(_ evaluate: () throws -> [String: [FHIRPathValue]]) rethrows -> [String: [FHIRPathValue]] {
        if let known = results.withLock({ $0.hasGlobals ? $0.globals : nil }) {
            return known
        }
        let evaluated = try evaluate()
        results.withLock {
            $0.globals = evaluated
            $0.hasGlobals = true
        }
        return evaluated
    }

    func boolean(
        _ expression: String,
        in scope: GroveQuestionnaire.Questionnaire.ExpressionScope,
        _ evaluate: () throws -> GroveQuestionnaire.Questionnaire.ExpressionBoolean
    ) rethrows -> GroveQuestionnaire.Questionnaire.ExpressionBoolean {
        if let known = results.withLock({ $0.booleans[scope]?[expression] }) {
            return known
        }
        let result = try evaluate()
        results.withLock {
            $0.booleans[scope, default: [:]][expression] = result
        }
        return result
    }

    func value(
        _ expression: String,
        in scope: GroveQuestionnaire.Questionnaire.ExpressionScope,
        _ evaluate: () throws -> QuestionnaireResponses.Response.Value?
    ) rethrows -> QuestionnaireResponses.Response.Value? {
        if let known = results.withLock({ $0.values[scope]?[expression] }) {
            return known
        }
        let result = try evaluate()
        results.withLock {
            $0.values[scope, default: [:]][expression] = result
        }
        return result
    }
}


/// Holds the state of the answers most recently asked about.
@available(iOS 18, macOS 15, watchOS 11, *)
private final class ResponseStates: Sendable {
    private let current = Mutex<(state: ResponseState?, built: Int)>((nil, 0))

    /// How many states have been built, for the tests that hold encoding to once per revision.
    var built: Int {
        current.withLock(\.built)
    }

    func state(for revision: Int, build: () throws -> ResponseState) rethrows -> ResponseState {
        if let state = current.withLock(\.state), state.revision == revision {
            return state
        }
        let state = try build()
        current.withLock {
            $0 = (state, $0.built + 1)
        }
        return state
    }
}


/// Evaluates SDC FHIRPath expressions against the in-progress `QuestionnaireResponse`.
///
/// Created by the FHIR conversion when the source questionnaire uses expression
/// features; the engine captures the questionnaire, its `variable` declarations,
/// and the app-supplied `launchContext` resources.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class FHIRQuestionnaireExpressionEngine: QuestionnaireExpressionEngine, Sendable {
    struct Variable {
        enum Scope {
            /// A questionnaire-level declaration, visible to every expression in the form.
            case global
            /// An item-level declaration, evaluated on the declaring item and visible to it and its descendants.
            case item(String, covering: Set<String>)
        }

        let name: String
        let expression: String
        let scope: Scope
    }

    private let questionnaireNode: FHIRPathNode
    /// The questionnaire's items by linkId, at any depth.
    private let questionnaireItems: [String: [FHIRPathNode]]
    /// `variable` declarations, in document order.
    private let variables: [Variable]
    /// App-supplied launch-context resources, keyed by their declared name.
    private let launchContext: [String: FHIRPathNode]
    private let expressions = ParsedExpressions()
    private let states = ResponseStates()
    /// `%questionnaire.descendants()`, walked once for the engine's lifetime: the questionnaire never changes.
    private let questionnaireDescendants = FHIRPathDescendantsCache(constants: ["questionnaire"])

    /// What the engine has done so far: expressions parsed and states of the answers encoded.
    var work: (parsedExpressions: Int, encodedStates: Int) {
        (expressions.count, states.built)
    }

    init(questionnaire: ModelsR4.Questionnaire, variables: [Variable], launchContext: [String: FHIRPathNode]) throws {
        let questionnaireNode = try FHIRPathNode.encoding(questionnaire)
        self.questionnaireNode = questionnaireNode
        self.questionnaireItems = Self.itemsByLinkId(in: questionnaireNode)
        self.variables = variables
        self.launchContext = launchContext
    }

    public func evaluateBoolean(
        _ expression: String,
        scope: GroveQuestionnaire.Questionnaire.ExpressionScope,
        in responses: QuestionnaireResponses
    ) throws -> GroveQuestionnaire.Questionnaire.ExpressionBoolean {
        let state = try state(for: responses)
        return try state.boolean(expression, in: scope) {
            let context = try evaluationContext(scope: scope, state: state)
            return switch try expressions.expression(expression).evaluateBoolean(context: context) {
            case .true: .true
            case .false: .false
            case .empty: .empty
            }
        }
    }

    public func evaluateValue(
        _ expression: String,
        for task: GroveQuestionnaire.Questionnaire.Task,
        in responses: QuestionnaireResponses
    ) throws -> QuestionnaireResponses.Response.Value? {
        let state = try state(for: responses)
        return try state.value(expression, in: .item(task.id)) {
            let context = try evaluationContext(scope: .item(task.id), state: state)
            let result = try expressions.expression(expression).evaluate(context: context)
            return try Self.responseValue(from: result, for: task)
        }
    }

    /// Evaluates an expression with no response yet (SDC `initialExpression`).
    func evaluateInitialValue(
        _ expression: String,
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> QuestionnaireResponses.Response.Value? {
        let context = try evaluationContext(scope: .item(task.id), state: nil)
        let result = try expressions.expression(expression).evaluate(context: context)
        return try Self.responseValue(from: result, for: task)
    }

    // MARK: Context Assembly

    /// The response the expressions see, with what has been derived from it so far.
    ///
    /// Encoded best-effort: an answer that cannot be expressed in FHIR yet — a
    /// half-entered number, say — drops out of the tree instead of failing every
    /// expression in the form at once.
    private func state(for responses: QuestionnaireResponses) throws -> ResponseState {
        let revision = responses.revision
        return try states.state(for: revision) {
            let node = try FHIRPathNode.encoding(ModelsR4.QuestionnaireResponse(evaluating: responses))
            return ResponseState(
                revision: revision,
                node: node,
                items: Self.itemsByLinkId(in: node),
                questionnaireDescendants: questionnaireDescendants
            )
        }
    }

    /// Binds the SDC evaluation environment: `%resource` is the whole response,
    /// `%context` and the focus are the response item(s) carrying the expression, and
    /// `%qitem` is the questionnaire item they answer.
    private func evaluationContext(
        scope: GroveQuestionnaire.Questionnaire.ExpressionScope,
        state: ResponseState?
    ) throws -> FHIRPathEvaluationContext {
        var constants: [String: [FHIRPathValue]] = [:]
        constants["questionnaire"] = [.object(questionnaireNode)]
        for (name, node) in launchContext {
            constants[name] = [.object(node)]
        }
        let qrNode = state?.node
        if let qrNode {
            constants["resource"] = [.object(qrNode)]
            constants["context"] = [.object(qrNode)]
        }
        var context = FHIRPathEvaluationContext(
            focus: qrNode.map { [.object($0)] } ?? [],
            constants: constants,
            now: state?.created ?? .now
        )
        context.descendants = state?.descendants ?? questionnaireDescendants
        // `variable`s may reference earlier variables and the response. A questionnaire-level one reads the
        // same response for every expression, so a state evaluates it once; an item-level one is visible
        // only to the item that declares it and that item's descendants, and reads the declaring item.
        let globals = try state?.globals { try evaluateVariables(in: context) } ?? evaluateVariables(in: context)
        context.constants.merge(globals) { _, global in global }
        for variable in variables {
            guard case let .item(declaring, covered) = variable.scope, let taskId = scope.taskId, covered.contains(taskId) else {
                continue
            }
            var declaringContext = context
            bind(&declaringContext, to: declaring, state: state, answers: false)
            context.constants[variable.name] = try expressions.expression(variable.expression).evaluate(context: declaringContext)
        }
        if let taskId = scope.taskId {
            bind(&context, to: taskId, state: state, answers: scope.isAnswer)
        }
        return context
    }

    /// Makes the item the expression's own: `%qitem`, `%context` and the focus, or the focus its answers.
    private func bind(_ context: inout FHIRPathEvaluationContext, to taskId: String, state: ResponseState?, answers: Bool) {
        context.constants["qitem"] = (questionnaireItems[taskId] ?? []).map { .object($0) }
        guard let state else {
            return
        }
        let responseItems = state.items[taskId] ?? []
        context.constants["context"] = responseItems.map { .object($0) }
        context.focus = answers
            ? responseItems.flatMap { item in item.children(named: "answer").flatMap { $0.children(named: "value") }.map(Self.value(of:)) }
            : responseItems.map { .object($0) }
    }

    /// The questionnaire-level variables, each evaluated in the context the earlier ones extend.
    private func evaluateVariables(in context: FHIRPathEvaluationContext) throws -> [String: [FHIRPathValue]] {
        var context = context
        var evaluated: [String: [FHIRPathValue]] = [:]
        for variable in variables where variable.isGlobal {
            let value = try expressions.expression(variable.expression).evaluate(context: context)
            context.constants[variable.name] = value
            evaluated[variable.name] = value
        }
        return evaluated
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRQuestionnaireExpressionEngine.Variable {
    var isGlobal: Bool {
        if case .global = scope {
            return true
        }
        return false
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.ExpressionScope {
    fileprivate var isAnswer: Bool {
        if case .answer = self {
            return true
        }
        return false
    }
}


// MARK: Node Access

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRQuestionnaireExpressionEngine {
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

    /// Every item by linkId, at any depth (including beneath an answer), in document order.
    private static func itemsByLinkId(in node: FHIRPathNode) -> [String: [FHIRPathNode]] {
        var found: [String: [FHIRPathNode]] = [:]
        func visit(_ node: FHIRPathNode) {
            if let linkId = node.stringMember("linkId") {
                found[linkId, default: []].append(node)
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
extension FHIRQuestionnaireExpressionEngine {
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
            choiceValue(from: result, options: config.options)
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
    ) -> QuestionnaireResponses.Response.Value? {
        var selected: Set<String> = []
        for value in result {
            switch value {
            case .object(let node):
                guard let code = node.stringMember("code") else {
                    continue
                }
                let token = node.stringMember("system").map { "\($0)|\(code)" } ?? code
                if let match = options.first(where: { $0.id == token || $0.id.hasSuffix("|\(code)") }) {
                    selected.insert(match.id)
                }
            case .string(let string):
                if let match = options.first(where: { $0.id == string || $0.id.hasSuffix("|\(string)") }) {
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
