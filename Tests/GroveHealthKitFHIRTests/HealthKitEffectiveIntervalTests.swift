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


/// A sample's interval in the effective datatype its measurement's profile fixes: a heart rate whose start and end
/// differ on the wire states a Period, an instant-only measurement states its start alone, and a Period's width is
/// judged on the half-even milliseconds the wire states.
@Suite
struct HealthKitEffectiveIntervalTests {
    /// 2026-08-19T14:10:00Z, a whole millisecond.
    private static let start = Date(timeIntervalSince1970: 1_787_148_600)
    /// The Los Angeles zone, as HealthKit states it.
    private static let losAngeles = [HKMetadataKeyTimeZone: "America/Los_Angeles"]

    /// A quantity sample from `start` to `end` seconds after the base instant.
    private static func quantity(
        _ type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: TimeInterval = 0,
        to end: TimeInterval,
        metadata: [String: Any] = [:]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(type),
            quantity: HKQuantity(unit: unit, doubleValue: 1),
            start: Self.start.addingTimeInterval(start),
            end: Self.start.addingTimeInterval(end),
            metadata: metadata
        )
    }

    /// A heart rate from `start` to `end` seconds after the base instant.
    private static func heartRate(from start: TimeInterval = 0, to end: TimeInterval, metadata: [String: Any] = [:]) -> HKQuantitySample {
        quantity(.heartRate, unit: .count().unitDivided(by: .minute()), from: start, to: end, metadata: metadata)
    }

    /// The export of `sample` under the default inputs.
    private static func export(_ sample: HKSample) async throws -> ExportedRecord {
        try await ExporterFixtures.export(sample)
    }

    /// The lexemes the export of `sample` states as its effective: one for an instant, start and end for a Period.
    private static func effective(of sample: HKSample) async throws -> [String?] {
        switch try await export(sample).observation.effective {
        case .dateTime(let instant): [instant.value?.description]
        case .period(let period): [period.start?.value?.description, period.end?.value?.description]
        default: []
        }
    }

    @Test("A minute-long heart rate in a named zone states a Period, each bound in the zone with its extension")
    func heartRateIntervalIsAPeriod() async throws {
        let conversion = try await Self.export(Self.heartRate(to: 60, metadata: Self.losAngeles))
        guard case .period(let period)? = conversion.observation.effective else {
            Issue.record("A heart rate whose start and end differ must state an effectivePeriod")
            return
        }
        #expect(period.start?.value?.description == "2026-08-19T07:10:00-07:00")
        #expect(period.end?.value?.description == "2026-08-19T07:11:00-07:00")
        for bound in [period.start, period.end] {
            #expect(bound?.extension?.map(\.url) == [Canonicals.timezone])
            #expect(bound?.extension?.first?.value == .code("America/Los_Angeles".asFHIRStringPrimitive()))
        }
        #expect(conversion.warnings.isEmpty)
    }

    @Test("A heart rate is a point exactly when its start and end state the same wire millisecond")
    func heartRatePointIsJudgedOnWireMilliseconds() async throws {
        await #expect(try Self.effective(of: Self.heartRate(to: 0)) == ["2026-08-19T14:10:00Z"])
        // 0.3 ms that both round down to the base millisecond.
        await #expect(try Self.effective(of: Self.heartRate(to: 0.0003)) == ["2026-08-19T14:10:00Z"])
        // 0.8 ms that both round up to the next millisecond.
        await #expect(try Self.effective(of: Self.heartRate(from: 0.0006, to: 0.0014)) == ["2026-08-19T14:10:00.001Z"])
        // 0.3 ms across a half millisecond: the wire states two instants, so a Period.
        await #expect(try Self.effective(of: Self.heartRate(from: 0.0004, to: 0.0007)) == ["2026-08-19T14:10:00Z", "2026-08-19T14:10:00.001Z"])
    }

    @Test(
        "An interval of an instant-only measurement states its start alone, without a warning",
        arguments: [
            (HKQuantityTypeIdentifier.respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
            (.heartRateVariabilitySDNN, .secondUnit(with: .milli))
        ]
    )
    func instantOnlyIntervalStatesItsStart(type: HKQuantityTypeIdentifier, unit: HKUnit) async throws {
        let conversion = try await Self.export(Self.quantity(type, unit: unit, to: 60, metadata: Self.losAngeles))
        guard case .dateTime(let instant)? = conversion.observation.effective else {
            Issue.record("\(type.rawValue) fixes effectiveDateTime")
            return
        }
        #expect(instant == (try HealthKitEffectiveTime.dateTime(Self.start, zone: TimeZone(identifier: "America/Los_Angeles"))))
        #expect(conversion.warnings.isEmpty)
    }

    @Test("A coded instant-only measurement's interval states its start alone")
    func codedInstantOnlyIntervalStatesItsStart() async throws {
        var metadata: [String: Any] = Self.losAngeles
        metadata[HKMetadataKeyMenstrualCycleStart] = true
        let flow = HKCategorySample(
            type: HKCategoryType(.menstrualFlow),
            value: HKCategoryValueVaginalBleeding.light.rawValue,
            start: Self.start,
            end: Self.start.addingTimeInterval(60),
            metadata: metadata
        )
        let conversion = try await Self.export(flow)
        await #expect(try Self.effective(of: flow) == ["2026-08-19T07:10:00-07:00"])
        #expect(conversion.warnings.isEmpty)
    }

    @Test("Exactly the plans whose profile fixes an instant state a sample's start alone, withholding its end")
    func instantOnlyMeasurementsWithholdTheirEnd() {
        /// Whether the type's Observation states only its start, so the wire carries no `endDate`.
        func withholdsEndDate(_ type: HealthKitSourceType) -> Bool {
            guard case .observation(let plan) = HealthKitContentPlan[type].route else {
                return false
            }
            return plan.effective == .instant
        }
        #expect(!withholdsEndDate(.heartRate))
        #expect(!withholdsEndDate(.stepCount))
        #expect(withholdsEndDate(.respiratoryRate))
        #expect(withholdsEndDate(.bloodPressure))
        #expect(!withholdsEndDate(.electrocardiogram))
        #expect(!withholdsEndDate(.workout))
        #expect(!withholdsEndDate(.stateOfMind))
    }

    @Test("A non-zero Period is judged on the wire: endpoints that round to one millisecond are refused")
    func nonZeroPeriodIsJudgedOnWireMilliseconds() async throws {
        await #expect(throws: HealthKitConversionError.invalidValue(.stepCount, .effectivePeriodInvalid)) {
            try await Self.export(Self.quantity(.stepCount, unit: .count(), to: 0.0003))
        }
        let steps = EffectiveRule(MeasurementCatalog.stepCount)
        let dietaryEnergy = EffectiveRule(MeasurementCatalog.dietaryEnergy)
        let end = Self.start.addingTimeInterval(0.0003)
        #expect(try steps.admitsPeriod(from: Self.start, to: end) == false)
        #expect(try dietaryEnergy.admitsPeriod(from: Self.start, to: end))
        await #expect(try Self.effective(of: Self.quantity(.dietaryEnergyConsumed, unit: .kilocalorie(), to: 0.0003))
            == ["2026-08-19T14:10:00Z", "2026-08-19T14:10:00Z"])
    }
}

#endif
