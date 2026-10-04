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


/// A sample's interval in the effective datatype its measurement's profile fixes, a Period's width judged on the
/// half-even milliseconds the wire states.
@Suite
struct HealthKitEffectiveIntervalTests {
    /// 2026-08-19T14:10:00Z, a whole millisecond.
    private static let start = Date(timeIntervalSince1970: 1_787_148_600)

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

    /// The export of `sample` under the default inputs.
    private static func export(_ sample: HKSample) throws -> ExportedRecord {
        try ExporterFixtures.export(sample)
    }

    /// The lexemes the export of `sample` states as its effective: one for an instant, start and end for a Period.
    private static func effective(of sample: HKSample) throws -> [String?] {
        switch try export(sample).observation.effective {
        case .dateTime(let instant): [instant.value?.description]
        case .period(let period): [period.start?.value?.description, period.end?.value?.description]
        default: []
        }
    }

    @Test("A non-zero Period is judged on the wire: endpoints that round to one millisecond are refused")
    func nonZeroPeriodIsJudgedOnWireMilliseconds() throws {
        #expect(throws: HealthKitConversionError.invalidValue(.stepCount, .effectivePeriodInvalid)) {
            try Self.export(Self.quantity(.stepCount, unit: .count(), to: 0.0003))
        }
        let steps = EffectiveRule(MeasurementCatalog.stepCount)
        let dietaryEnergy = EffectiveRule(MeasurementCatalog.dietaryEnergy)
        let end = Self.start.addingTimeInterval(0.0003)
        #expect(try steps.admitsPeriod(from: Self.start, to: end) == false)
        #expect(try dietaryEnergy.admitsPeriod(from: Self.start, to: end))
        #expect(try Self.effective(of: Self.quantity(.dietaryEnergyConsumed, unit: .kilocalorie(), to: 0.0003))
            == ["2026-08-19T14:10:00Z", "2026-08-19T14:10:00Z"])
    }
}

#endif
