//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


private let modernAudiogramsAvailable: Bool = {
    if #available(iOS 18.1, macOS 15.1, watchOS 11.1, *) {
        return true
    }
    return false
}()


@Suite(.enabled(if: modernAudiogramsAvailable))
struct HealthKitAudiogramContentTests {
    @available(iOS 18.1, macOS 15.1, watchOS 11.1, *)
    private static func point(hertz: Double, masked: Bool = false) throws -> HKAudiogramSensitivityPoint {
        let clamping = try HKAudiogramSensitivityPointClampingRange(lowerBound: -10, upperBound: 80)
        let test = try HKAudiogramSensitivityTest(
            sensitivity: HKQuantity(unit: .decibelHearingLevel(), doubleValue: 25),
            type: .air,
            masked: masked,
            side: .left,
            clampingRange: clamping
        )
        return try HKAudiogramSensitivityPoint(frequency: HKQuantity(unit: .hertz(), doubleValue: hertz), tests: [test])
    }

    @available(iOS 18.1, macOS 15.1, watchOS 11.1, *)
    private static func sample(points: [HKAudiogramSensitivityPoint]) throws -> HKAudiogramSample {
        let start = GoldenFixtures.conversionInstant.addingTimeInterval(-600)
        let sample = HKAudiogramSample(
            sensitivityPoints: points,
            start: start,
            end: start.addingTimeInterval(300),
            device: nil,
            metadata: GoldenFixtures.timeZoneMetadata
        )
        return try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(0xE7))
    }

    @Test("Known ear/frequency codes preserve masking and clamping facts without changing the supplied sensitivity")
    func mappedReading() throws {
        guard #available(iOS 18.1, macOS 15.1, watchOS 11.1, *) else {
            return
        }
        let content = try HealthKitAudiogramContent(HealthKitMeasurementCatalog.audiogramPanel)
        var observation = Observation(code: CodeableConcept(), status: .init(.final))
        try content.apply(to: &observation, sample: Self.sample(points: [Self.point(hertz: 250, masked: true)]))
        let component = try #require(observation.component?.first)
        #expect(observation.component?.count == 1)
        #expect(component.code.coding?.first?.code?.value?.string == "91375-6")
        guard case .quantity(let quantity) = component.value else {
            Issue.record("Sensitivity must be a Quantity")
            return
        }
        #expect(quantity.value?.value?.decimal == 25)
        #expect(quantity.code?.value?.string == "dB")
        let details = try #require(component.extension?.first?.extension)
        #expect(details.first { $0.url.value?.url.absoluteString == "masked" }?.value == .boolean(true))
        guard case .range(let bounds) = details.first(where: { $0.url.value?.url.absoluteString == "clampingRange" })?.value else {
            Issue.record("Clamping bounds must be preserved")
            return
        }
        #expect(bounds.low?.value?.value?.decimal == -10)
        #expect(bounds.high?.value?.value?.decimal == 80)
    }

    @Test("An unlisted frequency is retained explicitly and never assigned a neighbouring frequency code")
    func unlistedFrequency() throws {
        guard #available(iOS 18.1, macOS 15.1, watchOS 11.1, *) else {
            return
        }
        let content = try HealthKitAudiogramContent(HealthKitMeasurementCatalog.audiogramPanel)
        var observation = Observation(code: CodeableConcept(), status: .init(.final))
        try content.apply(to: &observation, sample: Self.sample(points: [Self.point(hertz: 1_250)]))
        let component = try #require(observation.component?.first)
        #expect(component.code.coding == nil)
        #expect(component.code.text?.value?.string.contains("1250") == true)
        let details = try #require(component.extension?.first?.extension)
        guard case .quantity(let frequency) = details.first(where: { $0.url.value?.url.absoluteString == "frequency" })?.value else {
            Issue.record("Exact source frequency must be preserved")
            return
        }
        #expect(frequency.value?.value?.decimal == 1_250)
        #expect(frequency.code?.value?.string == "Hz")
    }

    @Test("Each ear retains its own masking state at the same frequency")
    func bothEarsAtOneFrequency() throws {
        guard #available(iOS 18.1, macOS 15.1, watchOS 11.1, *) else {
            return
        }
        let sensitivity = HKQuantity(unit: .decibelHearingLevel(), doubleValue: 25)
        let masked = try HKAudiogramSensitivityTest(sensitivity: sensitivity, type: .air, masked: true, side: .left, clampingRange: nil)
        let unmasked = try HKAudiogramSensitivityTest(sensitivity: sensitivity, type: .air, masked: false, side: .right, clampingRange: nil)
        let point = try HKAudiogramSensitivityPoint(frequency: HKQuantity(unit: .hertz(), doubleValue: 250), tests: [masked, unmasked])
        let content = try HealthKitAudiogramContent(HealthKitMeasurementCatalog.audiogramPanel)
        var observation = Observation(code: CodeableConcept(), status: .init(.final))
        try content.apply(to: &observation, sample: Self.sample(points: [point]))
        let components = try #require(observation.component)
        #expect(components.count == 2)
        #expect(Set(components.compactMap { $0.code.coding?.first?.code?.value?.string }).count == 2)
        let masking = components.map { component in
            component.extension?.first?.extension?.first { $0.url.value?.url.absoluteString == "masked" }?.value
        }
        #expect(masking == [.boolean(true), .boolean(false)])
    }

    @Test("Audiogram export retains the complete test interval and stable retry identity")
    func exchangeRecord() async throws {
        guard #available(iOS 18.1, macOS 15.1, watchOS 11.1, *) else {
            return
        }
        let sample = try Self.sample(points: [Self.point(hertz: 250), Self.point(hertz: 1_250)])
        let exporter = try ExporterFixtures.exporter()
        let first = try await ExporterFixtures.collect(exporter, [.sample(sample)])
        let second = try await ExporterFixtures.collect(exporter, [.sample(sample)])
        let record = try #require(first.first?.record)
        #expect(second.first?.record?.json == record.json)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
        guard case .period(let period) = observation.effective else {
            Issue.record("A hearing test interval must not be reduced to its start")
            return
        }
        #expect(period.start != period.end)
        #expect(observation.component?.count == 2)
        #expect(observation.meta?.profile?.contains(Profile.healthkitAudiogramPanel) == true)
    }
}

#endif
