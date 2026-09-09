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
struct QuestionnaireWriterContextTests {
    private func responses() -> QuestionnaireResponses {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/check-in")!,
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
    func builderAppliesWriterContextBeforePairValidation() throws {
        let application = try BusinessIdentifier(
            system: "https://example.org/fhir/NamingSystem/application",
            value: "org.example.study"
        )
        let writerContext = try QuestionnaireWriterContext(
            applicationIdentifier: application,
            applicationName: "Example Study",
            applicationVersion: "1.2.3",
            applicationBuild: "45",
            hostModel: "iPhone17,1",
            hostOperatingSystemVersion: "26.0"
        )

        let pair = try ResourceBuilder().pair(
            from: responses(),
            writerContext: writerContext,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )

        let extensionValue = try #require(pair.response.extension?.first {
            $0.url == QuestionnaireWriterContext.canonicalURL
        })
        let children = try #require(extensionValue.extension)
        #expect(children.map { $0.url.value?.url.absoluteString } == [
            "applicationIdentifier",
            "applicationName",
            "applicationVersion",
            "applicationBuild",
            "hostModel",
            "hostOperatingSystemVersion"
        ])
        #expect(children[0].value == .identifier(application.fhirIdentifier))
    }

    @Test
    func applyingWriterContextIsIdempotent() throws {
        let first = try context(applicationValue: "org.example.first", name: "First", version: "1.0.0")
        let second = try context(applicationValue: "org.example.second", name: "Second", version: "2.0.0")
        var response = try ResourceBuilder().response(
            from: responses(),
            writerContext: first,
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )

        response.apply(writerContext: second)

        let writerContexts = response.extension?.filter {
            $0.url == QuestionnaireWriterContext.canonicalURL
        }
        let retained = try #require(writerContexts?.first?.extension)
        #expect(writerContexts?.count == 1)
        #expect(retained[1].value == .string("Second".asFHIRStringPrimitive()))
    }

    @Test
    func canonicalIdentityDistinguishesQuestionnaireVersions() throws {
        let valid = try ResourceBuilder().pair(
            from: responses(),
            authored: questionnaireResponseTestAuthoredAt,
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        let current = try #require(valid.response.questionnaireCanonicalIdentity)
        let next = try #require(QuestionnaireCanonicalIdentity(FHIRPrimitive(Canonical(
            stringLiteral: "https://example.org/fhir/Questionnaire/check-in|3.0.0"
        ))))

        #expect(current.url == next.url)
        #expect(current != next)
    }

    @Test
    func businessIdentifierCreatesTypedLogicalReference() throws {
        let identifier = try BusinessIdentifier(
            system: "https://example.org/fhir/NamingSystem/participant",
            value: "participant-42"
        )

        let reference = identifier.reference(to: .patient)

        #expect(reference.identifier == identifier.fhirIdentifier)
        #expect(reference.type?.value?.url.absoluteString == "Patient")
        #expect(reference.reference == nil)
        #expect(try TypedReference.validate(reference, expectedResourceType: .patient)
            == .identifier(type: .patient, identifier: identifier))
    }

    private func context(
        applicationValue: String,
        name: String,
        version: String
    ) throws -> QuestionnaireWriterContext {
        try QuestionnaireWriterContext(
            applicationIdentifier: BusinessIdentifier(
                system: "https://example.org/fhir/NamingSystem/application",
                value: applicationValue
            ),
            applicationName: name,
            applicationVersion: version
        )
    }
}
