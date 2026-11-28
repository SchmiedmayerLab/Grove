//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order


// MARK: Question Kind

/// Defines a question kind.
///
/// A question kind that is presented on screen additionally conforms to
/// `QuestionKindDefinitionWithViewSupport`, which adds the SwiftUI view it renders.
///
/// ## Topics
///
/// ### Static Methods
/// - ``validate(response:for:)``
/// - ``evaluateResponseValueComparison(for:response:operator:value:)``
///
/// ### Associated Types
/// - ``Config``
///
/// ### Related Types
/// - ``QuestionKindConfig``
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol QuestionKindDefinition: Sendable, SendableMetatype {
    associatedtype Config: QuestionKindConfig = EmptyQuestionKindConfig

    /// Validates a response collected to a question of this kind, against the question's config.
    static func validate(
        response: QuestionnaireResponses.Response,
        for config: Config
    ) -> QuestionnaireResponses.ResponseValidationResult

    /// Evaluates a ``Questionnaire/Condition/responseValueComparison(taskId:operator:value:)`` condition against a response collected to a question of this kind.
    ///
    /// - Note: By default, the response is equal to no value and has no order, so this function returns `true`
    ///     for ``Questionnaire/Condition/ComparisonOperator/notEqual`` and `false` for every other operator.
    static func evaluateResponseValueComparison(
        for config: Config,
        response: QuestionnaireResponses.Response.Value,
        operator: Questionnaire.Condition.ComparisonOperator,
        value: Questionnaire.Condition.Value
    ) -> Bool
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionKindDefinition {
    // swiftlint:disable:next missing_docs
    public static func evaluateResponseValueComparison(
        for config: Config,
        response: QuestionnaireResponses.Response.Value,
        operator: Questionnaire.Condition.ComparisonOperator,
        value: Questionnaire.Condition.Value
    ) -> Bool {
        // A question kind customizes this to compare its responses; without that, no response equals the value.
        `operator` == .notEqual
    }
}


// MARK: Question Kind Config

/// A configuration associated with a ``QuestionKindDefinition``
///
/// ## Topics
///
/// ### Supporting Types
/// - ``EmptyQuestionKindConfig``
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol QuestionKindConfig: Hashable, Sendable {
    /// Any follow-up tasks a task with this config will ask, in response to some specific event (e.g., a selection)
    var followUpTasks: [Questionnaire.Task] { get }

    /// Creates a functionally identical copy of the config, with any ``Questionnaire/Condition``s contained within simplified.
    func withConditionsSimplified() -> Self
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionKindConfig {
    // swiftlint:disable missing_docs
    public var followUpTasks: [Questionnaire.Task] { [] }

    public func withConditionsSimplified() -> Self {
        self
    }
    // swiftlint:enable missing_docs
}


@available(iOS 18, macOS 15, watchOS 11, *)
public struct EmptyQuestionKindConfig: QuestionKindConfig {
    public init() {}
}
