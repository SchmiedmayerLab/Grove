//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)
import Foundation
@testable import GroveQuestionnaireExtraction
import HealthKit
import ModelsR4
import Testing


/// Projects the guide's Home Vitals pair into HealthKit samples.
@Suite("Questionnaire HealthKit Sample Projection")
struct HealthKitSampleProjectionTests {
    private static func pair() throws -> (ModelsR4.Questionnaire, ModelsR4.QuestionnaireResponse) {
        func fixture<Resource: Decodable>(_ name: String) throws -> Resource {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
            return try JSONDecoder().decode(Resource.self, from: Data(contentsOf: url))
        }
        return (try fixture("HomeVitals_questionnaire"), try fixture("HomeVitals_response"))
    }

    @Test("The pair becomes a weight sample, a blood pressure correlation, and a step count")
    func projectsTheDocumentedSamples() throws {
        let (questionnaire, response) = try Self.pair()
        let samples = try QuestionnaireHealthKitSampleProjection.samples(
            questionnaire: questionnaire,
            response: response
        )
        #expect(samples.count == 3)

        let weight = try #require(samples.compactMap { $0 as? HKQuantitySample }.first {
            $0.quantityType == HKQuantityType(.bodyMass)
        })
        #expect(weight.quantity.doubleValue(for: .gramUnit(with: .kilo)) == 72.5)

        let pressure = try #require(samples.compactMap { $0 as? HKCorrelation }.first)
        #expect(pressure.correlationType == HKCorrelationType(.bloodPressure))
        let readings = pressure.objects.compactMap { $0 as? HKQuantitySample }
        let values = Set(readings.map { $0.quantity.doubleValue(for: .millimeterOfMercury()) })
        #expect(values == [118, 76])

        let steps = try #require(samples.compactMap { $0 as? HKQuantitySample }.first {
            $0.quantityType == HKQuantityType(.stepCount)
        })
        #expect(steps.quantity.doubleValue(for: .count()) == 8432)
        #expect(steps.startDate == weight.startDate)
    }

    @Test("A measurement HealthKit does not model refuses instead of guessing")
    func unmappableMeasurementRefuses() throws {
        var (questionnaire, response) = try Self.pair()
        var item = QuestionnaireItem(
            linkId: "bleeding".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        item.code = [
    Coding(
                code: "intermenstrual-bleeding".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(
                    stringLiteral: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-mobile-measurement"
                ))
            )
        ]
        item.extension = [
    Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.observationExtract)),
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            )
        ]
        questionnaire.item = (questionnaire.item ?? []) + [item]
        var answered = QuestionnaireResponseItem(linkId: "bleeding".asFHIRStringPrimitive())
        answered.answer = [
    QuestionnaireResponseItemAnswer(value: .coding(Coding(
                code: "present".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(
                    stringLiteral: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-intermenstrual-bleeding"
                ))
            )))
        ]
        response.item = (response.item ?? []) + [answered]
        #expect(throws: QuestionnaireHealthKitSampleError.measurementNotMappable(
            id: "intermenstrual-bleeding"
        )) {
            try QuestionnaireHealthKitSampleProjection.samples(
                questionnaire: questionnaire,
                response: response
            )
        }
    }
}
#endif
