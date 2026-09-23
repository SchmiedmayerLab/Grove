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
                language: "en-US",
                title: .init("Daily Check-In", translations: ["es-US": "Control diario"]),
                explainer: .init("A compact conformance fixture.", translations: ["es-US": "Un caso de conformidad compacto."]),
                entryMode: .sequential
            ),
            sections: [
                .init(id: "daily", tasks: [
                    .init(id: "well", title: .init("Are you feeling well?", translations: ["es-US": "¿Se siente bien?"]), kind: .boolean),
                    .init(
                        id: "temperature",
                        title: .init("Temperature", translations: ["es-US": "Temperatura"]),
                        kind: .numeric(.init(
                            inputMode: .numberPad(.decimal),
                            minimum: 30,
                            maximum: 45,
                            maxDecimalPlaces: 1,
                            unit: .init("(degree Celsius)", translations: ["es-US": "(grado Celsius)"]),
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
            // Rendered in a translation, so the pair exercises `language` and the omitted item text.
            renderedIn: Locale(identifier: "es_US"),
            authored: Date(timeIntervalSince1970: 1_700_000_000),
            authoredTimeZone: questionnaireResponseTestTimeZone
        )
        #expect(pair.questionnaire.subjectType?.map(\.value) == [.patient])
        #expect(pair.response.language?.value?.string == "es-US")
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
