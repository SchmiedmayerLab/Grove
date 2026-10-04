//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// One row of the consumption matrix: a source type's record built with any metadata, the metadata its content
/// requires (kept in every variant), the key groups varied (each removed whole, as a sync pair cannot be halved), and
/// the keys its graph carries.
struct MetadataConsumptionRow: Sendable, CustomTestStringConvertible {
    let testDescription: String
    var required: [String: any Sendable] = [:]
    let varied: [[String: any Sendable]]
    let carried: Set<String>
    /// The keys withheld although the graph depends on them: an ECG states its zone's offset, not the zone's name.
    var withheldButStated: Set<String> = []
    let convert: @Sendable ([String: any Sendable]) throws -> HealthKitAssembly.Conversion
}


/// The metadata each source type's graph carries, pinned key by key against the graph itself, so the carried-key rules
/// cannot drift from what the content reads: a carried key changes the graph, a withheld one is reported and does not.
@Suite
struct HealthKitMetadataConsumptionTests {
    private typealias Warnings = HealthKitMetadataWarningTests

    /// What every path could carry: manual entry, a zone that is not UTC, and the sync pair of an attributable writer.
    private static let shared: [[String: any Sendable]] = [
        [HKMetadataKeyWasUserEntered: true],
        GoldenFixtures.timeZoneMetadata,
        Warnings.syncPair
    ]

    /// What an Observation carries of `shared`: all of it.
    private static let observationKeys: Set<String> = [
        HKMetadataKeyWasUserEntered, HKMetadataKeyTimeZone, HKMetadataKeySyncIdentifier, HKMetadataKeySyncVersion
    ]

    static let rows: [MetadataConsumptionRow] = [
        MetadataConsumptionRow(
            testDescription: "heart rate",
            varied: shared + [[HKMetadataKeyHeartRateMotionContext: 1]],
            carried: observationKeys.union([HKMetadataKeyHeartRateMotionContext])
        ) { try Warnings.heartRate(metadata: $0) },
        MetadataConsumptionRow(testDescription: "step count", varied: shared, carried: observationKeys) { try Warnings.stepCount(metadata: $0) },
        MetadataConsumptionRow(
            testDescription: "insulin delivery",
            required: [HKMetadataKeyInsulinDeliveryReason: 2],
            varied: shared,
            carried: observationKeys.union([HKMetadataKeyInsulinDeliveryReason])
        ) { metadata in
            try Warnings.convert(StoredSampleFixtures.quantitySample(
                HKQuantityType(.insulinDelivery),
                value: 2.5,
                unit: .internationalUnit(),
                facts: Warnings.facts(0xE4, metadata: metadata)
            ))
        },
        MetadataConsumptionRow(
            testDescription: "menstrual flow",
            required: [HKMetadataKeyMenstrualCycleStart: true],
            varied: shared,
            carried: observationKeys.union([HKMetadataKeyMenstrualCycleStart])
        ) { try Self.category(.menstrualFlow, value: HKCategoryValueVaginalBleeding.light.rawValue, metadata: $0) },
        MetadataConsumptionRow(
            testDescription: "sexual activity",
            varied: shared + [[HKMetadataKeySexualActivityProtectionUsed: true]],
            carried: observationKeys.union([HKMetadataKeySexualActivityProtectionUsed])
        ) { try Self.category(.sexualActivity, value: HKCategoryValue.notApplicable.rawValue, metadata: $0) },
        MetadataConsumptionRow(
            testDescription: "electrocardiogram",
            varied: shared + [[HKMetadataKeyAppleECGAlgorithmVersion: 2]],
            carried: observationKeys.subtracting([HKMetadataKeyTimeZone]).union([HKMetadataKeyAppleECGAlgorithmVersion]),
            withheldButStated: [HKMetadataKeyTimeZone]
        ) { try Warnings.electrocardiogram(metadata: $0) },
        MetadataConsumptionRow(testDescription: "heartbeat series", varied: shared, carried: []) { try Warnings.heartbeatSeries(metadata: $0) }
    ]

    /// A category sample over a minute stating exactly `metadata`.
    private static func category(_ type: HKCategoryTypeIdentifier, value: Int, metadata: [String: any Sendable]) throws -> HealthKitAssembly.Conversion {
        try Warnings.convert(StoredSampleFixtures.categorySample(
            HKCategoryType(type),
            value: value,
            facts: Warnings.facts(0xE5, duration: 60, metadata: metadata)
        ))
    }

    /// A 120/80 reading whose correlation and systolic and diastolic members state exactly the metadata given.
    private static func bloodPressure(
        correlation: [String: any Sendable],
        systolic: [String: any Sendable],
        diastolic: [String: any Sendable] = [:]
    ) throws -> HealthKitAssembly.Conversion {
        func member(_ type: HKQuantityTypeIdentifier, _ value: Double, ordinal: UInt8, metadata: [String: any Sendable]) throws -> HKSample {
            try StoredSampleFixtures.quantitySample(
                HKQuantityType(type),
                value: value,
                unit: .millimeterOfMercury(),
                facts: Warnings.facts(ordinal, metadata: metadata, writer: .unattributed)
            )
        }
        let objects = [
            try member(.bloodPressureSystolic, 120, ordinal: 0xE7, metadata: systolic),
            try member(.bloodPressureDiastolic, 80, ordinal: 0xE8, metadata: diastolic)
        ]
        let facts = Warnings.facts(0xE6, metadata: correlation)
        return try Warnings.convert(StoredSampleFixtures.correlation(HKCorrelationType(.bloodPressure), objects: objects, facts: facts))
    }

    @Test("Each source type carries exactly its keys: a carried key changes the graph, a withheld one does not", arguments: HealthKitMetadataConsumptionTests.rows)
    func consumption(_ row: MetadataConsumptionRow) throws {
        let full = row.varied.reduce(row.required) { $0.merging($1) { $1 } }
        let conversion = try row.convert(full)
        #expect(conversion.withheldMetadataKeys == Set(full.keys).subtracting(row.carried).sorted())
        for group in row.varied {
            let keys = Set(group.keys)
            let without = try row.convert(full.filter { !keys.contains($0.key) })
            let stated = keys.isSubset(of: row.carried) || !keys.isDisjoint(with: row.withheldButStated)
            #expect((without.graph.json != conversion.graph.json) == stated, "\(keys.sorted())")
        }
    }

    @Test("A blood-pressure member's key is reported unless the record carries the equal value; manual entry false never is")
    func bloodPressureMembers() throws {
        let zone = GoldenFixtures.timeZoneMetadata
        let berlin: [String: any Sendable] = [HKMetadataKeyTimeZone: "Europe/Berlin"]
        let entry: [String: any Sendable] = [HKMetadataKeyWasUserEntered: true]
        #expect(try Self.bloodPressure(correlation: zone, systolic: zone, diastolic: zone).withheldMetadataKeys.isEmpty)
        #expect(try Self.bloodPressure(correlation: zone, systolic: berlin).withheldMetadataKeys == [HKMetadataKeyTimeZone])
        // Spec F9: a correlation stating no zone or manual entry takes its members' agreed zone, and manual entry when
        // every member states it, so those member keys are the record's and carried.
        #expect(try Self.bloodPressure(correlation: [:], systolic: zone).withheldMetadataKeys.isEmpty)
        #expect(try Self.bloodPressure(correlation: [:], systolic: zone, diastolic: berlin).withheldMetadataKeys == [HKMetadataKeyTimeZone])
        #expect(try Self.bloodPressure(correlation: zone, systolic: entry, diastolic: entry).withheldMetadataKeys.isEmpty)
        let merged = try Self.bloodPressure(
            correlation: zone.merging(["com.example.zeta": "z"]) { $1 },
            systolic: [HKMetadataKeyWasUserEntered: true, "com.example.cuff": "x"]
        )
        #expect(merged.withheldMetadataKeys == ["com.example.cuff", "com.example.zeta", HKMetadataKeyWasUserEntered].sorted())
        #expect(merged.warnings == [Warnings.unmodeled])
        let unentered: [String: any Sendable] = [HKMetadataKeyWasUserEntered: false]
        #expect(try Self.bloodPressure(correlation: zone, systolic: unentered, diastolic: unentered).withheldMetadataKeys.isEmpty)
        let entered = zone.merging([HKMetadataKeyWasUserEntered: true]) { $1 }
        #expect(try Self.bloodPressure(correlation: entered, systolic: [HKMetadataKeyWasUserEntered: true]).withheldMetadataKeys.isEmpty)
    }

    @Test("A workout event's key is reported unless the workout carries the equal value")
    func workoutEventKeys() throws {
        let begin = GoldenFixtures.sampleStart
        let lap = HKWorkoutEvent(
            type: .lap,
            dateInterval: DateInterval(start: begin, duration: 60),
            metadata: ["com.example.lap": 1, HKMetadataKeyTimeZone: GoldenFixtures.timeZone]
        )
        let workout = HKWorkout(
            activityType: .running,
            start: begin,
            end: begin.addingTimeInterval(600),
            workoutEvents: [lap],
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 64),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 1_000),
            device: nil,
            metadata: GoldenFixtures.timeZoneMetadata
        )
        let conversion = try Warnings.convert(StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(0xE9)))
        #expect(conversion.withheldMetadataKeys == ["com.example.lap"])
        #expect(conversion.warnings == [Warnings.unmodeled])
    }

    @Test("A contained object's key is withheld unless the record carries the equal value; manual entry false never is")
    func containedKeys() {
        let zone = HKMetadataKeyTimeZone
        let entered = HKMetadataKeyWasUserEntered
        let record: [String: Any] = [zone: "America/Los_Angeles", entered: true, "org.example.unread": 1]
        let carried: [String: Any] = [zone: "America/Los_Angeles", entered: true]
        func withheld(_ contained: [[String: Any]]) -> [String] {
            HealthKitSampleMetadata.withheldKeys(record: record, contained: contained, carried: carried)
        }
        #expect(withheld([]) == ["org.example.unread"])
        #expect(withheld([[zone: "America/Los_Angeles"], [entered: true]]) == ["org.example.unread"], "the carried values")
        #expect(withheld([[zone: "Europe/Berlin"]]) == ["org.example.unread", zone].sorted(), "another value")
        #expect(withheld([["org.example.unread": 1]]) == ["org.example.unread"], "a key the record states but does not carry")
        #expect(withheld([["org.example.activity": "a"]]) == ["org.example.activity", "org.example.unread"], "a key the record lacks")
        #expect(withheld([[entered: false]]) == ["org.example.unread"], "manual entry stated false")
        #expect(HealthKitSampleMetadata.withheldKeys(record: [:], contained: [[entered: true]], carried: [:]) == [entered])
    }
}

#endif
