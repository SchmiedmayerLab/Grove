//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation
private import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// A class, so that the evaluation, which recurses once for every task a condition depends on, keeps small
    /// stack frames.
    private final class ResolvedTask {
        /// The task with the resolved id.
        let task: Questionnaire.Task
        /// The ``QuestionnaireResponses`` instance whose ``QuestionnaireResponses/responses`` property contains this task's
        /// response; for an answerless occurrence, the container of the task it stands beneath.
        let responses: QuestionnaireResponses
        /// The occurrence's place in document order: the index of each enclosing task in its container,
        /// each followed by the index of the choice option whose follow-up container holds the next level.
        let position: [Int]
        /// Whether the occurrence has no answers by construction: it stands for the follow-up tasks of a task that
        /// is disabled or has no follow-up container, as the pair rules place items beneath a question without answers.
        let isAnswerless: Bool

        init(task: Questionnaire.Task, responses: QuestionnaireResponses, position: [Int], isAnswerless: Bool = false) {
            self.task = task
            self.responses = responses
            self.position = position
            self.isAnswerless = isAnswerless
        }
    }

    /// A task definition, held by reference for the same reason as ``ResolvedTask``.
    private final class TaskDefinition {
        let task: Questionnaire.Task

        init(_ task: Questionnaire.Task) {
            self.task = task
        }
    }

    /// What a condition reads for a referenced task.
    private enum Source {
        /// The occurrence the condition reads; it is enabled.
        case occurrence(ResolvedTask)
        /// The task has no enabled occurrence the condition can read, so it has no answers.
        case absent(TaskDefinition)
        /// The condition cannot be evaluated: it reads its own task, a task the questionnaire does not have,
        /// a task it encloses, or a task whose enablement depends on it.
        case unknown
    }
    
    
    /// Determines whether the task should currently be enabled, based on its ``Questionnaire/Task/enabledCondition``
    /// and the conditions of the groups enclosing it.
    package func shouldEnable(task: Questionnaire.Task) -> Bool {
        shouldEnable(task: task, visited: [])
    }

    /// - parameter visited: The task ids already on the evaluation stack; a task encountered
    ///     twice forms a reference cycle and evaluates as disabled, terminating the recursion.
    private func shouldEnable(task: Questionnaire.Task, visited: Set<Questionnaire.Task.ID>) -> Bool {
        // A condition that cannot be evaluated leaves the task disabled.
        enablement(of: task, visited: visited) == true
    }

    /// Whether the task is enabled; `nil` if its conditions cannot be evaluated, as on a reference cycle.
    private func enablement(
        of task: Questionnaire.Task,
        visited: Set<Questionnaire.Task.ID>
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        guard !visited.contains(task.id) else {
            return nil
        }
        let visited = visited.union([task.id])
        // A grouped task is asked only while every group it sits in is enabled.
        let outcomes = task.groupPath.map { evaluate($0.condition, for: task, visited: visited) }
            + [evaluate(task.enabledCondition, for: task, visited: visited)]
        return outcomes.contains(false) ? false : outcomes.contains(nil) ? nil : true
    }


    private func evaluate(
        _ condition: Questionnaire.Condition,
        for task: Questionnaire.Task,
        visited: Set<Questionnaire.Task.ID>
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        Self._evaluate(condition) {
            let source = resolve(targetTaskId: $0, from: task.id, visited: visited)
            guard case .occurrence(let resolved) = source else {
                return source
            }
            guard !resolved.isAnswerless else {
                return .absent(TaskDefinition(resolved.task))
            }
            // FHIR: when evaluating enableWhen, the answers of an item that is itself currently disabled are
            // treated as absent. A task whose enablement is evaluated further up forms a cycle and is unknown.
            switch resolved.responses.enablement(of: resolved.task, visited: visited) {
            case true?: return source
            case false?: return .absent(TaskDefinition(resolved.task))
            case nil: return .unknown
            }
        } evaluateExpression: { expression in
            // SDC enableWhenExpression: an empty result disables the item. A failing one is
            // an authoring defect, so it is recorded before the item disappears.
            guard let engine = questionnaire.expressionEngine else {
                return false
            }
            do {
                return try engine.evaluateBoolean(expression, scope: .item(task.id), in: self) == .true
            } catch {
                recordExpressionFailure(expression, for: task.id, error: error)
                return false
            }
        }
    }
    
    
    /// Whether the task's enablement can still change with answers not yet given.
    ///
    /// A condition over an unanswered question, or an expression with nothing to evaluate over, is
    /// unsettled: the task may yet be asked. Everything else is settled, one way or the other.
    package func isEnablementSettled(for task: Questionnaire.Task) -> Bool {
        isEnablementSettled(for: task, visited: [])
    }

    private func isEnablementSettled(for task: Questionnaire.Task, visited: Set<Questionnaire.Task.ID>) -> Bool {
        guard !visited.contains(task.id) else {
            return true
        }
        let visited = visited.union([task.id])
        return task.groupPath.allSatisfy { isSettled($0.condition, for: task, visited: visited) }
            && isSettled(task.enabledCondition, for: task, visited: visited)
    }

    private func isSettled(
        _ condition: Questionnaire.Condition,
        for task: Questionnaire.Task,
        visited: Set<Questionnaire.Task.ID>
    ) -> Bool {
        func settled(_ inner: Questionnaire.Condition) -> Bool {
            isSettled(inner, for: task, visited: visited)
        }
        func outcome(_ inner: Questionnaire.Condition) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
            evaluate(inner, for: task, visited: visited)
        }
        switch condition {
        case .not(let inner):
            return settled(inner)
        case .all(let inner):
            // One settled miss decides it; otherwise every part has to be settled.
            return inner.contains { settled($0) && outcome($0) == false } || inner.allSatisfy { settled($0) }
        case .any(let inner):
            return inner.contains { settled($0) && outcome($0) == true } || inner.allSatisfy { settled($0) }
        case .expression(let expression):
            guard let engine = questionnaire.expressionEngine else {
                return true
            }
            return (try? engine.evaluateBoolean(expression, scope: .item(task.id), in: self)) != .empty
        case .hasResponse(let taskId), .isMissingResponse(let taskId), .responseValueComparison(let taskId, _, _):
            let resolved: ResolvedTask
            switch resolve(targetTaskId: taskId, from: task.id, visited: visited) {
            case .occurrence(let occurrence) where occurrence.isAnswerless:
                // A follow-up task whose option is not selected yet, or whose choice task is disabled, can still occur.
                return false
            case .occurrence(let occurrence):
                resolved = occurrence
            case .absent:
                return false
            case .unknown:
                return true
            }
            // An answer settles it, and so does the referenced question being ruled out for good.
            return resolved.responses.hasResponse(for: resolved.task)
                || (!resolved.responses.shouldEnable(task: resolved.task, visited: visited)
                    && resolved.responses.isEnablementSettled(for: resolved.task, visited: visited))
        }
    }

    /// The occurrence of `targetTaskId` that a condition of the task `currentTaskId` in this container reads.
    ///
    /// Follows FHIR R4 `Questionnaire.item.enableWhen.question`: the nearest occurrence on the ancestor axis,
    /// then on the preceding axis, then on the following axis, in document order. A follow-up task occurs once
    /// in the container of every selected option of its choice task, in the order of the options, while that
    /// choice task is enabled, and otherwise once without answers. A condition never reads its own task.
    private func resolve(
        targetTaskId: Questionnaire.Task.ID,
        from currentTaskId: Questionnaire.Task.ID,
        visited: Set<Questionnaire.Task.ID>
    ) -> Source {
        let tasks = questionnaire.sections.flatMap(\.tasks)
        guard targetTaskId != currentTaskId, let definition = Self.task(targetTaskId, in: tasks),
              let current = position(of: currentTaskId) else {
            return .unknown
        }
        guard let candidates = Self.occurrences(
            of: targetTaskId,
            in: tasks,
            container: root,
            position: [],
            currentPath: Array(pathFromRoot),
            visited: visited
        ) else {
            return .unknown
        }
        if let ancestor = candidates.last(where: { current.starts(with: $0.position) }) {
            return .occurrence(ancestor)
        }
        if let nearest = candidates.last(where: { $0.position.lexicographicallyPrecedes(current) })
            ?? candidates.first(where: { current.lexicographicallyPrecedes($0.position) && !$0.position.starts(with: current) }) {
            return .occurrence(nearest)
        }
        return .absent(TaskDefinition(definition))
    }

    /// The document position of the task with `taskId` in this container; see ``ResolvedTask/position``.
    private func position(of taskId: Questionnaire.Task.ID) -> [Int]? { // swiftlint:disable:this discouraged_optional_collection
        var tasks = questionnaire.sections.flatMap(\.tasks)
        var current: Questionnaire.Task?
        var container = root
        var position: [Int] = []
        for component in pathFromRoot {
            switch component {
            case .task(let id):
                guard let index = tasks.firstIndex(where: { $0.id == id }) else {
                    return nil
                }
                position.append(index)
                current = tasks[index]
            case .choiceOption(let optionId):
                guard let task = current,
                      let index = Self.followUpContainerIndex(of: optionId, of: task, in: container) else {
                    return nil
                }
                position.append(index)
                tasks = task.kind.followUpTasks
                container = container.view(appending: ResponsesPath().appending(taskId: task.id).appending(choiceOption: optionId))
            }
        }
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            return nil
        }
        return position + [index]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// The outcome of `condition`: `nil` if it cannot be evaluated, as in the pair rules.
    ///
    /// `not`, `all` and `any` follow three-valued logic, so a condition that cannot be evaluated decides only
    /// where the known conditions do not.
    /// - parameter condition: The ``Questionnaire/Condition`` that should be evaluated
    /// - parameter resolveTaskId: Maps a referenced task id to what the condition reads for it.
    private static func _evaluate( // swiftlint:disable:this cyclomatic_complexity
        _ condition: Questionnaire.Condition,
        _ resolveTaskId: (Questionnaire.Task.ID) -> Source,
        evaluateExpression: (String) -> Bool
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        func inner(_ condition: Questionnaire.Condition) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
            _evaluate(condition, resolveTaskId, evaluateExpression: evaluateExpression)
        }
        switch condition {
        case .not(let condition):
            return inner(condition).map(!)
        case .any(let conditions):
            let outcomes = conditions.map(inner)
            return outcomes.contains(true) ? true : outcomes.contains(nil) ? nil : false
        case .all(let conditions):
            let outcomes = conditions.map(inner)
            return outcomes.contains(false) ? false : outcomes.contains(nil) ? nil : true
        case .expression(let expression):
            return evaluateExpression(expression)
        case .hasResponse(let taskId):
            switch resolveTaskId(taskId) {
            case .occurrence(let resolved): return resolved.responses.hasResponse(for: resolved.task)
            case .absent: return false
            case .unknown: return nil
            }
        case .isMissingResponse(let taskId):
            switch resolveTaskId(taskId) {
            case .occurrence(let resolved): return resolved.responses.isMissingResponse(for: resolved.task)
            case .absent: return false
            case .unknown: return nil
            }
        case let .responseValueComparison(taskId, `operator`, value):
            return compare(resolveTaskId(taskId), `operator`, value)
        }
    }

    /// The outcome of a ``Questionnaire/Condition/responseValueComparison(taskId:operator:value:)`` on `source`.
    @inline(never)
    private static func compare(
        _ source: Source,
        _ operator: Questionnaire.Condition.ComparisonOperator,
        _ value: Questionnaire.Condition.Value
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        let resolved: ResolvedTask
        switch source {
        case .occurrence(let occurrence):
            resolved = occurrence
        case .absent(let definition):
            if case .custom = definition.task.kind.variant {
                return `operator` == .notEqual
            }
            guard ConditionAnswer.compares(value, withAnswersOf: definition.task), ConditionAnswer.compares(`operator`, with: value) else {
                return nil
            }
            // An absent or disabled question has no answers.
            return `operator` == .notEqual
        case .unknown:
            return nil
        }
        let task = resolved.task
        let response = resolved.responses.responses[task.id].value
        if case let .custom(questionKind, config) = task.kind.variant {
            return questionKind.evaluateResponseValueComparison(
                for: config,
                response: response,
                operator: `operator`,
                value: value
            )
        }
        guard ConditionAnswer.compares(value, withAnswersOf: task), ConditionAnswer.compares(`operator`, with: value) else {
            return nil
        }
        return ConditionAnswer.answers(of: response, for: task).satisfy(`operator`, value)
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
    /// Every occurrence of `taskId` among `tasks` and their follow-up containers, in document order; `nil` if whether
    /// a follow-up container occurs is open.
    ///
    /// - parameter visited: The task ids on the evaluation stack, for deciding whether a choice task is enabled.
    /// - parameter currentPath: The rest of the path of the container a condition is evaluated in. A custom kind's
    ///     container on it occurs also while it holds no responses.
    private static func occurrences( // swiftlint:disable:this function_parameter_count cyclomatic_complexity function_body_length
        of taskId: Questionnaire.Task.ID,
        in tasks: [Questionnaire.Task],
        container: QuestionnaireResponses,
        position: [Int],
        currentPath: [ResponsePathComponent],
        visited: Set<Questionnaire.Task.ID>
    ) -> [ResolvedTask]? { // swiftlint:disable:this discouraged_optional_collection
        var occurrences: [ResolvedTask] = []
        for (index, task) in tasks.enumerated() {
            let taskPosition = position + [index]
            if task.id == taskId {
                occurrences.append(.init(task: task, responses: container, position: taskPosition))
            }
            // Only follow-up containers that can hold the task are searched.
            guard Self.contains(taskId, in: task.kind.followUpTasks) else {
                continue
            }
            // The follow-up tasks of a disabled task, or of one without a follow-up container, occur once beneath it
            // without answers. That occurrence sorts before every follow-up container of the task.
            let answerless = ResolvedTask(
                task: Self.task(taskId, in: task.kind.followUpTasks) ?? task,
                responses: container,
                position: taskPosition + [-1],
                isAnswerless: true
            )
            switch container.enablement(of: task, visited: visited) {
            case true?: break
            case false?:
                occurrences.append(answerless)
                continue
            // Whether the follow-up tasks occur is open, as on a cycle through the task's own condition.
            case nil: return nil
            }
            var currentOptionId: Questionnaire.Task.Kind.ChoiceConfig.Option.ID?
            if currentPath.count >= 2, case .task(task.id) = currentPath[0], case .choiceOption(let optionId) = currentPath[1] {
                currentOptionId = optionId
            }
            var optionIds = Self.followUpContainers(of: task, in: container)
            if case .custom = task.kind.variant, let currentOptionId, !optionIds.contains(currentOptionId) {
                optionIds.append(currentOptionId)
            }
            guard !optionIds.isEmpty else {
                occurrences.append(answerless)
                continue
            }
            for optionId in optionIds {
                guard let containerIndex = Self.followUpContainerIndex(of: optionId, of: task, in: container) else {
                    continue
                }
                guard let nested = Self.occurrences(
                    of: taskId,
                    in: task.kind.followUpTasks,
                    container: container.view(appending: ResponsesPath().appending(taskId: task.id).appending(choiceOption: optionId)),
                    position: taskPosition + [containerIndex],
                    currentPath: optionId == currentOptionId ? Array(currentPath.dropFirst(2)) : [],
                    visited: visited
                ) else {
                    return nil
                }
                occurrences += nested
            }
        }
        return occurrences
    }
}
