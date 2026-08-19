//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Shared modifier storage embedded in every DSL component.
@_documentation(visibility: internal)
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ComponentCore: Hashable, Sendable {
    var subtitle = ""
    var footer = ""
    var prefix: String?
    var shortTitle: String?
    var isOptional = false
    var isReadOnly = false
    var isHidden = false
    var enabledCondition: Questionnaire.Condition = .none
    var initialValue: QuestionnaireResponses.Response.Value?
    var calculatedExpression: String?
    var constraints: [Questionnaire.Task.Constraint] = []
    var media: Questionnaire.Task.Media?

    public init() {}

    /// Applies the stored modifiers onto a compiled task.
    func apply(to task: inout Questionnaire.Task) {
        task.subtitle = subtitle
        task.footer = footer
        task.prefix = prefix
        task.shortTitle = shortTitle
        task.isOptional = isOptional
        task.isReadOnly = isReadOnly
        task.isHidden = isHidden
        task.enabledCondition = enabledCondition
        task.initialValue = initialValue
        task.calculatedExpression = calculatedExpression
        task.constraints = constraints
        task.media = media
    }
}
