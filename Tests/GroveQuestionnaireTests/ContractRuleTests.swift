//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing


@Suite
struct GroveQuestionnaireFHIRContractTests {
    private static let canonical = URL(string: "https://example.org/fhir/Questionnaire/check-in")!

    private func responses() -> QuestionnaireResponses {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: Self.canonical,
            version: "2.1.0",
            title: "Daily Check-In"
        ) {
            Section("daily") {
                BooleanQuestion("well", "Are you feeling well?")
            }
        }
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["well"] = .init(value: .bool(true))
        return responses
    }

    @Test
    func builderProducesTheExactVersionedPair() throws {
        let pair = try ResourceBuilder().pair(
            from: responses(),
            authored: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(pair.questionnaire.id == nil)
        #expect(pair.response.id == nil)
        #expect(pair.questionnaire.meta?.profile == [Profile.groveQuestionnaire])
        #expect(pair.response.meta?.profile == [Profile.groveQuestionnaireResponse])
        #expect(pair.response.questionnaire?.value?.url == Self.canonical)
        #expect(pair.response.questionnaire?.value?.version == "2.1.0")
        #expect(pair.response.identifier?.system?.value?.url == Self.canonical)
        #expect(pair.response.identifier?.value?.value?.string.isEmpty == false)
        #expect(PairValidator().issues(
            questionnaire: pair.questionnaire,
            response: pair.response
        ).isEmpty)
    }

    @Test
    func repositoryIDsAreOnlyWrittenWhenExplicitlyAssigned() throws {
        let questionnaireID = try RepositoryID("questionnaire-42")
        let responseID = try RepositoryID("response-42")
        let pair = try ResourceBuilder().pair(
            from: responses(),
            questionnaireRepositoryID: questionnaireID,
            responseRepositoryID: responseID,
            authored: questionnaireResponseTestAuthoredAt
        )

        #expect(pair.questionnaire.id?.value?.string == "questionnaire-42")
        #expect(pair.response.id?.value?.string == "response-42")
    }

    @Test
    func pairValidationRejectsCanonicalDrift() throws {
        let valid = try ResourceBuilder().pair(
            from: responses(),
            authored: questionnaireResponseTestAuthoredAt
        )
        var drifted = valid.response
        drifted.questionnaire = FHIRPrimitive(Canonical(
            stringLiteral: "https://example.org/fhir/Questionnaire/check-in|2.0.0"
        ))

        let issues = PairValidator().issues(
            questionnaire: valid.questionnaire,
            response: drifted
        )
        #expect(issues.contains { $0.code == .questionnaireCanonical })
        #expect(throws: ContractError.self) {
            try ResourcePair(
                questionnaire: valid.questionnaire,
                response: drifted
            )
        }
    }

    @Test
    func pairValidationRejectsWrongAnswerTypesAndUnknownItems() throws {
        let valid = try ResourceBuilder().pair(
            from: responses(),
            authored: questionnaireResponseTestAuthoredAt
        )
        var drifted = valid.response
        drifted.item = [
            QuestionnaireResponseItem(
                answer: [QuestionnaireResponseItemAnswer(value: .string("yes".asFHIRStringPrimitive()))],
                linkId: "unknown".asFHIRStringPrimitive(),
                text: "Are you feeling well?".asFHIRStringPrimitive()
            )
        ]

        let issues = PairValidator().issues(
            questionnaire: valid.questionnaire,
            response: drifted
        )
        #expect(issues.contains { $0.code == .itemUnknown })
    }

    @Test
    func pairValidationChecksPrimitiveInlineOptionsByValue() throws {
        let valid = try ResourceBuilder().pair(
            from: responses(),
            authored: questionnaireResponseTestAuthoredAt
        )
        var questionnaire = valid.questionnaire
        var questionnaireGroup = try #require(questionnaire.item?.first)
        var questionnaireItem = try #require(questionnaireGroup.item?.first)
        questionnaireItem.type = FHIRPrimitive(.string)
        questionnaireItem.answerOption = [
            QuestionnaireItemAnswerOption(
                value: .string("allowed".asFHIRStringPrimitive())
            )
        ]
        questionnaireGroup.item = [questionnaireItem]
        questionnaire.item = [questionnaireGroup]

        var response = valid.response
        var responseGroup = try #require(response.item?.first)
        var responseItem = try #require(responseGroup.item?.first)
        responseItem.answer = [
            QuestionnaireResponseItemAnswer(
                value: .string("different".asFHIRStringPrimitive())
            )
        ]
        responseGroup.item = [responseItem]
        response.item = [responseGroup]

        let issues = PairValidator().issues(
            questionnaire: questionnaire,
            response: response
        )
        #expect(issues.contains { $0.code == .answerOption })
    }

    @Test(arguments: ["1", "01.0.0", "1.0", "1.0.0.0", "v1.0.0"])
    func invalidVersionsFailClosed(_ version: String) throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: Self.canonical,
            version: version,
            title: "Invalid"
        ) {
            Section("daily") {
                BooleanQuestion("well", "Are you feeling well?")
            }
        }
        #expect(throws: ContractError.self) {
            try ModelsR4.Questionnaire(questionnaire)
        }
    }

    @Test
    func exportSurfaceDoesNotExtractObservations() throws {
        let pair = try ResourceBuilder().pair(
            from: responses(),
            authored: questionnaireResponseTestAuthoredAt
        )
        let encodedResources = [
            try JSONEncoder().encode(ResourceProxy(with: pair.questionnaire)),
            try JSONEncoder().encode(ResourceProxy(with: pair.response))
        ]
        let resourceTypes = try encodedResources.map { data in
            try #require((JSONSerialization.jsonObject(with: data) as? [String: Any])?["resourceType"] as? String)
        }
        #expect(resourceTypes == ["Questionnaire", "QuestionnaireResponse"])
    }
}
