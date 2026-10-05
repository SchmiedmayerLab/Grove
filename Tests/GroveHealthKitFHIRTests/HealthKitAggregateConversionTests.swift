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

    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private var inputs: ExportInputs {
        var inputs = ExportInputs()
        inputs.converter = ApplicationDevice.test(
            name: "Example Study",
            bundleIdentifier: "org.grovealliance.example-study",
            version: "2.0.0 (42)"
        )
        inputs.graphIdentifierSystem = "https://study.example.org/fhir/identifiers/mobile-graph"
        inputs.instant = timestamp
        return inputs
    }

    /// The assembly under the test context's scope, and a request for one event of that context.
    private static func assembly() -> (HealthKitAssembly, HealthKitAssembly.Request) {
        let base = TestEvent.test()
        let assembly = HealthKitAssembly(scope: ExchangeEnvelope.Scope(
            adapter: HealthKitAssembly.adapter,
            identityScope: base.identityScope,
            subject: base.subject,
            repositoryScope: base.repositoryScope
        ))
        let facts = ExchangeEventFacts(application: base.application, host: base.host, studies: [])
        return (assembly, HealthKitAssembly.Request(event: base.event, instant: base.conversionInstant, facts: facts))
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
        let observation = try ExporterFixtures.export(sample, inputs).observation
        let method = try #require(testCase.measurement.method)
        let coding = try #require(observation.method?.coding?.first)

        #expect(coding.system == Canonicals.aggregationMethodCodeSystem)
        #expect(coding.code?.value?.string == method.code)
        #expect(coding.display?.value?.string == method.display)
        #expect(observation.effective?.isPeriod == true)
    }

    @Test("A point measurement asserts no aggregation method")
    func pointMeasurementsHaveNoMethod() throws {
        let sample = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72, interval: 0)
        let observation = try ExporterFixtures.export(sample, inputs).observation
        let resting = try ExporterFixtures.export(
            quantitySample(.restingHeartRate, unit: .count().unitDivided(by: .minute()), value: 58),
            inputs
        ).observation

        #expect(observation.method == nil)
        #expect(observation.effective?.isPeriod == false)
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

    @Test("Sleeping breathing disturbances pass HealthKit's per-hour rate through unchanged")
    func sessionRatePassesPlatformRateThrough() throws {
        // HealthKit stores this type as events per hour already; a night-long sample must not be divided again.
        let sample = quantitySample(
            .appleSleepingBreathingDisturbances,
            unit: .count(),
            value: 4.2,
            interval: 7 * 3_600
        )
        let observation = try ExporterFixtures.export(sample, inputs).observation
        let quantity: Quantity = try #require({
            guard case .quantity(let quantity) = observation.value else {
                return nil
            }
            return quantity
        }())

        #expect(quantity.code?.value?.string == "/h")
        #expect(quantity.value?.value?.decimal.description == "4.2")
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
        let observation = try ExporterFixtures.export(sample, inputs).observation
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

    /// The refusal of every registered type's bare sample, written out rather than derived from the rule the plans
    /// compile: an admitted type no path emits yet is not yet convertible, a type admitted only as a recording document
    /// is platform exclusive, and only an identifier outside the inventory is an unsupported source type. A deletion
    /// of a type with no outputs is refused for the same reason by the assembly's retraction, which the exporter never
    /// reaches for such a type: it reports that the deletion has nothing to retract.
    @Test("Every registered type a bare sample cannot convert is refused for what its catalog row states")
    func unconvertibleRowsFailClosedWithTheirCatalogReason() throws {
        let notYetConvertible: Set<HealthKitSourceType> = [
            .food, .audiogram, .biologicalSex, .bloodType, .dateOfBirth, .fitzpatrickSkinType, .wheelchairUse,
            .visionPrescription, .medicationDoseEvent, .userAnnotatedMedicationConcept
        ]
        let recordingDocuments: Set<HealthKitSourceType> = [
            .heartbeatSeries, .workoutRoute, .cda, .allergyRecord, .clinicalNoteRecord, .conditionRecord, .coverageRecord,
            .immunizationRecord, .labResultRecord, .medicationRecord, .procedureRecord, .vitalSignRecord
        ]
        let members: Set<HealthKitSourceType> = [.bloodPressureSystolic, .bloodPressureDiastolic]
        let intentionallyUnsupported: Set<HealthKitSourceType> = [.activityMoveMode, .nikeFuel]
        // A refused route never reads the sample, and a clinical route refuses one that carries no clinical record.
        let standIn = quantitySample(.heartRate, unit: .count().unitDivided(by: .minute()), value: 72)
        let (assembly, request) = Self.assembly()
        for type in HealthKitSourceType.allCases {
            let reason = HealthKitCatalog[type].requirement ?? ""
            let expected: (error: HealthKitConversionError, code: String)? = if notYetConvertible.contains(type) {
                (.notYetConvertible(type), "mobile-input.not-yet-convertible")
            } else if recordingDocuments.contains(type) {
                (.platformExclusiveSourceType(type), "mobile-input.platform-exclusive-source-type")
            } else if members.contains(type) {
                (.componentRequiresCorrelation(type), "healthkit-input.component-requires-correlation")
            } else if intentionallyUnsupported.contains(type) {
                (.intentionallyUnsupported(type, reason: reason), "mobile-input.intentionally-unsupported-source-type")
            } else if type == .electrocardiogram {
                (.ecgEvidence(.evidenceRequired), "healthkit-input.ecg-evidence")
            } else {
                nil
            }
            guard let expected else {
                let converts = if case .observation = HealthKitContentPlan[type].route { true } else { false }
                #expect(converts && !HealthKitContentPlan[type].outputs.isEmpty, "\(type) converts no sample of its own")
                continue
            }
            #expect(throws: expected.error, "\(type)") {
                try assembly.convert(standIn, plan: HealthKitContentPlan[type], request: request)
            }
            #expect(expected.error.diagnostic.code == expected.code, "\(type)")
            guard HealthKitContentPlan[type].outputs.isEmpty else {
                continue
            }
            #expect(throws: expected.error, "\(type)") {
                try assembly.retraction(of: standIn.uuid, type: type, request: request, occurred: .instant(request.instant))
            }
        }
        #expect(!intentionallyUnsupported.contains { HealthKitCatalog[$0].requirement?.isEmpty != false })
        let emitsNothing = Set(HealthKitSourceType.allCases.filter { HealthKitContentPlan[$0].outputs.isEmpty })
        #expect(emitsNothing == notYetConvertible.union(members).union(intentionallyUnsupported))
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
