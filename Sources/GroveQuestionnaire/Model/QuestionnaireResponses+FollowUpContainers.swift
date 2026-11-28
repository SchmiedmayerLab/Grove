//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The follow-up containers of tasks, in the order the enablement conditions read them.
@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// The follow-up container that stands for the free-text answer of an open choice.
    ///
    /// No option has this id, so the container holds no responses. An exported response carries the free-text
    /// answer after the selected options, and its follow-up items occur beneath it without answers.
    static let freeTextContainerId = "\u{1F}free-text"

    /// The follow-up containers of `task` in `container`, in document order.
    ///
    /// A choice task has one for every selected option, in the order of the options, and a last one for a
    /// free-text answer. A custom kind keeps its follow-up responses under option ids of its own; they are
    /// taken in the order of their ids.
    static func followUpContainers(
        of task: Questionnaire.Task,
        in container: QuestionnaireResponses
    ) -> [Questionnaire.Task.Kind.ChoiceConfig.Option.ID] {
        switch task.kind.variant {
        case .choice(let config):
            let choice = container.responses[task.id].value.choiceValue
            return config.options.map(\.id).filter { choice.selectedOptions.contains($0) }
                + (choice.freeTextOtherResponse == nil ? [] : [freeTextContainerId])
        case .custom:
            let optionIds = container.responses[task.id].nestedResponses.keys.map { identifier in
                switch identifier {
                case .choiceOption(let optionId):
                    optionId
                }
            }
            return optionIds.sorted()
        case .instructional, .boolean, .freeText, .dateTime, .numeric, .fileAttachment:
            return []
        }
    }

    /// The document position of the follow-up container `optionId` of `task` among all its containers.
    ///
    /// A choice task orders its containers by its options, also those not selected, followed by the free-text
    /// container. A custom kind orders them by option id: a stored container `i` is at `2 * i`, and a container
    /// without stored responses, such as the one a condition is evaluated in, falls between them.
    static func followUpContainerIndex(
        of optionId: Questionnaire.Task.Kind.ChoiceConfig.Option.ID,
        of task: Questionnaire.Task,
        in container: QuestionnaireResponses
    ) -> Int? {
        switch task.kind.variant {
        case .choice(let config):
            return optionId == freeTextContainerId ? config.options.count : config.options.firstIndex { $0.id == optionId }
        case .custom:
            let stored = followUpContainers(of: task, in: container)
            if let index = stored.firstIndex(of: optionId) {
                return 2 * index
            }
            return 2 * stored.count { $0 < optionId } - 1
        case .instructional, .boolean, .freeText, .dateTime, .numeric, .fileAttachment:
            return nil
        }
    }
}
