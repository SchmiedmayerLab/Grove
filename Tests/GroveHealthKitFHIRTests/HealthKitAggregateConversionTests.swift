//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HealthKitFHIRAggregateConversionTests {
    struct MethodCase: CustomTestStringConvertible, Sendable {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let value: Double
        let measurement: MeasurementContract

        var testDescription: String { measurement.id }
    }

    static let methodCases: [MethodCase] = [
        MethodCase(
            identifier: .walkingHeartRateAverage,
            unit: .count().unitDivided(by: .minute()),
            value: 104,
            measurement: HealthKitMeasurementCatalog.walkingHeartRateAverage
        ),
        MethodCase(
            identifier: .atrialFibrillationBurden,
            unit: .percent(),
            value: 0.042,
            measurement: HealthKitMeasurementCatalog.atrialFibrillationBurden
        ),
        MethodCase(
            identifier: .appleWalkingSteadiness,
            unit: .percent(),
            value: 0.71,
            measurement: HealthKitMeasurementCatalog.walkingSteadiness
        ),
        MethodCase(
            identifier: .sixMinuteWalkTestDistance,
            unit: .meter(),
            value: 512,
            measurement: HealthKitMeasurementCatalog.sixMinuteWalkTestDistance
        )
    ]

    private let converter = HealthKitConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private var context: HealthKitConversionContext {
        HealthKitConversionContext(
            subject: .testPatient,
            converter: HealthKitApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
    }

    private func quantitySample(
        _ type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        value: Double,
        interval: TimeInterval = 3_600,
        metadata: [String: Any] = [:]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(type),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: timestamp,
            end: timestamp.addingTimeInterval(interval),
            metadata: metadata
        )
    }

    @Test("Windowed aggregates carry their fixed aggregation method", arguments: methodCases)
    func aggregateMethod(testCase: MethodCase) throws {
        let sample = quantitySample(testCase.identifier, unit: testCase.unit, value: testCase.value)
        let observation = try converter.convert(sample, context: context).observation
        let method = try #require(testCase.measurement.method)
        let coding = try #require(observation.method?.coding?.first)

        #expect(coding.system == Canonicals.aggregationMethodCodeSystem)
        #expect(coding.code?.value?.string == method.code)
        #expect(coding.display?.value?.string == method.display)
        #expect(observation.effective?.isPeriod == true)
    }

    @Test("A point measurement asserts no aggregation method")
    func pointMeasurementsHaveNoMethod() throws {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let observation = try converter.convert(sample, context: context).observation
        let resting = try converter.convert(
            quantitySample(.restingHeartRate, unit: .count().unitDivided(by: .minute()), value: 58),
            context: context
        ).observation

        #expect(observation.method == nil)
        #expect(MeasurementCatalog.heartRate.method == nil)
        #expect(resting.method == nil)
        #expect(resting.effective?.isPeriod == false)
        #expect(MeasurementCatalog.restingHeartRate.effective == .dateTime)
        #expect(resting.code.coding?.map {
            [
                $0.system?.value?.url.absoluteString ?? "",
                $0.code?.value?.string ?? ""
            ]
        } == [
            ["http://loinc.org", "40443-4"],
            ["http://loinc.org", "8867-4"]
        ])
    }

    @Test("Sleeping breathing disturbances normalize to events per hour of the session")
    func sessionRateNormalizesToHours() throws {
        let sample = quantitySample(
            .appleSleepingBreathingDisturbances,
            unit: .count(),
            value: 21,
            interval: 7 * 3_600
        )
        let observation = try converter.convert(sample, context: context).observation
        let quantity: Quantity = try #require({
            guard case .quantity(let quantity) = observation.value else {
                return nil
            }
            return quantity
        }())

        #expect(quantity.code?.value?.string == "/h")
        #expect(quantity.value?.value?.decimal.description == "3")
        #expect(observation.method?.coding?.first?.code?.value?.string == "session-rate")
    }

    // HealthKit validates the reason key and its value while building the sample, so the
    // converter's missing-metadata and unknown-value guards stay defensive and untestable here.
    @Test(
        "Insulin delivery retains its delivery reason as a component",
        arguments: [HKInsulinDeliveryReason.basal, .bolus]
    )
    func insulinDeliveryReasonIsRetained(reason: HKInsulinDeliveryReason) throws {
        let sample = quantitySample(
            .insulinDelivery,
            unit: .internationalUnit(),
            value: 4.5,
            metadata: [HKMetadataKeyInsulinDeliveryReason: NSNumber(value: reason.rawValue)]
        )
        let observation = try converter.convert(sample, context: context).observation
        let component = try #require(observation.component?.first)
        let expected = reason == .basal ? "basal" : "bolus"

        #expect(component.code.coding?.first?.code?.value?.string == HKMetadataKeyInsulinDeliveryReason)
        #expect(component.code.coding?.first?.system == Canonicals.healthKitMetadataKey)
        #expect({
            guard case .codeableConcept(let concept) = component.value else {
                return nil as String?
            }
            return concept.coding?.first?.code?.value?.string
        }() == expected)
    }

    @Test("Rows outside this converter's Observation surface fail closed with their catalog reason")
    func unconvertibleRowsFailClosedWithTheirCatalogReason() throws {
        let clinical = "HKClinicalTypeIdentifierLabResultRecord"
        #expect(
            HealthKitConverter.unconvertibleSampleError(forSourceTypeIdentifier: clinical)
                == .platformExclusiveDocument(sampleType: clinical)
        )

        let workout = HKWorkoutType.workoutType().identifier
        #expect(
            HealthKitConverter.unconvertibleSampleError(forSourceTypeIdentifier: workout)
                == .notYetConvertible(sampleType: workout)
        )

        let systolic = HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
        #expect(
            HealthKitConverter.unconvertibleSampleError(forSourceTypeIdentifier: systolic)
                == .componentSampleRequiresCorrelation(sampleType: systolic)
        )

        let alert = "HKQuantityTypeIdentifierNikeFuel"
        let entry = try #require(HealthKitCatalog.entry(forSourceTypeIdentifier: alert))
        let reason = try #require(entry.requirement)
        #expect(
            HealthKitConverter.unconvertibleSampleError(forSourceTypeIdentifier: alert)
                == .intentionallyUnsupported(sampleType: alert, reason: reason)
        )

        let deferredType = "HKDataTypeIdentifierHeartbeatSeries"
        #expect(
            HealthKitConverter.unconvertibleSampleError(forSourceTypeIdentifier: deferredType)
                == .platformExclusiveDocument(sampleType: deferredType)
        )
    }
}


extension Observation.EffectiveX {
    fileprivate var isPeriod: Bool {
        if case .period = self {
            return true
        }
        return false
    }
}

#endif
