//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract
public import GroveQuestionnaire
public import ModelsR4


/// The normative, profile-aware construction surface for Grove Questionnaire 0.2.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct GroveQuestionnaireFHIRBuilder: Sendable {
    /// Creates a stateless Questionnaire exchange builder.
    public init() {}

    /// Creates a profiled Questionnaire, assigning `Resource.id` only when supplied by a repository.
    public func questionnaire(
        from source: GroveQuestionnaire.Questionnaire,
        repositoryID: GroveFHIRRepositoryID? = nil
    ) throws -> ModelsR4.Questionnaire {
        try ModelsR4.Questionnaire(source, repositoryID: repositoryID)
    }

    /// Creates a profiled QuestionnaireResponse with a complete business identifier.
    ///
    /// Use this when the response travels alone -- for example when the receiving system already
    /// holds the Questionnaire. When both resources travel together, prefer ``pair(from:subject:author:responseSource:status:identifier:questionnaireRepositoryID:responseRepositoryID:valueSets:authored:)``,
    /// which also cross-validates the two against the published pair rules.
    ///
    /// ```swift
    /// let response = try GroveQuestionnaireFHIRBuilder().response(
    ///     from: responses,
    ///     subject: Reference(reference: "Patient/example")
    /// )
    /// ```
    public func response(
        from source: GroveQuestionnaire.QuestionnaireResponses,
        subject: Reference? = nil,
        author: Reference? = nil,
        source responseSource: Reference? = nil,
        status: QuestionnaireResponseStatus = .completed,
        identifier: Identifier? = nil,
        repositoryID: GroveFHIRRepositoryID? = nil,
        authored: Date = .now
    ) throws -> ModelsR4.QuestionnaireResponse {
        try ModelsR4.QuestionnaireResponse(
            source,
            subject: subject,
            author: author,
            source: responseSource,
            status: status,
            identifier: identifier,
            repositoryID: repositoryID,
            authored: authored
        )
    }

    /// Creates an exact Questionnaire/QuestionnaireResponse pair and validates them against each other.
    ///
    /// Unlike calling ``questionnaire(from:repositoryID:)`` and
    /// ``response(from:subject:author:source:status:identifier:repositoryID:authored:)`` separately,
    /// the pair is checked against the published pair rules -- every answer's linkId, type, and
    /// enable-when relationship must line up -- so an inconsistent export fails here instead of at
    /// the receiving system.
    ///
    /// ```swift
    /// let pair = try GroveQuestionnaireFHIRBuilder().pair(
    ///     from: responses,
    ///     subject: Reference(reference: "Patient/example")
    /// )
    /// send(pair.questionnaire, pair.response)
    /// ```
    public func pair(
        from source: GroveQuestionnaire.QuestionnaireResponses,
        subject: Reference? = nil,
        author: Reference? = nil,
        responseSource: Reference? = nil,
        status: QuestionnaireResponseStatus = .completed,
        identifier: Identifier? = nil,
        questionnaireRepositoryID: GroveFHIRRepositoryID? = nil,
        responseRepositoryID: GroveFHIRRepositoryID? = nil,
        valueSets: [ModelsR4.ValueSet] = [],
        authored: Date = .now
    ) throws -> GroveQuestionnaireFHIRPair {
        let questionnaire = try questionnaire(
            from: source.questionnaire,
            repositoryID: questionnaireRepositoryID
        )
        let response = try response(
            from: source,
            subject: subject,
            author: author,
            source: responseSource,
            status: status,
            identifier: identifier,
            repositoryID: responseRepositoryID,
            authored: authored
        )
        return try GroveQuestionnaireFHIRPair(
            questionnaire: questionnaire,
            response: response,
            valueSets: valueSets
        )
    }
}
