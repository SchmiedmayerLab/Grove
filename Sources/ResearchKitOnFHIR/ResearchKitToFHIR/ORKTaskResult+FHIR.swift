//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if ResearchKit

import FHIRModelsExtensions
import Foundation
public import GroveFHIRContract
public import ModelsR4
public import ResearchKit


/// Resolves a ResearchKit-local file into exchange-ready FHIR attachment metadata.
///
/// The resolver is the explicit staging boundary: it may embed the bytes or upload them to a
/// durable HTTPS location. The returned attachment is validated before it reaches the wire.
public typealias ResearchKitAttachmentResolver = @Sendable (
    _ resultIdentifier: String,
    _ localFileURL: URL
) throws -> Attachment


public enum ResearchKitFHIRConversionError: Error, Equatable, Sendable {
    case invalidQuestionnaireCanonical(String)
    case questionnaireProfileRequired
    case invalidQuestionnaireLayout(String)
    case duplicateQuestionnaireLinkID(String)
    case repeatedQuestionnaireItem(String)
    case unsupportedRepeatedAttachment(linkID: String)
    case itemControlCardinalityConflict(linkID: String)
    case invalidAnswerCardinality(linkID: String, answerCount: Int)
    case invalidReference(field: String)
    case taskIdentifierMismatch(expected: String, actual: String)
    case duplicateResultIdentifier(String)
    case unknownResultIdentifier(String)
    case ambiguousNestedResponse(linkID: String, answerCount: Int)
    case attachmentResolverRequired(resultIdentifier: String)
    case invalidResolvedAttachment(resultIdentifier: String, reason: String)
    case unsupportedResultType(String)
    case unsupportedChoiceAnswer(resultIdentifier: String)
    case malformedCodedAnswer(resultIdentifier: String)
    case unqualifiedQuantityUnit(resultIdentifier: String, unit: String)
    case temporalConversion(resultIdentifier: String, reason: String)
}


/// Explicit, durable facts required to turn one ResearchKit result into FHIR.
public struct ResearchKitFHIRConversionContext: Sendable {
    public struct Unit: Hashable, Sendable {
        public let system: URL
        public let code: String
        public let display: String

        public init(system: URL, code: String, display: String) {
            self.system = system
            self.code = code
            self.display = display
        }

        public static func ucum(code: String, display: String? = nil) -> Self {
            guard let system = URL(string: "http://unitsofmeasure.org") else {
                preconditionFailure("Static UCUM URL is invalid")
            }
            return Self(
                system: system,
                code: code,
                display: display ?? code
            )
        }
    }

    public let questionnaire: Questionnaire
    public let questionnaireCanonical: String
    public let responseIdentifier: BusinessIdentifier
    public let subject: Reference
    public let authored: Date
    public let authoredTimeZone: TimeZone
    public let author: Reference?
    public let source: Reference?
    public let repositoryID: RepositoryID?
    public let unitsByResultIdentifier: [String: Unit]
    public let attachmentResolver: ResearchKitAttachmentResolver?

    public init(
        questionnaire: Questionnaire,
        responseIdentifier: BusinessIdentifier,
        subject: Reference,
        authored: Date,
        authoredTimeZone: TimeZone,
        author: Reference? = nil,
        source: Reference? = nil,
        repositoryID: RepositoryID? = nil,
        unitsByResultIdentifier: [String: Unit] = [:],
        attachmentResolver: ResearchKitAttachmentResolver? = nil
    ) throws {
        let questionnaireCanonical = try Self.canonical(for: questionnaire)
        try Self.validateQuestionnaireProfile(questionnaire)
        try Self.validateReference(subject, field: "subject", allowedTypes: [.patient])
        if let author {
            try Self.validateReference(
                author,
                field: "author",
                allowedTypes: [.device, .organization, .patient, .practitioner, .practitionerRole, .relatedPerson]
            )
        }
        if let source {
            try Self.validateReference(
                source,
                field: "source",
                allowedTypes: [.patient, .practitioner, .practitionerRole, .relatedPerson]
            )
        }
        try Self.validateLayout(questionnaire.item ?? [])

        self.questionnaire = questionnaire
        self.questionnaireCanonical = questionnaireCanonical
        self.responseIdentifier = responseIdentifier
        self.subject = subject
        self.authored = authored
        self.authoredTimeZone = authoredTimeZone
        self.author = author
        self.source = source
        self.repositoryID = repositoryID
        self.unitsByResultIdentifier = unitsByResultIdentifier
        self.attachmentResolver = attachmentResolver
    }

    private static func validateQuestionnaireProfile(_ questionnaire: Questionnaire) throws {
        let profiles = questionnaire.meta?.profile?.compactMap { $0.value?.url.absoluteString } ?? []
        let required = Profile.groveQuestionnaire.value?.url.absoluteString
        guard profiles.count == 1, profiles.first == required else {
            throw ResearchKitFHIRConversionError.questionnaireProfileRequired
        }
    }

    private static func canonical(for questionnaire: Questionnaire) throws -> String {
        let rawURL = questionnaire.url?.value?.url.absoluteString ?? "<missing>"
        guard let rawVersion = questionnaire.version?.value?.string,
              ResearchKitQuestionnaireCanonical.isValidURL(rawURL),
              ResearchKitQuestionnaireCanonical.isSemanticVersion(rawVersion) else {
            let invalidCanonical = if let version = questionnaire.version?.value?.string {
                "\(rawURL)|\(version)"
            } else {
                rawURL
            }
            throw ResearchKitFHIRConversionError.invalidQuestionnaireCanonical(
                invalidCanonical
            )
        }
        return "\(rawURL)|\(rawVersion)"
    }

    private static func validateReference(
        _ reference: Reference,
        field: String,
        allowedTypes: Set<ResourceType>
    ) throws {
        guard let rawType = reference.type?.value?.url.absoluteString,
              let type = ResourceType(rawValue: rawType),
              allowedTypes.contains(type) else {
            throw ResearchKitFHIRConversionError.invalidReference(field: field)
        }
        do {
            _ = try TypedReference.validate(reference, expectedResourceType: type)
        } catch {
            throw ResearchKitFHIRConversionError.invalidReference(field: field)
        }
    }

    private static func validateLayout(_ items: [QuestionnaireItem]) throws {
        var seen = Set<String>()
        func validate(_ item: QuestionnaireItem) throws {
            guard let linkID = item.linkId.value?.string,
                  linkID == linkID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !linkID.isEmpty,
                  item.type.value != nil else {
                throw ResearchKitFHIRConversionError.invalidQuestionnaireLayout(
                    item.linkId.value?.string ?? "<missing>"
                )
            }
            guard seen.insert(linkID).inserted else {
                throw ResearchKitFHIRConversionError.duplicateQuestionnaireLinkID(linkID)
            }
            if item.repeats?.value?.bool == true {
                switch item.type.value {
                case .choice, .openChoice:
                    break
                case .attachment:
                    throw ResearchKitFHIRConversionError.unsupportedRepeatedAttachment(linkID: linkID)
                default:
                    throw ResearchKitFHIRConversionError.repeatedQuestionnaireItem(linkID)
                }
            }
            if item.itemControl == "check-box", item.repeats?.value?.bool != true {
                throw ResearchKitFHIRConversionError.itemControlCardinalityConflict(linkID: linkID)
            }
            try (item.item ?? []).forEach(validate)
        }
        try items.forEach(validate)
    }
}


extension ORKTaskResult {
    private static var electronicCompletionMode: Extension {
        Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaireresponse-completionMode",
            value: .codeableConcept(CodeableConcept(coding: [
                Coding(
                    code: "ELECTRONIC".asFHIRStringPrimitive(),
                    display: "electronic data".asFHIRStringPrimitive(),
                    system: "http://terminology.hl7.org/CodeSystem/v3-ParticipationMode".asFHIRURIPrimitive()
                )
            ]))
        )
    }

    /// Extracts results from a ResearchKit survey task and converts to a FHIR
    /// `QuestionnaireResponse` using caller-persisted identity, subject, and time facts.
    public func fhirResponse(
        using context: ResearchKitFHIRConversionContext
    ) throws -> QuestionnaireResponse {
        guard identifier == context.questionnaireCanonical else {
            throw ResearchKitFHIRConversionError.taskIdentifierMismatch(
                expected: context.questionnaireCanonical,
                actual: identifier
            )
        }

        var resultsByIdentifier: [String: ORKResult] = [:]
        try collectLeafResults(self, into: &resultsByIdentifier)
        let knownIdentifiers = Set(context.questionnaire.flattenedResearchKitItems.map(\.linkID))
        if let unknown = resultsByIdentifier.keys.first(where: { !knownIdentifiers.contains($0) }) {
            throw ResearchKitFHIRConversionError.unknownResultIdentifier(unknown)
        }

        let questionnaireResponses = try (context.questionnaire.item ?? []).compactMap {
            try responseItem(for: $0, resultsByIdentifier: resultsByIdentifier, context: context)
        }
        
        var questionnaireResponse = QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
        questionnaireResponse.meta = Meta(profile: [Profile.groveQuestionnaireResponse])
        questionnaireResponse.extension = [Self.electronicCompletionMode]
        questionnaireResponse.item = questionnaireResponses
        questionnaireResponse.id = context.repositoryID?.primitive
        questionnaireResponse.identifier = context.responseIdentifier.fhirIdentifier
        questionnaireResponse.subject = context.subject
        questionnaireResponse.author = context.author
        questionnaireResponse.source = context.source
        questionnaireResponse.authored = FHIRPrimitive(try DateTime(
            date: context.authored,
            timeZone: context.authoredTimeZone
        ))
        questionnaireResponse.questionnaire = FHIRPrimitive(
            Canonical(stringLiteral: context.questionnaireCanonical)
        )
        
        return questionnaireResponse
    }

    private func collectLeafResults(
        _ result: ORKResult,
        into resultsByIdentifier: inout [String: ORKResult]
    ) throws {
        if let collection = result as? ORKCollectionResult {
            for child in collection.results ?? [] {
                try collectLeafResults(child, into: &resultsByIdentifier)
            }
            return
        }
        guard resultsByIdentifier.updateValue(result, forKey: result.identifier) == nil else {
            throw ResearchKitFHIRConversionError.duplicateResultIdentifier(result.identifier)
        }
    }

    private func responseItem(
        for questionnaireItem: QuestionnaireItem,
        resultsByIdentifier: [String: ORKResult],
        context: ResearchKitFHIRConversionContext
    ) throws -> QuestionnaireResponseItem? {
        guard let linkID = questionnaireItem.linkId.value?.string,
              let itemType = questionnaireItem.type.value else {
            throw ResearchKitFHIRConversionError.invalidQuestionnaireLayout(
                questionnaireItem.linkId.value?.string ?? "<missing>"
            )
        }
        let childResponses = try (questionnaireItem.item ?? []).compactMap {
            try responseItem(for: $0, resultsByIdentifier: resultsByIdentifier, context: context)
        }

        if itemType == .group {
            guard !childResponses.isEmpty else {
                return nil
            }
            return QuestionnaireResponseItem(
                item: childResponses,
                linkId: linkID.asFHIRStringPrimitive(),
                text: questionnaireItem.text
            )
        }
        if itemType == .display {
            guard childResponses.isEmpty else {
                throw ResearchKitFHIRConversionError.invalidQuestionnaireLayout(linkID)
            }
            return nil
        }

        let response = try resultsByIdentifier[linkID].map { try createResponse($0, using: context) }
        guard var response else {
            guard childResponses.isEmpty else {
                throw ResearchKitFHIRConversionError.ambiguousNestedResponse(linkID: linkID, answerCount: 0)
            }
            return nil
        }
        response.text = questionnaireItem.text
        return try responseByAttaching(
            childResponses,
            to: response,
            itemType: itemType,
            questionnaireItem: questionnaireItem,
            linkID: linkID
        )
    }

    private func responseByAttaching(
        _ childResponses: [QuestionnaireResponseItem],
        to response: QuestionnaireResponseItem,
        itemType: QuestionnaireItemType,
        questionnaireItem: QuestionnaireItem,
        linkID: String
    ) throws -> QuestionnaireResponseItem? {
        var response = response
        if [.choice, .openChoice].contains(itemType),
           questionnaireItem.repeats?.value?.bool != true,
           (response.answer?.count ?? 0) > 1 {
            throw ResearchKitFHIRConversionError.invalidAnswerCardinality(
                linkID: linkID,
                answerCount: response.answer?.count ?? 0
            )
        }
        guard !childResponses.isEmpty else {
            return response.answer == nil ? nil : response
        }
        let answerCount = response.answer?.count ?? 0
        guard answerCount == 1 else {
            throw ResearchKitFHIRConversionError.ambiguousNestedResponse(
                linkID: linkID,
                answerCount: answerCount
            )
        }
        response.answer?[0].item = childResponses
        return response
    }
    
    
    // MARK: Functions for creating FHIR responses from ResearchKit results
    
    private func appendResponseAnswer(_ value: QuestionnaireResponseItemAnswer.ValueX?, to responseAnswers: inout [QuestionnaireResponseItemAnswer]) {
        // A valueless answer would serialize as an empty object, which is invalid FHIR
        // (ele-1) and misreports a skipped question as answered.
        guard let value else {
            return
        }
        var responseAnswer = QuestionnaireResponseItemAnswer()
        responseAnswer.value = value
        responseAnswers.append(responseAnswer)
    }

    private func createResponse(
        _ result: ORKResult,
        using context: ResearchKitFHIRConversionContext
    ) throws -> QuestionnaireResponseItem {
        var response = QuestionnaireResponseItem(linkId: FHIRPrimitive(FHIRString(result.identifier)))
        var responseAnswers: [QuestionnaireResponseItemAnswer] = []
        
        switch result {
        case let result as ORKBooleanQuestionResult:
            appendResponseAnswer(createBooleanResponse(result), to: &responseAnswers)
        case let result as ORKChoiceQuestionResult:
            let values = try createChoiceResponse(result)
            for value in values {
                appendResponseAnswer(value, to: &responseAnswers)
            }
        case let result as ORKFileResult:
            appendResponseAnswer(try createAttachmentResponse(result, using: context), to: &responseAnswers)
        case let result as ORKNumericQuestionResult:
            appendResponseAnswer(try createNumericResponse(result, using: context), to: &responseAnswers)
        case let result as ORKDateQuestionResult:
            appendResponseAnswer(try createDateResponse(result, using: context), to: &responseAnswers)
        case let result as ORKScaleQuestionResult:
            appendResponseAnswer(createScaleResponse(result), to: &responseAnswers)
        case let result as ORKTextQuestionResult:
            appendResponseAnswer(createTextResponse(result), to: &responseAnswers)
        case let result as ORKTimeOfDayQuestionResult:
            appendResponseAnswer(createTimeResponse(result), to: &responseAnswers)
        default:
            throw ResearchKitFHIRConversionError.unsupportedResultType(String(describing: type(of: result)))
        }
        
        // An empty `answer` array is invalid FHIR JSON; omit the element instead.
        response.answer = responseAnswers.isEmpty ? nil : responseAnswers
        return response
    }
    
    private func createNumericResponse(
        _ result: ORKNumericQuestionResult,
        using context: ResearchKitFHIRConversionContext
    ) throws -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let value = result.numericAnswer else {
            return nil
        }
        
        // If a unit is defined, then the result is a Quantity
        if let unit = result.unit {
            guard let governedUnit = context.unitsByResultIdentifier[result.identifier] else {
                throw ResearchKitFHIRConversionError.unqualifiedQuantityUnit(
                    resultIdentifier: result.identifier,
                    unit: unit
                )
            }
            return .quantity(
                Quantity(
                    code: governedUnit.code.asFHIRStringPrimitive(),
                    system: governedUnit.system.asFHIRURIPrimitive(),
                    unit: governedUnit.display.asFHIRStringPrimitive(),
                    value: FHIRPrimitive(FHIRDecimal(value.decimalValue))
                )
            )
        }
        
        if result.questionType == ORKQuestionType.integer {
            return .integer(FHIRPrimitive(FHIRInteger(value.int32Value)))
        } else {
            return .decimal(FHIRPrimitive(FHIRDecimal(value.decimalValue)))
        }
    }

    private func createScaleResponse(_ result: ORKScaleQuestionResult) -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let value = result.scaleAnswer else {
            return nil
        }

        return .integer(FHIRPrimitive(FHIRInteger(value.int32Value)))
    }

    private func createTextResponse(_ result: ORKTextQuestionResult) -> QuestionnaireResponseItemAnswer.ValueX? {
        guard let text = result.textAnswer else {
            return nil
        }
        return .string(FHIRPrimitive(FHIRString(text)))
    }
}


extension Questionnaire {
    fileprivate var flattenedResearchKitItems: [(linkID: String, type: QuestionnaireItemType)] {
        func flatten(_ items: [QuestionnaireItem]) -> [(String, QuestionnaireItemType)] {
            items.flatMap { item in
                let own: [(String, QuestionnaireItemType)] = if let linkID = item.linkId.value?.string,
                                                                let type = item.type.value {
                    [(linkID, type)]
                } else {
                    []
                }
                return own + flatten(item.item ?? [])
            }
        }
        return flatten(item ?? [])
    }
}
#endif
