//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// Controls task id lookup behaviour when evaluating a condition.
    private struct TaskLookupConfig {
        /// Whether the condition should be limited to only see responses for tasks that precede the one to which the condition belongs.
        let limitToPreviousTasks: Bool
        /// Whether, if the condition references a task that cannot be found in the current scope, the lookup for this task should continue in the parent scope.
        let exposeParentScope: Bool
    }
    
    private struct ResolvedTask {
        /// The task with the resolved id.
        let task: Questionnaire.Task
        /// The ``QuestionnaireResponses`` instance whose ``QuestionnaireResponses/responses`` property contains this task's
        let responses: QuestionnaireResponses
    }
    
    
    /// Determines whether the task should currently be enabled, based on its ``Questionnaire/Task/enabledCondition``
    /// and the conditions of the groups enclosing it.
    func shouldEnable(task: Questionnaire.Task) -> Bool {
        shouldEnable(task: task, visited: [])
    }

    /// - parameter visited: The task ids already on the evaluation stack; a task encountered
    ///     twice forms a reference cycle and evaluates as disabled, terminating the recursion.
    private func shouldEnable(task: Questionnaire.Task, visited: Set<Questionnaire.Task.ID>) -> Bool {
        guard !visited.contains(task.id) else {
            return false
        }
        let visited = visited.union([task.id])
        // FHIR's enableWhen places no ordering restriction on references, so lookups
        // consider the whole questionnaire, not only preceding tasks.
        let config = TaskLookupConfig(limitToPreviousTasks: false, exposeParentScope: true)
        // A grouped task is asked only while every group it sits in is enabled.
        return task.groupPath.allSatisfy { evaluate($0.condition, for: task, visited: visited, config: config) }
            && evaluate(task.enabledCondition, for: task, visited: visited, config: config)
    }


    private func evaluate(
        _ condition: Questionnaire.Condition,
        for task: Questionnaire.Task,
        visited: Set<Questionnaire.Task.ID>,
        config: TaskLookupConfig
    ) -> Bool {
        Self._evaluate(condition) {
            guard let resolved = resolveTaskId(targetTaskId: $0, currentTaskId: task.id, using: config) else {
                return nil
            }
            // FHIR: when evaluating enableWhen, the answers of an item that is itself
            // currently disabled are treated as absent.
            guard resolved.responses.shouldEnable(task: resolved.task, visited: visited) else {
                return nil
            }
            return resolved
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
    
    
    /// Looks up a ``Questionnaire/Task``, based on its id, in compliance with a ``TaskLookupConfig``.
    private func resolveTaskId( // swiftlint:disable:this cyclomatic_complexity
        targetTaskId: Questionnaire.Task.ID,
        currentTaskId: Questionnaire.Task.ID,
        using config: TaskLookupConfig
    ) -> ResolvedTask? {
        guard targetTaskId != currentTaskId else {
            // A condition is never allowed to reference its own task
            return nil
        }
        switch _variant {
        case .root:
            // if we're at the root level, we only can look up top-level (i.e., non-nested) tasks.
            let allTopLevelTasks = questionnaire.sections.flatMap(\.tasks)
            guard let curIdx = allTopLevelTasks.firstIndex(where: { $0.id == currentTaskId }) else {
                // we were unable to find the current task. this should never happen
                assertionFailure("Failed to resolve current task (\(currentTaskId)) in scope consisting of \(allTopLevelTasks.map(\.id))")
                return nil
            }
            guard let targetIdx = allTopLevelTasks.firstIndex(where: { $0.id == targetTaskId }) else {
                // we were not able to find the referenced task.
                // since we're not at the root level, we simply return nil.
                return nil
            }
            if targetIdx < curIdx || !config.limitToPreviousTasks {
                // the referenced task is ordered before the current task, or we're not limited to earlier tasks. all is well.
                return .init(task: allTopLevelTasks[targetIdx], responses: self)
            } else {
                return nil
            }
        case let .view(parent, pathFromParent: _):
            // we're nested somwehere within the questionnaire.
            // this is a little more tricky now.
            let parentTaskPath = self.pathFromRoot.compactMap { component in
                switch component {
                case .task(let taskId):
                    taskId
                case .choiceOption:
                    nil
                }
            }
            guard let parentTask = questionnaire.task(at: parentTaskPath) else {
                assertionFailure("unable to find parent task")
                return nil
            }
            let allTasks = parentTask.kind.followUpTasks
            guard let curIdx = allTasks.firstIndex(where: { $0.id == currentTaskId }) else {
                // we were unable to find the current task. this should never happen
                assertionFailure()
                return nil
            }
            guard let targetIdx = allTasks.firstIndex(where: { $0.id == targetTaskId }) else {
                // we were unable to find the referenced task at the current level.
                return if config.exposeParentScope {
                    parent.resolveTaskId(targetTaskId: targetTaskId, currentTaskId: parentTask.id, using: config)
                } else {
                    nil
                }
            }
            // we found both the current and the target task, at the current level
            if targetIdx < curIdx || !config.limitToPreviousTasks {
                return .init(task: allTasks[targetIdx], responses: self)
            } else {
                return nil
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// - parameter condition: The ``Questionnaire/Condition`` that should be evaluated
    /// - parameter resolveTaskId: A closure that maps a task is to its task. The function uses this to resolve tasks that are referenced by the condition.
    private static func _evaluate( // swiftlint:disable:this cyclomatic_complexity function_body_length
        _ condition: Questionnaire.Condition,
        _ resolveTaskId: (Questionnaire.Task.ID) -> ResolvedTask?,
        evaluateExpression: (String) -> Bool
    ) -> Bool {
        switch condition {
        case .not(let inner):
            return !_evaluate(inner, resolveTaskId, evaluateExpression: evaluateExpression)
        case .any(let inner):
            return inner.contains { _evaluate($0, resolveTaskId, evaluateExpression: evaluateExpression) }
        case .all(let inner):
            return inner.allSatisfy { _evaluate($0, resolveTaskId, evaluateExpression: evaluateExpression) }
        case .expression(let expression):
            return evaluateExpression(expression)
        case .hasResponse(let taskId):
            guard let resolved = resolveTaskId(taskId) else {
                return false
            }
            return resolved.responses.hasResponse(for: resolved.task)
        case .isMissingResponse(let taskId):
            guard let resolved = resolveTaskId(taskId) else {
                return false
            }
            return resolved.responses.isMissingResponse(for: resolved.task)
        case let .responseValueComparison(taskId, `operator`, value):
            guard let resolved = resolveTaskId(taskId) else {
                return false
            }
            let task = resolved.task
            let responses = resolved.responses.responses
            switch task.kind.variant {
            case .instructional:
                return false
            case .boolean:
                guard let response = responses[task.id].value.boolValue,
                      case let .bool(value) = value else {
                    return false
                }
                switch `operator` {
                case .equal:
                    return response == value
                case .notEqual:
                    return response != value
                case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
                    // not supported
                    return false
                }
            case .choice(let config):
                let response = responses[task.id].value.choiceValue
                // Option ids created from FHIR codings are `system|code` tokens; a condition
                // coding without a system matches on the bare code.
                func matches(optionId: String, conditionId: String) -> Bool {
                    optionId == conditionId || (!conditionId.contains("|") && optionId.hasSuffix("|\(conditionId)"))
                }
                switch value {
                case let .SCMCOption(conditionId):
                    switch `operator` {
                    case .equal:
                        return response.selectedOptions.contains { matches(optionId: $0, conditionId: conditionId) }
                    case .notEqual:
                        // FHIR: true if at least one answer differs; an unanswered question stays false.
                        return response.selectedOptions.contains { !matches(optionId: $0, conditionId: conditionId) }
                    case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
                        return false
                    }
                case .string(let expected):
                    // String-valued answerOptions, plus the open-choice free-text answer.
                    let selected: [String] = response.selectedOptions.compactMap { id in
                        config.options.first { $0.id == id }.flatMap {
                            if case .string(let string) = $0.answerValue { string } else { nil }
                        }
                    } + (response.freeTextOtherResponse.map { [$0] } ?? [])
                    switch `operator` {
                    case .equal:
                        return selected.contains(expected)
                    case .notEqual:
                        return selected.contains { $0 != expected }
                    case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
                        return false
                    }
                case .integer(let expected):
                    let selected: [Int] = response.selectedOptions.compactMap { id in
                        config.options.first { $0.id == id }.flatMap {
                            if case .integer(let int) = $0.answerValue { int } else { nil }
                        }
                    }
                    switch `operator` {
                    case .equal:
                        return selected.contains(expected)
                    case .notEqual:
                        return selected.contains { $0 != expected }
                    case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
                        return false
                    }
                case .bool, .decimal, .date, .quantity:
                    return false
                }
            case .freeText:
                guard case let .string(value) = value,
                      let response = responses[task.id].value.stringValue else {
                    return false
                }
                switch `operator` {
                case .equal:
                    return response == value
                case .notEqual:
                    return response != value
                case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
                    // not supported
                    return false
                }
            case .dateTime(let config):
                guard let response = responses[task.id].value.dateValue else {
                    return false
                }
                guard case .date(let expected) = value else {
                    return false
                }
                switch config.style {
                case .timeOnly:
                    let response = (response.hour ?? 0, response.minute ?? 0, response.second ?? 0)
                    let expected = (expected.hour ?? 0, expected.minute ?? 0, expected.second ?? 0)
                    return switch `operator` {
                    case .equal:
                        response == expected
                    case .notEqual:
                        response != expected
                    case .greaterThan:
                        response > expected
                    case .greaterThanOrEqual:
                        response >= expected
                    case .lessThan:
                        response < expected
                    case .lessThanOrEqual:
                        response <= expected
                    }
                case .dateOnly:
                    let response = (response.year ?? 0, response.month ?? 1, response.day ?? 1)
                    let expected = (expected.year ?? 0, expected.month ?? 1, expected.day ?? 1)
                    return switch `operator` {
                    case .equal:
                        response == expected
                    case .notEqual:
                        response != expected
                    case .greaterThan:
                        response > expected
                    case .greaterThanOrEqual:
                        response >= expected
                    case .lessThan:
                        response < expected
                    case .lessThanOrEqual:
                        response <= expected
                    }
                case .dateAndTime:
                    let cal = Calendar.current
                    guard let response = cal.date(from: response), let expected = cal.date(from: expected) else {
                        return false
                    }
                    return switch `operator` {
                    case .equal:
                        response == expected
                    case .notEqual:
                        response != expected
                    case .greaterThan:
                        response > expected
                    case .greaterThanOrEqual:
                        response >= expected
                    case .lessThan:
                        response < expected
                    case .lessThanOrEqual:
                        response <= expected
                    }
                }
            case .numeric(let config):
                switch value {
                case let .quantity(value, unitCode):
                    // Same-unit magnitude comparison; a condition without a unit matches any.
                    // A unit the participant chose (unitOption) takes precedence over the fixed unit.
                    let taskUnit = responses[task.id].value.quantityValue?.unitCode
                        ?? config.unitCode ?? (config.unit.isEmpty ? nil : config.unit)
                    guard unitCode == nil || unitCode == taskUnit,
                          let response = responses[task.id].value.numberValue else {
                        return false
                    }
                    return switch `operator` {
                    case .equal:
                        response == value
                    case .notEqual:
                        response != value
                    case .lessThan:
                        response < value
                    case .greaterThan:
                        response > value
                    case .lessThanOrEqual:
                        response <= value
                    case .greaterThanOrEqual:
                        response >= value
                    }
                case .integer(let value):
                    guard let response = responses[task.id].value.numberValue.flatMap(Int.init(exactly:)) else {
                        return false
                    }
                    return switch `operator` {
                    case .equal:
                        response == value
                    case .notEqual:
                        response != value
                    case .lessThan:
                        response < value
                    case .greaterThan:
                        response > value
                    case .lessThanOrEqual:
                        response <= value
                    case .greaterThanOrEqual:
                        response >= value
                    }
                case .decimal(let value):
                    guard let response = responses[task.id].value.numberValue else {
                        return false
                    }
                    return switch `operator` {
                    case .equal:
                        response == value
                    case .notEqual:
                        response != value
                    case .lessThan:
                        response < value
                    case .greaterThan:
                        response > value
                    case .lessThanOrEqual:
                        response <= value
                    case .greaterThanOrEqual:
                        response >= value
                    }
                case .bool, .date, .string, .SCMCOption:
                    // invalid match
                    return false
                }
            case .fileAttachment:
                return false
            case let .custom(questionKind, config):
                let response = responses[taskId].value
                return questionKind.evaluateResponseValueComparison(
                    for: config,
                    response: response,
                    operator: `operator`,
                    value: value
                )
            }
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
