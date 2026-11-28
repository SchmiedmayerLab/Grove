//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation


/// The enablement `enableWhen` gives the occurrences of an ``EnablementPlacement``, as the pair rules evaluate the
/// exported response.
///
/// A condition reads the occurrence FHIR R4 names for `enableWhen.question`: the nearest one on the ancestor axis,
/// then on the preceding axis, then on the following axis. The answers of an occurrence that is not enabled, also
/// where its enablement is unknown, count as absent, since the exported response omits it. A task or group whose
/// enablement depends on itself cannot be evaluated (see ``ConditionDependencies``), and a follow-up task is enabled
/// only while its choice task is.
///
/// The enablement of the occurrences a condition depends on is evaluated with an explicit stack, dependencies
/// first, so the length of a chain of conditions is not limited by the thread's stack.
@available(iOS 18, macOS 15, watchOS 11, *)
private struct EnablementGraph {
    /// What a condition reads for a referenced task.
    enum Source {
        /// The enabled occurrence the condition reads, and the container that holds its response.
        case occurrence(Questionnaire.Task, QuestionnaireResponses)
        /// The occurrence is not enabled or has no answers.
        case absent(Questionnaire.Task)
        /// The condition cannot be evaluated: it reads its own task, a task the questionnaire does not have,
        /// or a task only the evaluated task encloses.
        case unknown
    }

    private let root: QuestionnaireResponses
    private let placement: EnablementPlacement
    private let cyclic: Set<ConditionDependencies.Node>
    /// The enablement of each evaluated occurrence; `nil` when it cannot be evaluated.
    private(set) var states: [Int: Bool?] = [:] // swiftlint:disable:this discouraged_optional_boolean
    /// Whether the enablement of each settled occurrence can no longer change with answers not yet given.
    private(set) var settled: [Int: Bool] = [:]

    init(for container: QuestionnaireResponses) {
        root = container.root
        placement = container.enablementPlacement
        cyclic = container.cyclicConditionNodes
    }

    /// The occurrence of `taskId` in the container the graph is made for.
    func occurrence(of taskId: Questionnaire.Task.ID) -> Int? {
        placement.observed[taskId]
    }

    private func view(_ path: QuestionnaireResponses.ResponsesPath) -> QuestionnaireResponses {
        path.isEmpty ? root : root.view(appending: path)
    }
}


// MARK: Evaluation

@available(iOS 18, macOS 15, watchOS 11, *)
extension EnablementGraph {
    /// The outcome of a ``Questionnaire/Condition/responseValueComparison(taskId:operator:value:)`` on `source`.
    private static func compare(
        _ source: Source,
        _ operator: Questionnaire.Condition.ComparisonOperator,
        _ value: Questionnaire.Condition.Value
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        switch source {
        case let .occurrence(task, container):
            let response = container.responses[task.id].value
            if case let .custom(questionKind, config) = task.kind.variant {
                return questionKind.evaluateResponseValueComparison(for: config, response: response, operator: `operator`, value: value)
            }
            guard ConditionAnswer.compares(value, withAnswersOf: task), ConditionAnswer.compares(`operator`, with: value) else {
                return nil
            }
            return ConditionAnswer.answers(of: response, for: task).satisfy(`operator`, ConditionAnswer.recorded(value, for: task))
        case .absent(let task):
            if case .custom = task.kind.variant {
                return `operator` == .notEqual
            }
            guard ConditionAnswer.compares(value, withAnswersOf: task), ConditionAnswer.compares(`operator`, with: value) else {
                return nil
            }
            // An absent or disabled question has no answers.
            return `operator` == .notEqual
        case .unknown:
            return nil
        }
    }

    /// The occurrence a condition of the occurrence `index` reads for `taskId`; `nil` if there is none.
    private func source(of taskId: Questionnaire.Task.ID, from index: Int) -> Int? {
        let occurrences = placement.occurrences
        guard occurrences[index].task.id != taskId else {
            return nil
        }
        var ancestor = occurrences[index].parent
        while let current = ancestor {
            if occurrences[current].task.id == taskId {
                return current
            }
            ancestor = occurrences[current].parent
        }
        let candidates = placement.readable[taskId] ?? []
        return candidates.last { $0 < index } ?? candidates.first { $0 > index && !isDescendant($0, of: index) }
    }

    private func isDescendant(_ candidate: Int, of index: Int) -> Bool {
        var parent = placement.occurrences[candidate].parent
        while let current = parent {
            if current == index {
                return true
            }
            parent = placement.occurrences[current].parent
        }
        return false
    }

    /// The conditions of the occurrence: those of its groups, then its own; `nil` for one that depends on itself.
    private func conditions(of index: Int) -> [Questionnaire.Condition?] {
        let task = placement.occurrences[index].task
        return task.groupPath.map { cyclic.contains(.group($0.id)) ? nil : $0.condition }
            + [cyclic.contains(.task(task.id)) ? nil : task.enabledCondition]
    }

    /// The occurrences the enablement of `index` depends on.
    ///
    /// A comparison that cannot be evaluated is `nil` whatever its source's enablement, so, as in the cycles,
    /// it adds no dependency.
    private func dependencies(of index: Int) -> [Int] {
        let sources = conditions(of: index).compactMap(\.self).flatMap { condition in
            ConditionDependencies.references(in: condition) { taskId, comparison in
                source(of: taskId, from: index).map { ConditionDependencies.isEvaluable(comparison, on: placement.occurrences[$0].task) } ?? false
            }
            .compactMap { source(of: $0, from: index) }
        }
        return (placement.occurrences[index].parent.map { [$0] } ?? []) + sources
    }

    /// Evaluates the enablement of `index` and of every occurrence it depends on, dependencies first.
    ///
    /// - returns: The occurrences evaluated, in the order they were evaluated.
    @discardableResult
    mutating func evaluate(_ index: Int) -> [Int] {
        var order: [Int] = []
        var expanded: Set<Int> = []
        var stack = [index]
        while let current = stack.last {
            if states[current] != nil {
                stack.removeLast()
                continue
            }
            // An occurrence already being expanded would form a cycle; its enablement reads as unknown.
            let pending = expanded.contains(current)
                ? []
                : dependencies(of: current).filter { states[$0] == nil && !expanded.contains($0) }
            guard pending.isEmpty else {
                expanded.insert(current)
                stack += pending
                continue
            }
            stack.removeLast()
            states[current] = .some(state(of: current))
            order.append(current)
        }
        return order
    }

    /// The enablement of `index`, from that of its dependencies.
    private func state(of index: Int) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        let enclosing = placement.occurrences[index].parent.map { states[$0].flatMap(\.self) } ?? true
        let outcomes = [enclosing] + conditions(of: index).map { condition in
            condition.flatMap { outcome(of: $0, at: index) }
        }
        return outcomes.contains(false) ? false : outcomes.contains(nil) ? nil : true
    }

    /// What a condition of the occurrence `index` reads for `taskId`.
    private func read(_ taskId: Questionnaire.Task.ID, from index: Int) -> Source {
        guard let source = source(of: taskId, from: index) else {
            return .unknown
        }
        let occurrence = placement.occurrences[source]
        guard states[source] == true, let container = occurrence.container else {
            return .absent(occurrence.task)
        }
        return .occurrence(occurrence.task, view(container))
    }

    /// The outcome of `condition` for the occurrence `index`: `nil` if it cannot be evaluated, as in the pair rules.
    ///
    /// `not`, `all` and `any` follow three-valued logic, so a condition that cannot be evaluated decides only
    /// where the known conditions do not.
    private func outcome( // swiftlint:disable:this cyclomatic_complexity
        of condition: Questionnaire.Condition,
        at index: Int
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        switch condition {
        case .not(let inner):
            return outcome(of: inner, at: index).map(!)
        case .any(let conditions):
            let outcomes = conditions.map { outcome(of: $0, at: index) }
            return outcomes.contains(true) ? true : outcomes.contains(nil) ? nil : false
        case .all(let conditions):
            let outcomes = conditions.map { outcome(of: $0, at: index) }
            return outcomes.contains(false) ? false : outcomes.contains(nil) ? nil : true
        case .expression(let expression):
            return expressionOutcome(expression, at: index)
        case .hasResponse(let taskId):
            switch read(taskId, from: index) {
            case let .occurrence(task, container): return container.hasResponse(for: task)
            case .absent: return false
            case .unknown: return nil
            }
        case .isMissingResponse(let taskId):
            switch read(taskId, from: index) {
            case let .occurrence(task, container): return !task.isOptional && !task.isHidden && !container.hasResponse(for: task)
            case .absent: return false
            case .unknown: return nil
            }
        case let .responseValueComparison(taskId, `operator`, value):
            return Self.compare(read(taskId, from: index), `operator`, value)
        }
    }

    /// SDC enableWhenExpression: an empty result disables the item. A failing one is an authoring defect, so it is
    /// recorded before the item disappears.
    private func expressionOutcome(_ expression: String, at index: Int) -> Bool {
        let occurrence = placement.occurrences[index]
        guard let engine = root.questionnaire.expressionEngine else {
            return false
        }
        let scope = view(occurrence.scope)
        do {
            return try engine.evaluateBoolean(expression, scope: .item(occurrence.task.id), in: scope) == .true
        } catch {
            scope.recordExpressionFailure(expression, for: occurrence.task.id, error: error)
            return false
        }
    }
}


// MARK: Settledness

@available(iOS 18, macOS 15, watchOS 11, *)
extension EnablementGraph {
    /// Decides whether the enablement of `index` is settled; its dependencies have to be settled first.
    mutating func settle(_ index: Int) {
        // Each part of the enablement: whether it holds, and whether that is settled.
        var parts: [(outcome: Bool?, isSettled: Bool)] = [] // swiftlint:disable:this discouraged_optional_boolean
        if let parent = placement.occurrences[index].parent {
            parts.append((states[parent].flatMap(\.self), settled[parent] ?? false))
        }
        for condition in conditions(of: index) {
            // A condition that cannot be evaluated stays so.
            parts.append(condition.map { (outcome(of: $0, at: index), isSettled($0, at: index)) } ?? (nil, true))
        }
        // One settled miss decides it; otherwise every part has to be settled.
        settled[index] = parts.contains { $0.isSettled && $0.outcome == false } || parts.allSatisfy(\.isSettled)
    }

    private func isSettled(_ condition: Questionnaire.Condition, at index: Int) -> Bool {
        switch condition {
        case .not(let inner):
            return isSettled(inner, at: index)
        case .all(let inner):
            return inner.contains { isSettled($0, at: index) && outcome(of: $0, at: index) == false }
                || inner.allSatisfy { isSettled($0, at: index) }
        case .any(let inner):
            return inner.contains { isSettled($0, at: index) && outcome(of: $0, at: index) == true }
                || inner.allSatisfy { isSettled($0, at: index) }
        case .expression(let expression):
            let occurrence = placement.occurrences[index]
            guard let engine = root.questionnaire.expressionEngine else {
                return true
            }
            return (try? engine.evaluateBoolean(expression, scope: .item(occurrence.task.id), in: view(occurrence.scope))) != .empty
        case .hasResponse(let taskId), .isMissingResponse(let taskId), .responseValueComparison(let taskId, _, _):
            guard let source = source(of: taskId, from: index) else {
                return true
            }
            // An answer of an enabled occurrence settles it, and so does the occurrence being ruled out for good.
            // An occurrence without answers beneath a choice task that can still be selected is unsettled, and so
            // is an answer stored beneath a task that is disabled but can still be enabled.
            let occurrence = placement.occurrences[source]
            if states[source] == true, let container = occurrence.container {
                return view(container).hasResponse(for: occurrence.task)
            }
            return states[source] != true && settled[source] == true
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionKindDefinition {
    fileprivate static func evaluateResponseValueComparison(
        for config: any QuestionKindConfig,
        response: QuestionnaireResponses.Response.Value,
        operator: Questionnaire.Condition.ComparisonOperator,
        value: Questionnaire.Condition.Value
    ) -> Bool {
        guard let config = config as? Config else {
            return false
        }
        return self.evaluateResponseValueComparison(
            for: config,
            response: response,
            operator: `operator`,
            value: value
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// Determines whether the task should currently be enabled, based on its ``Questionnaire/Task/enabledCondition``,
    /// the conditions of the groups enclosing it, and the enablement of the choice task it follows up on.
    ///
    /// A condition that cannot be evaluated leaves the task disabled, and so does a task that does not occur in
    /// this container.
    package func shouldEnable(task: Questionnaire.Task) -> Bool {
        var graph = EnablementGraph(for: self)
        guard let index = graph.occurrence(of: task.id) else {
            return false
        }
        graph.evaluate(index)
        return graph.states[index] == true
    }

    /// Whether the task's enablement can still change with answers not yet given.
    ///
    /// A condition over an unanswered question, or an expression with nothing to evaluate over, is
    /// unsettled: the task may yet be asked. Everything else is settled, one way or the other.
    package func isEnablementSettled(for task: Questionnaire.Task) -> Bool {
        var graph = EnablementGraph(for: self)
        guard let index = graph.occurrence(of: task.id) else {
            return true
        }
        for evaluated in graph.evaluate(index) {
            graph.settle(evaluated)
        }
        return graph.settled[index] == true
    }
}
