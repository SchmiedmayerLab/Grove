//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import ModelsR4


/// A deterministic problem found while validating a Grove Questionnaire/Response pair.
public struct GroveQuestionnaireFHIRValidationIssue: Equatable, Hashable, Sendable {
    public enum Severity: String, Equatable, Hashable, Sendable {
        case error
        case warning
    }

    public enum Code: String, Equatable, Hashable, Sendable {
        case questionnaireProfile
        case responseProfile
        case questionnaireCanonical
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
public struct GroveQuestionnaireFHIRPairValidator: Sendable {
    public init() {}

    /// Validates a pair and returns all non-blocking warnings.
    ///
    /// Error-severity issues throw ``GroveQuestionnaireFHIRContractError/invalidPair(_:)``.
    /// Warning-severity target constraints remain visible to the caller without rejecting
    /// an otherwise conformant completed or amended response.
    @discardableResult
    public func validate(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet] = []
    ) throws -> [GroveQuestionnaireFHIRValidationIssue] {
        let validationIssues = issues(
            questionnaire: questionnaire,
            response: response,
            valueSets: valueSets
        )
        let failures = validationIssues.filter { $0.severity == .error }
        guard failures.isEmpty else {
            throw GroveQuestionnaireFHIRContractError.invalidPair(failures)
        }
        return validationIssues.filter { $0.severity == .warning }
    }

    /// Returns every deterministic issue, sorted by path, code, severity, and message.
    public func issues(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet] = []
    ) -> [GroveQuestionnaireFHIRValidationIssue] {
        GroveQuestionnaireFHIRPairRules.issues(
            questionnaire: questionnaire,
            response: response,
            valueSets: valueSets
        )
    }
}


/// A Questionnaire and QuestionnaireResponse whose canonical, answer structure, and
/// deterministic acceptance rules have passed Grove preflight.
public struct GroveQuestionnaireFHIRPair {
    /// The exact Questionnaire definition that was validated.
    public let questionnaire: ModelsR4.Questionnaire
    /// The QuestionnaireResponse validated against `questionnaire`.
    public let response: ModelsR4.QuestionnaireResponse
    /// Non-blocking validation findings, including unresolved warning constraints that
    /// a form filler must surface to the user and evaluate with a conforming FHIRPath engine.
    public let warnings: [GroveQuestionnaireFHIRValidationIssue]

    /// Validates and retains an exact Questionnaire/QuestionnaireResponse pair.
    public init(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse,
        valueSets: [ModelsR4.ValueSet] = [],
        validator: GroveQuestionnaireFHIRPairValidator = .init()
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
