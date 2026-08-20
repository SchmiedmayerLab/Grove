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
    public func response(
        from source: GroveQuestionnaire.QuestionnaireResponses,
        subject: Reference? = nil,
        author: Reference? = nil,
        source responseSource: Reference? = nil,
        status: QuestionnaireResponseStatus = .completed,
        identifier: Identifier? = nil,
        repositoryID: GroveFHIRRepositoryID? = nil,
        authored: Date
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

    /// Creates and validates an exact Questionnaire/QuestionnaireResponse pair.
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
        authored: Date
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
