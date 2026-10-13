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

    /// The Observation the exporter's own plan states for a category sample of `type` holding `value`, over ten minutes
    /// where the measurement admits a Period, in Los Angeles.
    private static func exported(
        _ type: HealthKitSourceType,
        value: Int,
        metadata: [String: Any] = [:]
    ) throws -> (sample: HKCategorySample, observation: ModelsR4.Observation) {
        let plan = HealthKitContentPlan[type]
        guard case .observation(let content) = plan.route,
              let id = plan.entry.measurements.first?.id,
              let contract = HealthKitSampleProjection.measurements.values.first(where: { $0.id == id }) else {
            throw plan.refusal
        }
        let start = GoldenFixtures.sampleStart
        let sample = HKCategorySample(
            type: HKCategoryType(HKCategoryTypeIdentifier(rawValue: type.rawValue)),
            value: value,
            start: start,
            end: EffectiveRule(contract) == .instant ? start : start.addingTimeInterval(600),
            metadata: metadata.merging([HKMetadataKeyTimeZone: "America/Los_Angeles"]) { stated, _ in stated }
        )
        return (sample, try content.observation(sample, metadata: HealthKitSampleMetadata(sample, rule: plan.metadata)))
    }

    /// The Observation the exporter's own plan states for `sample` of `type`.
    private static func exported(_ sample: HKSample, as type: HealthKitSourceType) throws -> ModelsR4.Observation {
        let plan = HealthKitContentPlan[type]
        guard case .observation(let content) = plan.route else {
            throw plan.refusal
        }
        return try content.observation(sample, metadata: HealthKitSampleMetadata(sample, rule: plan.metadata))
    }

    /// `concept` with a second coding of `code` in its first coding's system, contradicting it.
    private static func contradicted(_ concept: CodeableConcept, by code: String) throws -> CodeableConcept {
        var first = try #require(concept.coding?.first)
        first.code = code.asFHIRStringPrimitive()
        return CodeableConcept(coding: (concept.coding ?? []) + [first])
    }

    /// The category values and metadata a plan's round trip covers: every value of a coded table, the one of a duration,
    /// and each protection; a menstrual flow with and without its cycle start. Any other plan covers none.
    private static func roundTripCases(of plan: HealthKitContentPlan) -> [(value: Int, metadata: [String: Any])] {
        guard case .observation(let content) = plan.route else {
            return []
        }
        var cases: [(value: Int, metadata: [String: Any])]
        switch content.value {
        case .coded(let values, _):
            cases = values.keys.sorted().map { ($0, [:]) }
        case .duration:
            cases = [(HKCategoryValue.notApplicable.rawValue, [:])]
        case .protection:
            let key = HKMetadataKeySexualActivityProtectionUsed
            cases = [[:], [key: true], [key: false]].map { (HKCategoryValue.notApplicable.rawValue, $0) }
        default:
            return []
        }
        if plan.sourceType == .menstrualFlow {
            cases = cases.flatMap { value, _ in [true, false].map { (value, [HKMetadataKeyMenstrualCycleStart: $0]) } }
        }
        return cases
    }

    @Test("A weight observation lands as a body-mass sample with its stated envelope")
    func weightProjectsWithEnvelope() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        let sample = try #require(observation.healthKitSample() as? HKQuantitySample)
        #expect(sample.quantityType == HKQuantityType(.bodyMass))
        #expect(sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) == 72.5)
        #expect(sample.startDate == sample.endDate)
        #expect(sample.startDate == (try DateTime(Self.effective).asNSDate()))
        #expect(sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true)
        #expect(sample.metadata?[HKMetadataKeyTimeZone] as? String == "GMT-0700")
        #expect(sample.metadata?[HKMetadataKeySyncIdentifier] == nil)
    }

    @Test("A stated value lands as the binary64 nearest its decimal")
    func valueLandsNearestItsDecimal() throws {
        for lexeme in ["1.32", "0.42", "36.52"] {
            let observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: Decimal(string: lexeme))
            let sample = try #require(observation.healthKitSample() as? HKQuantitySample)
            #expect(sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) == Double(lexeme))
        }
    }

    /// Foundation's calendar would read this lexeme as the Julian date, nine days later.
    @Test("A reading from before the 1582 calendar reform lands on its proleptic Gregorian instant")
    func preReformInstantIsProleptic() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.effective = .dateTime(FHIRPrimitive(try DateTime("1500-01-01T00:00:00Z")))
        let sample = try observation.healthKitSample()
        #expect(sample.startDate == Date(timeIntervalSince1970: -14_831_769_600))
        #expect(sample.endDate == sample.startDate)
    }

    @Test("A sample from before the 1582 calendar reform converts and projects back onto its own instant")
    func preReformSampleRoundTrips() async throws {
        let start = Date(timeIntervalSince1970: -14_831_769_600)
        let sample = try StoredSampleFixtures.stored(
            HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70), start: start, end: start),
            uuid: GoldenFixtures.uuid(1)
        )
        let projected = try await ExporterFixtures.export(sample).graph.healthKitSamples()
        #expect(projected.failures.isEmpty)
        #expect(projected.conversions.map(\.startDate) == [start])
    }

    /// `HKSample` raises an uncatchable exception for an end at or after `Date.distantFuture`, 4001-01-01T00:00:00Z.
    @Test("An effective instant HealthKit cannot hold refuses instead of aborting the process")
    func instantPastHealthKitRefuses() throws {
        func observation(at lexeme: String) throws -> ModelsR4.Observation {
            var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
            observation.effective = .dateTime(FHIRPrimitive(try DateTime(lexeme)))
            return observation
        }
        for lexeme in ["4000-12-31T23:59:59.999Z", "4001-01-01T00:30:00+01:00"] {
            #expect(try observation(at: lexeme).healthKitSample().endDate == (try DateTime(lexeme).asNSDate()), "\(lexeme)")
        }
        for lexeme in ["4001-01-01T00:00:00Z", "4000-12-31T23:30:00-01:00", "9999-12-31T23:59:59Z"] {
            let refused = try observation(at: lexeme)
            #expect(throws: HealthKitSampleProjectionError.effectiveMissing(id: "body-weight"), "\(lexeme)") {
                try refused.healthKitSample()
            }
        }
    }

    @Test("A sync identifier makes re-projection replace, and an amendment outrank the original")
    func syncIdentityFollowsTheObservation() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        let first = try observation.healthKitSample(syncIdentifier: "response-1|weight")
        #expect(first.metadata?[HKMetadataKeySyncIdentifier] as? String == "response-1|weight")
        #expect(first.metadata?[HKMetadataKeySyncVersion] as? Int == 1)

        observation.status = FHIRPrimitive(.amended)
        let amended = try observation.healthKitSample(syncIdentifier: "response-1|weight")
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

        let sample = try observation.healthKitSample()
        #expect(sample.metadata?[HKMetadataKeySyncIdentifier] as? String == "v0:installation:1:digest")

        let overridden = try observation.healthKitSample(syncIdentifier: "explicit")
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
        let correlation = try #require(observation.healthKitSample() as? HKCorrelation)
        #expect(correlation.correlationType == HKCorrelationType(.bloodPressure))
        let readings = correlation.objects.compactMap { $0 as? HKQuantitySample }
        #expect(Set(readings.map { $0.quantity.doubleValue(for: .millimeterOfMercury()) }) == [118, 76])
        #expect(correlation.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true)
    }

    @Test("A panel missing a reading refuses instead of writing half a correlation")
    func incompleteBloodPressureRefuses() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.bloodPressure)
        #expect(throws: HealthKitSampleProjectionError.componentMissing(id: "blood-pressure", code: "8480-6")) {
            try observation.healthKitSample()
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
            try observation.healthKitSample()
        }
    }

    @Test("A measurement bound to several HealthKit types refuses instead of guessing")
    func ambiguousMeasurementRefuses() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.speed, value: 3)
        #expect(throws: HealthKitSampleProjectionError.measurementNotMappable(id: "speed")) {
            try observation.healthKitSample()
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
            try observation.healthKitSample()
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
            try observation.healthKitSample()
        }
    }

    @Test("An observation without a value refuses")
    func valueMissingRefuses() throws {
        let observation = try Self.observation(contract: MeasurementCatalog.bodyWeight)
        #expect(throws: HealthKitSampleProjectionError.valueMissing(id: "body-weight")) {
            try observation.healthKitSample()
        }
    }

    @Test("A carried writer record version outranks the status-derived one")
    func writerRecordVersionBecomesTheSyncVersion() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.extension = (observation.extension ?? []) + [
            Extension(url: Canonicals.writerRecordVersion, value: .string("7".asFHIRStringPrimitive()))
        ]
        let sample = try observation.healthKitSample(syncIdentifier: "response-1|weight")
        #expect(sample.metadata?[HKMetadataKeySyncVersion] as? Int == 7)
    }

    @Test("An observation without an effective instant refuses")
    func effectiveMissingRefuses() throws {
        var observation = try Self.observation(contract: MeasurementCatalog.bodyWeight, value: 72.5)
        observation.effective = nil
        #expect(throws: HealthKitSampleProjectionError.effectiveMissing(id: "body-weight")) {
            try observation.healthKitSample()
        }
        let diagnostic = HealthKitSampleProjectionError.effectiveMissing(id: "body-weight").diagnostic
        #expect(diagnostic.code == "mobile-input.effective-period-invalid")
        #expect(diagnostic.location == "Observation.effective")
    }

    @Test("Every category value the exporter states projects back to its type, value and interval, its first coding alone too")
    func categoryValuesRoundTrip() throws {
        var projected = 0
        for plan in HealthKitContentPlan.all {
            guard HealthKitSampleProjection.projections[plan.entry.measurements.first?.id ?? ""]?.sourceType == plan.sourceType.rawValue else {
                continue
            }
            for (value, metadata) in Self.roundTripCases(of: plan) {
                let (sample, observation) = try Self.exported(plan.sourceType, value: value, metadata: metadata)
                var firstCodingOnly = observation
                if case .codeableConcept(let concept)? = observation.value {
                    firstCodingOnly.value = .codeableConcept(CodeableConcept(coding: concept.coding.map { Array($0.prefix(1)) }))
                }
                for stated in [observation, firstCodingOnly] {
                    let back = try #require(stated.healthKitSample() as? HKCategorySample, "\(plan.sourceType.rawValue) \(value)")
                    #expect(back.categoryType == sample.categoryType)
                    #expect(back.value == value, "\(plan.sourceType.rawValue)")
                    #expect(back.startDate == sample.startDate && back.endDate == sample.endDate, "\(plan.sourceType.rawValue)")
                    for (key, flag) in metadata {
                        #expect(back.metadata?[key] as? Bool == flag as? Bool, "\(plan.sourceType.rawValue) \(key)")
                    }
                    if metadata.isEmpty {
                        #expect(back.metadata?[HKMetadataKeySexualActivityProtectionUsed] == nil)
                    }
                }
                projected += 1
            }
        }
        // 36 symptoms of 5 severities, 12 occurrences, the other coded tables, 3 durations and 3 protections.
        #expect(projected > 250)
    }

    @Test("A percentage projects back to the fraction it was stated from, and a platform rate to its count")
    func percentAndRateRoundTrip() throws {
        let start = GoldenFixtures.sampleStart
        var projected = 0
        for plan in HealthKitContentPlan.all {
            guard case .observation(let content) = plan.route, case .quantity(_, let read) = content.value,
                  HealthKitSampleProjection.projections[plan.entry.measurements.first?.id ?? ""]?.sourceType == plan.sourceType.rawValue else {
                continue
            }
            let unit: HKUnit
            switch read {
            case .percent: unit = .percent()
            case .platformRate: unit = .count()
            case .unit, .score: continue
            }
            let type = HKQuantityType(HKQuantityTypeIdentifier(rawValue: plan.sourceType.rawValue))
            // Fractions whose binary64 times 100 is not the shifted decimal: 0.282 * 100 is 28.199999999999996.
            for value in [0, 0.07, 0.282, 0.5, 0.573, 1] {
                let sample = HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: start,
                    end: start.addingTimeInterval(600),
                    metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]
                )
                let observation = try content.observation(sample, metadata: HealthKitSampleMetadata(sample, rule: plan.metadata))
                let back = try #require(observation.healthKitSample() as? HKQuantitySample, "\(plan.sourceType.rawValue)")
                #expect(back.quantityType == type)
                #expect(back.quantity.doubleValue(for: unit) == value, "\(plan.sourceType.rawValue) \(value)")
                projected += 1
            }
        }
        // Eight percentages, oxygen saturation and body fat among them, and one platform rate.
        #expect(projected == 9 * 6)
    }

    @Test("Codes that contradict each other refuse instead of picking one")
    func contradictoryCodesRefuse() throws {
        let start = GoldenFixtures.sampleStart
        let insulin = HKQuantitySample(
            type: HKQuantityType(.insulinDelivery),
            quantity: HKQuantity(unit: .internationalUnit(), doubleValue: 2),
            start: start,
            end: start.addingTimeInterval(60),
            metadata: [HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue, HKMetadataKeyTimeZone: "America/Los_Angeles"]
        )
        var observation = try Self.exported(insulin, as: .insulinDelivery)
        let back = try #require(observation.healthKitSample() as? HKQuantitySample)
        #expect(back.metadata?[HKMetadataKeyInsulinDeliveryReason] as? Int == HKInsulinDeliveryReason.bolus.rawValue)
        // The reason states bolus and basal at once.
        var reason = try #require(observation.component?.last)
        guard case .codeableConcept(let bolus)? = reason.value else {
            Issue.record("an insulin delivery states its reason as a coded component")
            return
        }
        reason.value = .codeableConcept(try Self.contradicted(bolus, by: "basal"))
        observation.component = [reason]
        #expect(throws: HealthKitSampleProjectionError.valueNotMappable(id: "insulin-delivery")) {
            try observation.healthKitSample()
        }

        // Protection used and not used at once.
        let key = HKMetadataKeySexualActivityProtectionUsed
        var activity = try Self.exported(.sexualActivity, value: HKCategoryValue.notApplicable.rawValue, metadata: [key: true]).observation
        guard case .codeableConcept(let protected)? = activity.value else {
            Issue.record("sexual activity states its protection as a coded value")
            return
        }
        let unprotected = try Self.exported(.sexualActivity, value: HKCategoryValue.notApplicable.rawValue, metadata: [key: false]).observation
        guard case .codeableConcept(let notProtected)? = unprotected.value else {
            Issue.record("sexual activity states its protection as a coded value")
            return
        }
        activity.value = .codeableConcept(CodeableConcept(coding: (protected.coding ?? []) + (notProtected.coding ?? [])))
        #expect(throws: HealthKitSampleProjectionError.valueNotMappable(id: "sexual-activity")) {
            try activity.healthKitSample()
        }
    }

    @Test("A duration spans its Period, which its stated length must agree with to the millisecond")
    func durationAgreesWithItsPeriod() throws {
        let start = GoldenFixtures.sampleStart
        // The exporter states 60.0004 s but rounds the end to the millisecond; the Period wins.
        let handwashing = HKCategorySample(
            type: HKCategoryType(.handwashingEvent),
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: start.addingTimeInterval(60.0004),
            metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]
        )
        var observation = try Self.exported(handwashing, as: .handwashingEvent)
        let back = try #require(observation.healthKitSample() as? HKCategorySample)
        #expect(back.endDate.timeIntervalSince(back.startDate) == 60)

        guard case .quantity(var length)? = observation.value else {
            Issue.record("a duration states its length as a quantity")
            return
        }
        length.value = FHIRPrimitive(FHIRDecimal(Decimal(string: "59.998") ?? 0))
        observation.value = .quantity(length)
        #expect(throws: HealthKitSampleProjectionError.valueNotMappable(id: "handwashing-session")) {
            try observation.healthKitSample()
        }
        length.value = nil
        observation.value = .quantity(length)
        #expect(throws: HealthKitSampleProjectionError.valueMissing(id: "handwashing-session")) {
            try observation.healthKitSample()
        }
    }

    @Test("A category value its HealthKit type does not hold refuses instead of guessing")
    func unmappedCategoryValueRefuses() throws {
        var headache = try Self.exported(.headache, value: HKCategoryValueSeverity.mild.rawValue).observation
        guard case .codeableConcept(let mild)? = headache.value, var codings = mild.coding, codings.count == 2 else {
            Issue.record("a severity states its shared code, then its HealthKit case")
            return
        }
        // The HealthKit case contradicts the shared code.
        codings[1].code = "severe"
        headache.value = .codeableConcept(CodeableConcept(coding: codings))
        #expect(throws: HealthKitSampleProjectionError.valueNotMappable(id: "symptom-headache")) {
            try headache.healthKitSample()
        }
        codings[0].code = "unknown-severity"
        headache.value = .codeableConcept(CodeableConcept(coding: [codings[0]]))
        #expect(throws: HealthKitSampleProjectionError.valueNotMappable(id: "symptom-headache")) {
            try headache.healthKitSample()
        }
        let diagnostic = HealthKitSampleProjectionError.valueNotMappable(id: "symptom-headache").diagnostic
        #expect(diagnostic.code == "mobile-input.unsupported-source-value")

        // A walking-steadiness value without its occurrence names neither the initial nor the repeat case.
        let initialLow = HKCategoryValueAppleWalkingSteadinessEvent.initialLow.rawValue
        var steadiness = try Self.exported(.appleWalkingSteadinessEvent, value: initialLow).observation
        steadiness.component = nil
        #expect(throws: HealthKitSampleProjectionError.valueNotMappable(id: "walking-steadiness-notification")) {
            try steadiness.healthKitSample()
        }

        // HealthKit raises on a menstrual flow without its cycle start.
        let light = HKCategoryValueVaginalBleeding.light.rawValue
        var flow = try Self.exported(.menstrualFlow, value: light, metadata: [HKMetadataKeyMenstrualCycleStart: true]).observation
        flow.component = nil
        #expect(throws: HealthKitSampleProjectionError.componentMissing(id: "menstruation-flow", code: "menstrual-cycle-start")) {
            try flow.healthKitSample()
        }
    }
}
