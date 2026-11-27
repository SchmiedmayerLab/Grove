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


@Suite
struct HealthKitFoodContentTests {
    @Test("Food members retain the same bytes and identities when collected independently")
    func preservesIndependentNutrients() async throws {
        let first = try Self.nutrient(ordinal: 0xA1), second = try Self.nutrient(ordinal: 0xA2)
        let correlation = try Self.food([first, second])
        let exporter = try ExporterFixtures.exporter { $0.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem) }
        let grouped = try await ExporterFixtures.collect(exporter, samples: [correlation])
        let independent = try await ExporterFixtures.collect(exporter, samples: [first, second])
        try #require(grouped.count == 3)
        let parent = try Self.observation(#require(grouped.first?.record))
        #expect(parent.value == nil && parent.component == nil)
        #expect(parent.meta?.profile == [Profile.healthkitFoodCorrelation])
        #expect(parent.hasMember?.count == 2)
        #expect(grouped.dropFirst().compactMap { $0.record?.json } == independent.compactMap { $0.record?.json })
        let nutrients = try grouped.dropFirst().map { try Self.observation(#require($0.record)) }
        let referenced = Set(try #require(parent.hasMember).compactMap { $0.identifier })
        let identities = Set(nutrients.flatMap { ($0.identifier ?? []).filter { (try? RoledIdentifier($0).role) == .sourceOutput } })
        #expect(referenced == identities)
        let nativeIDs = nutrients.flatMap { observation in
            (observation.identifier ?? []).filter { $0.system?.value?.url.absoluteString == GoldenFixtures.nativeIdentifierSystem.rawValue }
        }
        #expect(Set(nativeIDs.compactMap { $0.value?.value?.string }) == Set([first.uuid, second.uuid].map { $0.uuidString.lowercased() }))
        #expect(identities.count == 2)
    }

    @Test("Per-source conversion instants preserve bytes across independently timed food and nutrient queries")
    func independentlyTimedMembersKeepTheStandaloneVersion() async throws {
        let first = try Self.nutrient(ordinal: 0xA5), second = try Self.nutrient(ordinal: 0xA6)
        let correlation = try Self.food([first, second])
        let exporter = try ExporterFixtures.exporter()
        let instant = GoldenFixtures.conversionInstant
        let later = instant.addingTimeInterval(60)
        let defaults = try await ExporterFixtures.collect(exporter, samples: [correlation], at: later)
        var grouped: [HealthKitFHIRExporter.Export] = []
        try await exporter.export(
            records: [.sample(correlation)], at: later, conversionInstants: [first.uuid: instant, correlation.uuid: instant]
        ) { grouped.append($0) }
        let independent = try await ExporterFixtures.collect(exporter, samples: [first], at: instant)
        let unchangedSecond = try await ExporterFixtures.collect(exporter, samples: [second], at: later)
        #expect(grouped.count == 3)
        #expect(grouped.first?.record?.json != defaults.first?.record?.json)
        #expect(grouped.first { $0.source.uuid == first.uuid }?.record?.json == independent.first?.record?.json)
        #expect(grouped.first { $0.source.uuid == second.uuid }?.record?.json == unchangedSecond.first?.record?.json)
        let before = try Self.observation(#require(defaults.first?.record))
        let after = try Self.observation(#require(grouped.first?.record))
        #expect(before.hasMember == after.hasMember)
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.export(
                records: [.sample(correlation)], at: later, conversionInstants: [first.uuid: Date(timeIntervalSince1970: .nan)]
            ) { _ in
                Issue.record("An invalid explicit conversion instant must not produce partial exports")
            }
        }
    }

    @Test("An unchanged food query retries identically and each nutrient keeps its own metadata")
    func stableRetryAndMetadata() async throws {
        let member = try Self.nutrient(ordinal: 0xA3)
        let correlation = try Self.food([member])
        let exporter = try ExporterFixtures.exporter()
        let first = try await ExporterFixtures.collect(exporter, samples: [correlation])
        let retry = try await ExporterFixtures.collect(exporter, samples: [correlation])
        try #require(first.count == 2)
        #expect(first.compactMap { $0.record?.json } == retry.compactMap { $0.record?.json })
        let parent = try Self.observation(#require(first[0].record)), nutrient = try Self.observation(#require(first[1].record))
        #expect(parent.extension != nutrient.extension)
        #expect(nutrient.extension?.contains { $0.url.value?.url.absoluteString == HealthKitContract.metadataExtensionURL } == true)
    }

    @Test("Members follow the disclosure options as they do when collected independently")
    func membersFollowTheDisclosureOptions() async throws {
        let start = GoldenFixtures.conversionInstant.addingTimeInterval(-600)
        let device = HKDevice(
            name: "Anna's Watch",
            manufacturer: "Device Manufacturer",
            model: "Device Model",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: "local-4",
            udiDeviceIdentifier: nil
        )
        let member = try StoredSampleFixtures.stored(HKQuantitySample(
            type: HKQuantityType(.dietaryProtein),
            quantity: HKQuantity(unit: .gram(), doubleValue: 12),
            start: start,
            end: start.addingTimeInterval(60),
            device: device,
            metadata: [HKMetadataKeyTimeZone: "UTC", HKMetadataKeyDeviceSerialNumber: "SN-0042"]
        ), uuid: GoldenFixtures.uuid(0xA7))
        let correlation = try Self.food([member])
        let exporter = try ExporterFixtures.exporter { options in
            options = .nonIdentifying
            options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            options.syncIdentifier = .authorized
        }
        let grouped = try await ExporterFixtures.collect(exporter, samples: [correlation])
        let alone = try await ExporterFixtures.collect(exporter, samples: [member])
        try #require(grouped.count == 2 && alone.count == 1)
        #expect(grouped[1].record?.json == alone[0].record?.json)
        for export in grouped {
            let json = String(decoding: try #require(export.record).json, as: UTF8.self)
            for value in ["Anna's Watch", "local-4", "SN-0042"] {
                #expect(!json.contains(value), "\(value)")
            }
        }
        #expect(String(decoding: try #require(grouped[1].record).json, as: UTF8.self).contains(member.uuid.uuidString.lowercased()))
    }

    @Test("Empty, repeated, or nonnutritional members cannot create a food grouping")
    func refusesInvalidMembers() throws {
        let sample = try Self.nutrient(ordinal: 0xA4)
        #expect(throws: (any Error).self) { try HealthKitFoodContent.validate([]) }
        #expect(throws: (any Error).self) { try HealthKitFoodContent.validate([sample, sample]) }
        let heartRate = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 60),
            start: GoldenFixtures.conversionInstant,
            end: GoldenFixtures.conversionInstant
        )
        #expect(throws: (any Error).self) { try HealthKitFoodContent.validate([heartRate]) }
    }
}


extension HealthKitFoodContentTests {
    private static func nutrient(ordinal: UInt8) throws -> HKQuantitySample {
        let start = GoldenFixtures.conversionInstant.addingTimeInterval(-600)
        return try StoredSampleFixtures.stored(HKQuantitySample(
            type: HKQuantityType(.dietaryProtein),
            quantity: HKQuantity(unit: .gram(), doubleValue: 12),
            start: start,
            end: start.addingTimeInterval(60),
            metadata: [HKMetadataKeyTimeZone: "UTC", "meal-note": "synthetic-nutrient"]
        ), uuid: GoldenFixtures.uuid(ordinal))
    }

    private static func food(_ members: [HKQuantitySample]) throws -> HKCorrelation {
        let start = GoldenFixtures.conversionInstant.addingTimeInterval(-600)
        return try StoredSampleFixtures.stored(HKCorrelation(
            type: HKCorrelationType(.food),
            start: start,
            end: start.addingTimeInterval(120),
            objects: Set(members),
            metadata: GoldenFixtures.timeZoneMetadata
        ), uuid: GoldenFixtures.uuid(0xA0))
    }

    private static func observation(_ record: ExchangeRecord) throws -> Observation {
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        return try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
    }
}

#endif
