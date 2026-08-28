//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Testing


/// Covers the in-progress response lifecycle: draft snapshots, resume, version
/// pinning, and in-progress FHIR export.
@Suite
struct DraftLifecycleTests {
    private func makeQuestionnaire(version: String? = "1.0.0") -> GroveQuestionnaire.Questionnaire {
        GroveQuestionnaire.Questionnaire(
            metadata: .init(
                id: "https://example.org/fhir/Questionnaire/draft-test",
                url: URL(string: "https://example.org/fhir/Questionnaire/draft-test"),
                version: version,
                title: "Draft Test",
                explainer: ""
            ),
            sections: [
                .init(id: "s1", tasks: [
                    .init(id: "mood", title: "Mood?", kind: .boolean),
                    .init(id: "note", title: "Notes", kind: .freeText(.init())),
                    .init(id: "weight", title: "Weight", kind: .numeric(.init(inputMode: .numberPad(.decimal))))
                ])
            ]
        )
    }

    @Test
    func draftRoundTripsThroughCodable() throws {
        let questionnaire = makeQuestionnaire()
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["mood"] = .init(value: .bool(true))
        responses.responses["note"] = .init(value: .string("feeling fine"))
        responses.responses["weight"] = .init(value: .number(72.5))

        let data = try JSONEncoder().encode(try responses.draft())
        let decoded = try JSONDecoder().decode(QuestionnaireResponses.Draft.self, from: data)
        let resumed = try QuestionnaireResponses(questionnaire: questionnaire, resuming: decoded)
        #expect(resumed.id == responses.id)
        #expect(resumed.responses["mood"].value == .bool(true))
        #expect(resumed.responses["note"].value == .string("feeling fine"))
        #expect(resumed.responses["weight"].value == .number(72.5))
    }

    @Test
    func draftRefusesDifferentQuestionnaireVersion() throws {
        let responses = QuestionnaireResponses(questionnaire: makeQuestionnaire(version: "1.0.0"))
        responses.responses["mood"] = .init(value: .bool(false))
        let draft = try responses.draft()
        #expect(throws: QuestionnaireResponses.DraftError.self) {
            try QuestionnaireResponses(questionnaire: makeQuestionnaire(version: "2.0.0"), resuming: draft)
        }
    }

    @Test
    func choiceDraftPreservesSelectionsAndOtherText() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(id: "q", url: nil, title: "", explainer: ""),
            sections: [
                .init(id: "s1", tasks: [
                    .init(id: "pick", title: "Pick", kind: .choice(.init(
                        options: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
                        hasFreeTextOtherOption: true,
                        allowsMultipleSelection: true
                    )))
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["pick"] = .init(value: .choice(.init(selectedOptions: ["a", "b"], freeTextOtherResponse: "custom")))
        let resumed = try QuestionnaireResponses(questionnaire: questionnaire, resuming: try responses.draft())
        #expect(resumed.responses["pick"].value.choiceValue.selectedOptions == ["a", "b"])
        #expect(resumed.responses["pick"].value.choiceValue.freeTextOtherResponse == "custom")
    }

    @Test
    func inProgressExportCarriesStatus() throws {
        let questionnaire = makeQuestionnaire()
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["mood"] = .init(value: .bool(true))
        let fhirResponse = try ModelsR4.QuestionnaireResponse(
            responses,
            status: .inProgress,
            authored: questionnaireResponseTestAuthoredAt
        )
        #expect(fhirResponse.status.value == .inProgress)
        // The default remains a completed response.
        let completed = try ModelsR4.QuestionnaireResponse(
            responses,
            authored: questionnaireResponseTestAuthoredAt
        )
        #expect(completed.status.value == .completed)
    }
}
