//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRPathParser
public import Foundation
public import ModelsR4


/// A deterministic problem found while validating a Grove Questionnaire/Response pair.
public struct ValidationIssue: Equatable, Hashable, Sendable {
    public enum Severity: String, Equatable, Hashable, Sendable {
        case error
        case warning
    }

    public enum Code: String, Equatable, Hashable, Sendable {
        case questionnaireProfile
        case responseProfile
        case questionnaireCanonical
        case subjectType
        case responseIdentifier
        case responseEnteredInError
        case itemUnknown
        case itemMisplaced
        case itemDuplicate
        case itemDisabled
        case responseText
        case answerType
        case answerOption
        case answerValueSet
        case valueSetUnresolved
        case answerLength
        case answerDecimalPlaces
        case answerValueBound
        case answerQuantityBound
        case answerUnit
        case answerAttachment
        case answerOccurrence
        case optionExclusive
        case repeats
        case requiredItem
        case itemNesting
        case enableWhenEvaluation
        case expressionShape
        case expressionEngineRequired
        case expressionEvaluation
        case targetConstraint
        case serialization
    }

    public let severity: Severity
    public let code: Code
    public let path: String
    public let message: String

    public init(severity: Severity = .error, code: Code, path: String, message: String) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }
}


/// Validates the deterministic rules that require one exact Questionnaire, its Response,
/// and any ValueSets used to certify coded answers or selectable units.
///
/// Base R4, SDC, and profile validation remain the job of the official validator pipeline.
/// This preflight is deliberately offline: every terminology resource must be supplied by
/// the caller, and an unresolved ValueSet fails closed.
public struct PairExpressionEvaluator: Sendable {
    // FHIRPath has three outcomes here: true, false, and the empty collection (`nil`).
    // swiftlint:disable:next discouraged_optional_boolean
    private let evaluation: @Sendable (_ expression: String, _ path: String) throws -> Bool?

    // swiftlint:disable discouraged_optional_boolean
    /// Creates an evaluator already bound to the Questionnaire/QuestionnaireResponse and
    /// launch context being validated. Returning `nil` means the expression evaluated empty.
    public init(
        _ evaluation: @escaping @Sendable (_ expression: String, _ path: String) throws -> Bool?
    ) {
        self.evaluation = evaluation
    }
    // swiftlint:enable discouraged_optional_boolean

    func evaluate(_ expression: String, path: String) throws -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        try evaluation(expression, path)
    }
}


public struct PairValidator: Sendable {
    private let expressionEvaluator: PairExpressionEvaluator?

    /// Creates a pair validator. Completed responses that use FHIRPath must supply an
    /// evaluator bound to the exact validation inputs; otherwise they fail with
    /// `expressionEngineRequired` rather than being accepted by assumption.
    public init(expressionEvaluator: PairExpressionEvaluator? = nil) {
        self.expressionEvaluator = expressionEvaluator
    }

    /// Validates a pair and returns all non-blocking warnings.
    ///
    /// Error-severity issues throw ``ContractError/invalidPair(_:)``.
    /// Warning-severity target constraints remain visible to the caller without rejecting
    /// an otherwise conformant completed or amended response.
    @discardableResult
    public func validate(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet] = []
    ) throws -> [ValidationIssue] {
        let validationIssues = issues(
            questionnaire: questionnaire,
            response: response,
            valueSets: valueSets
        )
        let failures = validationIssues.filter { $0.severity == .error }
        guard failures.isEmpty else {
            throw ContractError.invalidPair(failures)
        }
        return validationIssues.filter { $0.severity == .warning }
    }

    /// Returns every deterministic issue, sorted by path, code, severity, and message.
    public func issues(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet] = []
    ) -> [ValidationIssue] {
        PairRules.issues(
            questionnaire: questionnaire,
            response: response,
            valueSets: valueSets,
            expressionEvaluator: expressionEvaluator
        )
    }
}


/// A Questionnaire and QuestionnaireResponse whose canonical, answer structure, and
/// deterministic acceptance rules have passed Grove preflight.
public struct ResourcePair {
    /// The exact Questionnaire definition that was validated.
    public let questionnaire: ModelsR4.Questionnaire
    /// The QuestionnaireResponse validated against `questionnaire`.
    public let response: ModelsR4.QuestionnaireResponse
    /// Non-blocking validation findings, including unresolved warning constraints that
    /// a form filler must surface to the user and evaluate with a conforming FHIRPath engine.
    public let warnings: [ValidationIssue]

    /// Validates and retains an exact Questionnaire/QuestionnaireResponse pair.
    public init(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet] = [],
        validator: PairValidator = .init()
    ) throws {
        self.warnings = try validator.validate(
            questionnaire: questionnaire,
            response: response,
            valueSets: valueSets
        )
        self.questionnaire = questionnaire
        self.response = response
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PairExpressionEvaluator {
    /// Creates the built-in FHIRPath evaluator bound to one exact resource pair.
    public static func fhirPath(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone,
        launchContext: [String: ResourceProxy] = [:]
    ) throws -> Self {
        let questionnaireNode = try FHIRPathNode.encoding(questionnaire)
        let responseNode = try FHIRPathNode.encoding(response)
        let launchNodes = try launchContext.mapValues { try FHIRPathNode.encoding($0) }
        return Self { expression, _ in
            var constants: [String: [FHIRPathValue]] = [
                "questionnaire": [.object(questionnaireNode)],
                "resource": [.object(responseNode)],
                "context": [.object(responseNode)]
            ]
            for (name, node) in launchNodes {
                constants[name] = [.object(node)]
            }
            let context = FHIRPathEvaluationContext(
                focus: [.object(responseNode)],
                constants: constants,
                evaluationInstant: evaluationInstant,
                evaluationTimeZone: evaluationTimeZone
            )
            return switch try FHIRPathExpression.evaluateBoolean(
                expression: expression,
                context: context
            ) {
            case .true: true
            case .false: false
            case .empty: nil
            }
        }
    }
}
