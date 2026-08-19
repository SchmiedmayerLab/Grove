//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation


/// Evaluates authored expressions (typically FHIRPath) against the in-progress responses.
///
/// The questionnaire model itself is expression-language-agnostic; a ``Questionnaire``
/// created from a FHIR resource carries an engine wired up by the FHIR conversion layer,
/// which resolves SDC constructs (`enableWhenExpression`, `calculatedExpression`,
/// `variable`, `targetConstraint`) over the live `QuestionnaireResponse`.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol QuestionnaireExpressionEngine: AnyObject, Sendable {
    /// Evaluates a boolean-valued expression (enable conditions, constraints).
    ///
    /// - Throws: When the expression is invalid or uses unsupported features.
    func evaluateBoolean(
        _ expression: String,
        scope: Questionnaire.ExpressionScope,
        in responses: QuestionnaireResponses
    ) throws -> Questionnaire.ExpressionBoolean

    /// Evaluates a value-producing expression (calculated values) into a response
    /// value suitable for the given task.
    func evaluateValue(
        _ expression: String,
        for task: Questionnaire.Task,
        in responses: QuestionnaireResponses
    ) throws -> QuestionnaireResponses.Response.Value?
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// What a boolean-valued expression came out as.
    ///
    /// The expression languages behind an engine are three-valued — an expression over an
    /// unanswered item yields nothing rather than `false` — and the two differ in what they
    /// mean: an unmet constraint is a validation failure, an empty one proves nothing.
    public enum ExpressionBoolean: Hashable, Sendable {
        /// The expression held.
        case `true`
        /// The expression did not hold.
        case `false`
        /// The expression had nothing to evaluate over, which is neither.
        case empty
    }

    /// What an authored expression is evaluated against.
    ///
    /// SDC keeps `%resource` on the whole `QuestionnaireResponse` and requires `%context`
    /// (and with it the expression's starting focus) to be the response item(s) whose
    /// linkId matches the item carrying the expression; `%qitem` is the questionnaire item
    /// they answer.
    public enum ExpressionScope: Hashable, Sendable {
        /// An expression authored on the questionnaire itself.
        case questionnaire
        /// An expression authored on an item (`enableWhenExpression`, `calculatedExpression`).
        case item(Task.ID)
        /// A rule about the answers an item collected (`targetConstraint`), which
        /// evaluates against those answers: `$this` is what the participant entered.
        case answer(Task.ID)

        /// The item the expression is authored on, if it is not questionnaire-level.
        public var taskId: Task.ID? {
            switch self {
            case .questionnaire:
                nil
            case .item(let taskId), .answer(let taskId):
                taskId
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task {
    /// An authored cross-field validation rule (FHIR `targetConstraint`).
    public struct Constraint: Hashable, Sendable {
        public enum Severity: String, Hashable, Sendable {
            /// A violation makes the response invalid.
            case error
            /// A violation is surfaced but does not block completion.
            case warning
        }

        /// The boolean expression that must evaluate to `true` for the response to be valid.
        public let expression: String
        /// The human-readable message shown when the constraint is violated.
        public let humanDescription: String
        public let severity: Severity
        /// The rule's identifier (FHIR `targetConstraint.key`), unique within the questionnaire.
        ///
        /// Exports synthesize one from the task id when none was authored.
        public let key: String?

        public init(expression: String, humanDescription: String, severity: Severity = .error, key: String? = nil) {
            self.expression = expression
            self.humanDescription = humanDescription
            self.severity = severity
            self.key = key
        }
    }
}
