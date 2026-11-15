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


private let platform27Available: Bool = {
    if #available(iOS 27, macOS 27, watchOS 27, *) {
        return true
    }
    return false
}()


@Suite(.enabled(if: platform27Available))
struct HealthKitPlatform27Tests {
    private static func observation(_ sample: HKSample, ordinal: UInt8) async throws -> Observation {
        let stored = try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(ordinal))
        let exporter = try ExporterFixtures.exporter()
        let exports = try await ExporterFixtures.collect(exporter, samples: [stored])
        let record = try #require(exports.first?.record)
        let repeated = try await ExporterFixtures.collect(exporter, samples: [stored])
        #expect(repeated.first?.record?.json == record.json)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        return try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
    }

    @Test("RMSSD retains its own statistic, milliseconds, source type and measurement interval")
    func rmssd() async throws {
        guard #available(iOS 27, macOS 27, watchOS 27, *) else {
            return
        }
        let end = GoldenFixtures.conversionInstant
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRateVariabilityRMSSD),
            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 42),
            start: end.addingTimeInterval(-300),
            end: end,
            metadata: GoldenFixtures.timeZoneMetadata
        )
        let observation = try await Self.observation(sample, ordinal: 0xE8)
        #expect(observation.meta?.profile?.contains(Profile.groveMobileHeartRateVariabilityRmssd) == true)
        #expect(observation.code.coding?.first?.code?.value?.string == "heart-rate-variability-rmssd")
        guard case .quantity(let quantity) = observation.value, case .period(let period) = observation.effective else {
            Issue.record("RMSSD must retain its scalar and interval")
            return
        }
        #expect(quantity.value?.value?.decimal == 42)
        #expect(quantity.code?.value?.string == "ms")
        #expect(period.start != period.end)
    }

    @Test("Postmenopausal bleeding preserves intensity and the whole source interval")
    func bleeding() async throws {
        guard #available(iOS 27, macOS 27, watchOS 27, *) else {
            return
        }
        let end = GoldenFixtures.conversionInstant
        let sample = HKCategorySample(
            type: HKCategoryType(.bleedingAfterMenopause),
            value: HKCategoryValueVaginalBleeding.heavy.rawValue,
            start: end.addingTimeInterval(-3_600),
            end: end,
            metadata: GoldenFixtures.timeZoneMetadata
        )
        let observation = try await Self.observation(sample, ordinal: 0xE9)
        #expect(observation.meta?.profile?.contains(Profile.healthkitBleedingAfterMenopause) == true)
        guard case .codeableConcept(let result) = observation.value, case .period(let period) = observation.effective else {
            Issue.record("Postmenopausal bleeding must retain its intensity and interval")
            return
        }
        #expect(result.coding?.first?.code?.value?.string == "heavy")
        #expect(period.start != period.end)
    }

    @Test("Every menopausal state remains a point-in-time statement without an invented duration")
    func menopausalStates() async throws {
        guard #available(iOS 27, macOS 27, watchOS 27, *) else {
            return
        }
        let cases: [(HKCategoryValueMenopausalState, String)] = [(.menopause, "menopause"), (.perimenopause, "perimenopause"), (.none, "none")]
        for (index, item) in cases.enumerated() {
            let sample = HKCategorySample(
                type: HKCategoryType(.menopausalState),
                value: item.0.rawValue,
                start: GoldenFixtures.conversionInstant,
                end: GoldenFixtures.conversionInstant,
                metadata: GoldenFixtures.timeZoneMetadata
            )
            let observation = try await Self.observation(sample, ordinal: UInt8(0xEA + index))
            #expect(observation.meta?.profile?.contains(Profile.healthkitMenopausalState) == true)
            guard case .codeableConcept(let result) = observation.value, case .dateTime = observation.effective else {
                Issue.record("A menopausal state is coded at one source instant")
                return
            }
            #expect(result.coding?.first?.code?.value?.string == item.1)
        }
    }
}

#endif
