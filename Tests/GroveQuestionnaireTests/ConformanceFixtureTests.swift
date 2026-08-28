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


/// Writes the Questionnaire and QuestionnaireResponse shapes Grove publishes for the
/// cross-repository HL7 validator job.
@Suite
struct QuestionnaireConformanceFixtureTests {
    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/conformance-fixtures/questionnaire")
    }

    @Test
    func writeConformanceFixtures() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(
                id: "daily-check-in",
                url: URL(string: "https://example.org/fhir/Questionnaire/daily-check-in"),
                version: "1.0.0",
                title: "Daily Check-In",
                explainer: "A compact conformance fixture.",
                entryMode: .sequential
            ),
            sections: [
                .init(id: "daily", tasks: [
                    .init(id: "well", title: "Are you feeling well?", kind: .boolean),
                    .init(
                        id: "temperature",
                        title: "Temperature",
                        kind: .numeric(.init(
                            inputMode: .numberPad(.decimal),
                            minimum: 30,
                            maximum: 45,
                            maxDecimalPlaces: 1,
                            unit: "(degree Celsius)",
                            unitSystem: URL(string: "http://unitsofmeasure.org"),
                            unitCode: "Cel",
                            valueKind: .quantity
                        ))
                    )
                ])
            ]
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["well"] = .init(value: .bool(true))
        responses.responses["temperature"] = .init(value: .quantity(36.8, unitCode: "Cel"))

        let pair = try ResourceBuilder().pair(
            from: responses,
            subject: Reference(reference: "Patient/example"),
            authored: Date(timeIntervalSince1970: 1_700_000_000),
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        let fixtures: [String: ResourceProxy] = [
            "questionnaire": ResourceProxy(with: pair.questionnaire),
            "questionnaire-response": ResourceProxy(with: pair.response)
        ]
        #expect(fixtures.count == 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try FileManager.default.createDirectory(at: Self.fixtureDirectory, withIntermediateDirectories: true)
        for (name, resource) in fixtures {
            try encoder.encode(resource).write(to: Self.fixtureDirectory.appendingPathComponent("\(name).json"))
        }
    }
}
