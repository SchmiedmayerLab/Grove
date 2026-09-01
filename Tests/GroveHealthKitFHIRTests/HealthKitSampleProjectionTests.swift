//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// Projects Grove observations back into the HealthKit samples they describe.
@Suite("HealthKit Sample Projection")
struct HealthKitSampleProjectionTests {
    private static let effective = "2026-08-24T07:41:00-07:00"

    private static func observation(
        contract: MeasurementContract,
        value: Decimal? = nil,
        manualEntry: Bool = true
    ) throws -> ModelsR4.Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(
                    code: contract.code.code.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: contract.code.system))
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.effective = .dateTime(FHIRPrimitive(try DateTime(effective)))
        if let value, let quantity = contract.quantity {
            observation.value = .quantity(Quantity(
                code: quantity.code.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: quantity.system)),
                unit: quantity.unit.asFHIRStringPrimitive(),
                value: FHIRPrimitive(FHIRDecimal(value))
            ))
        }
        if manualEntry {
            observation.extension = [
                Extension(
                    url: Canonicals.recordingMethod,
                    value: .coding(
                        Coding(code: "manual-entry", system: Canonicals.recordingMethodCodeSystem)
                    )
                )
            ]
        }
        return observation
    }

    @Test("A weight observation lands as a body-mass sample with its stated envelope")
    func weightProjectsWithEnvelope() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        let sample = try #require(HealthKitSampleProjection.sample(for: observation) as? HKQuantitySample)
        #expect(sample.quantityType == HKQuantityType(.bodyMass))
        #expect(sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) == 72.5)
        #expect(sample.startDate == sample.endDate)
        #expect(sample.startDate == (try DateTime(Self.effective).asNSDate()))
        #expect(sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true)
        #expect(sample.metadata?[HKMetadataKeyTimeZone] as? String == "GMT-0700")
        #expect(sample.metadata?[HKMetadataKeySyncIdentifier] == nil)
    }

    @Test("A sync identifier makes re-projection replace, and an amendment outrank the original")
    func syncIdentityFollowsTheObservation() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        let first = try HealthKitSampleProjection.sample(for: observation, syncIdentifier: "response-1|weight")
        #expect(first.metadata?[HKMetadataKeySyncIdentifier] as? String == "response-1|weight")
        #expect(first.metadata?[HKMetadataKeySyncVersion] as? Int == 1)

        observation.status = FHIRPrimitive(.amended)
        let amended = try HealthKitSampleProjection.sample(for: observation, syncIdentifier: "response-1|weight")
        #expect(amended.metadata?[HKMetadataKeySyncVersion] as? Int == 2)
    }

    @Test("An exchange observation syncs under its own minted source-output identity")
    func mintedIdentityBecomesTheSyncIdentifier() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.identifier = [
            Identifier(
                type: CodeableConcept(coding: [
                    Coding(
                        code: "source-output".asFHIRStringPrimitive(),
                        system: Canonicals.identifierRoleCodeSystem
                    )
                ]),
                value: "v0:installation:1:digest".asFHIRStringPrimitive()
            )
        ]

        let sample = try HealthKitSampleProjection.sample(for: observation)
        #expect(sample.metadata?[HKMetadataKeySyncIdentifier] as? String == "v0:installation:1:digest")

        let overridden = try HealthKitSampleProjection.sample(for: observation, syncIdentifier: "explicit")
        #expect(overridden.metadata?[HKMetadataKeySyncIdentifier] as? String == "explicit")
    }

    @Test("A blood pressure panel becomes one correlation with both readings")
    func bloodPressureBecomesACorrelation() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bloodPressure)
        observation.component = MeasurementCatalog.bloodPressure.components.map { component in
            ObservationComponent(
                code: CodeableConcept(coding: [
                    Coding(
                        code: component.code.asFHIRStringPrimitive(),
                        system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
                    )
                ]),
                value: .quantity(Quantity(
                    code: "mm[Hg]".asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: "http://unitsofmeasure.org")),
                    unit: "mmHg".asFHIRStringPrimitive(),
                    value: FHIRPrimitive(FHIRDecimal(component.id == "systolic" ? 118 : 76))
                ))
            )
        }
        let correlation = try #require(HealthKitSampleProjection.sample(for: observation) as? HKCorrelation)
        #expect(correlation.correlationType == HKCorrelationType(.bloodPressure))
        let readings = correlation.objects.compactMap { $0 as? HKQuantitySample }
        #expect(Set(readings.map { $0.quantity.doubleValue(for: .millimeterOfMercury()) }) == [118, 76])
        #expect(correlation.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true)
    }

    @Test("A panel missing a reading refuses instead of writing half a correlation")
    func incompleteBloodPressureRefuses() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.bloodPressure)
        #expect(throws: HealthKitSampleProjectionError.componentMissing(id: "blood-pressure", code: "8480-6")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }

    @Test("A code naming no Grove measurement refuses")
    func unknownCodeRefuses() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.code = CodeableConcept(coding: [
            Coding(
                code: "0000-0".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: "http://loinc.org"))
            )
        ])
        #expect(throws: HealthKitSampleProjectionError.measurementUnknown(system: "http://loinc.org", code: "0000-0")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }

    @Test("A measurement bound to several HealthKit types refuses instead of guessing")
    func ambiguousMeasurementRefuses() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.speed, value: 3)
        #expect(throws: HealthKitSampleProjectionError.measurementNotMappable(id: "speed")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }

    @Test("A value stated under another dimension's unit refuses instead of reaching HealthKit")
    func mismatchedUnitRefuses() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.value = .quantity(Quantity(
            code: "mm[Hg]".asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: "http://unitsofmeasure.org")),
            unit: "mmHg".asFHIRStringPrimitive(),
            value: FHIRPrimitive(FHIRDecimal(72.5))
        ))
        #expect(throws: HealthKitSampleProjectionError.unitNotMappable(code: "mm[Hg]")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }

    @Test("A blood pressure reading under another dimension's unit refuses")
    func mismatchedComponentUnitRefuses() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bloodPressure)
        observation.component = MeasurementCatalog.bloodPressure.components.map { component in
            ObservationComponent(
                code: CodeableConcept(coding: [
                    Coding(
                        code: component.code.asFHIRStringPrimitive(),
                        system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
                    )
                ]),
                value: .quantity(Quantity(
                    code: "kg".asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: "http://unitsofmeasure.org")),
                    unit: "kg".asFHIRStringPrimitive(),
                    value: FHIRPrimitive(FHIRDecimal(118))
                ))
            )
        }
        #expect(throws: HealthKitSampleProjectionError.unitNotMappable(code: "kg")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }

    @Test("An observation without a value refuses")
    func valueMissingRefuses() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.bodyWeight)
        #expect(throws: HealthKitSampleProjectionError.valueMissing(id: "body-weight")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }

    @Test("A carried writer record version outranks the status-derived one")
    func writerRecordVersionBecomesTheSyncVersion() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.extension = (observation.extension ?? []) + [
            Extension(url: Canonicals.writerRecordVersion, value: .string("7".asFHIRStringPrimitive()))
        ]
        let sample = try HealthKitSampleProjection.sample(for: observation, syncIdentifier: "response-1|weight")
        #expect(sample.metadata?[HKMetadataKeySyncVersion] as? Int == 7)
    }

    @Test("An observation without an effective instant refuses")
    func effectiveMissingRefuses() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.effective = nil
        #expect(throws: HealthKitSampleProjectionError.effectiveMissing(id: "body-weight")) {
            try HealthKitSampleProjection.sample(for: observation)
        }
    }
}
