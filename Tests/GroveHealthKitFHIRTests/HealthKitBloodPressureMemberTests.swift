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


/// Spec F9: a blood-pressure correlation's systolic and diastolic members belong to its record. The correlation's own
/// time zone and manual-entry flag decide when it states them; otherwise the members state the zone every member
/// naming one names, and manual entry only when every member states it. Their keys outside the allowlist are reported
/// with the correlation's, once. No other sample, a food correlation included, reads members.
@Suite
struct HealthKitBloodPressureMemberTests {
    typealias Metadata = [String: any Sendable]

    /// The metadata of a correlation and of its two members.
    struct Parts: Sendable, CustomTestStringConvertible {
        let correlation: Metadata
        let systolic: Metadata
        let diastolic: Metadata

        var testDescription: String {
            "correlation \(Self.text(correlation)), systolic \(Self.text(systolic)), diastolic \(Self.text(diastolic))"
        }

        init(_ correlation: Metadata = [:], systolic: Metadata = [:], diastolic: Metadata = [:]) {
            self.correlation = correlation
            self.systolic = systolic
            self.diastolic = diastolic
        }

        private static func text(_ metadata: Metadata) -> String {
            metadata.isEmpty ? "-" : metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
        }
    }

    /// The zone a record's parts state, as the bridge reads it.
    struct ZoneCase: Sendable, CustomTestStringConvertible {
        let parts: Parts
        /// The zone's identifier, or why the parts name none HealthKit knows.
        let zone: Result<String?, HealthKitConversionError.ValueFailure>

        var testDescription: String { parts.testDescription }
    }

    /// Whether a record's parts state manual entry.
    struct EntryCase: Sendable, CustomTestStringConvertible {
        let parts: Parts
        let wasUserEntered: Bool

        var testDescription: String { parts.testDescription }
    }

    static let pacific = "America/Los_Angeles"
    static let eastern = "America/New_York"

    static let zoneCases: [ZoneCase] = [
        ZoneCase(parts: Parts(), zone: .success(nil)),
        ZoneCase(parts: Parts(systolic: zone(pacific)), zone: .success(pacific)),
        ZoneCase(parts: Parts(diastolic: zone(pacific)), zone: .success(pacific)),
        ZoneCase(parts: Parts(systolic: zone(pacific), diastolic: zone(pacific)), zone: .success(pacific)),
        ZoneCase(parts: Parts(systolic: zone(pacific), diastolic: zone(eastern)), zone: .success(nil)),
        ZoneCase(parts: Parts(systolic: zone(eastern), diastolic: zone(pacific)), zone: .success(nil)),
        // An alias names another identifier, so the members disagree.
        ZoneCase(parts: Parts(systolic: zone("US/Pacific"), diastolic: zone(pacific)), zone: .success(nil)),
        // Every member's name is checked, whichever the set yields first.
        ZoneCase(parts: Parts(systolic: zone(pacific), diastolic: zone("Not/A-Time-Zone")), zone: .failure(.unsupportedMetadataValue(.timeZone))),
        ZoneCase(parts: Parts(systolic: zone("Not/A-Time-Zone"), diastolic: zone(pacific)), zone: .failure(.unsupportedMetadataValue(.timeZone))),
        ZoneCase(parts: Parts(diastolic: [HKMetadataKeyTimeZone: 42]), zone: .failure(.unsupportedMetadataValue(.timeZone))),
        // The correlation's own zone decides, and its members are then neither consulted nor checked.
        ZoneCase(parts: Parts(zone(pacific), systolic: zone(eastern), diastolic: zone(eastern)), zone: .success(pacific)),
        ZoneCase(parts: Parts(zone(pacific), systolic: zone("Not/A-Time-Zone")), zone: .success(pacific)),
        ZoneCase(parts: Parts(zone("Not/A-Time-Zone"), systolic: zone(pacific), diastolic: zone(pacific)), zone: .failure(.unsupportedMetadataValue(.timeZone)))
    ]

    static let entryCases: [EntryCase] = [
        EntryCase(parts: Parts(entered(true)), wasUserEntered: true),
        EntryCase(parts: Parts(entered(true), diastolic: entered(false)), wasUserEntered: true),
        EntryCase(parts: Parts(entered(false), systolic: entered(true), diastolic: entered(true)), wasUserEntered: false),
        EntryCase(parts: Parts(systolic: entered(true), diastolic: entered(true)), wasUserEntered: true),
        EntryCase(parts: Parts(systolic: entered(true)), wasUserEntered: false),
        EntryCase(parts: Parts(systolic: entered(true), diastolic: entered(false)), wasUserEntered: false),
        EntryCase(parts: Parts(), wasUserEntered: false),
        // A value that is not a Boolean states nothing, on the correlation as on a member.
        EntryCase(parts: Parts([HKMetadataKeyWasUserEntered: 2], systolic: entered(true), diastolic: entered(true)), wasUserEntered: true),
        EntryCase(parts: Parts(systolic: entered(true), diastolic: [HKMetadataKeyWasUserEntered: "true"]), wasUserEntered: false)
    ]

    @Test("Only blood pressure reads its members; a food correlation's objects are records of their own")
    func onlyBloodPressureReadsMembers() throws {
        #expect(HealthKitContentPlan.all.filter(\.metadata.readsMembers).map(\.sourceType) == [.bloodPressure])
        let entry = try StoredSampleFixtures.quantitySample(
            HKQuantityType(.dietaryEnergyConsumed),
            value: 320,
            unit: .kilocalorie(),
            facts: Self.facts([HKMetadataKeyWasUserEntered: true, "com.example.member": "x"], ordinal: 0xF1)
        )
        let food = try StoredSampleFixtures.correlation(HKCorrelationType(.food), objects: [entry], facts: Self.facts([:], ordinal: 0xF0))
        let bridged = try Self.bridge(food)
        #expect(bridged.memberValues.isEmpty)
        #expect(!bridged.wasUserEntered && bridged.withheldKeys.isEmpty)
        let pressure = try Self.pressure(Parts(systolic: [HKMetadataKeyWasUserEntered: true], diastolic: [HKMetadataKeyWasUserEntered: true]))
        #expect(try Self.bridge(pressure).memberValues.count == 2)
        #expect(HealthKitSampleMetadata(pressure, rule: .allowlist).memberValues.isEmpty)
    }

    @Test("The correlation's zone decides; otherwise every member naming one must name the same", arguments: zoneCases)
    func timeZone(_ expected: ZoneCase) throws {
        let bridged = try Self.bridge(Self.pressure(expected.parts))
        let zone = Result { () throws(HealthKitConversionError.ValueFailure) in try bridged.timeZone()?.identifier }
        #expect(zone == expected.zone)
        if case .success(let name) = expected.zone {
            #expect(bridged.statesTimeZone == (name != nil || expected.parts.correlation[HKMetadataKeyTimeZone] != nil))
        }
    }

    @Test("The correlation's Boolean decides manual entry; otherwise every member must state true", arguments: entryCases)
    func manualEntry(_ expected: EntryCase) throws {
        #expect(try Self.bridge(Self.pressure(expected.parts)).wasUserEntered == expected.wasUserEntered)
        let observation = try Self.export(Self.pressure(expected.parts)).observation
        let methods = observation.extension?.filter { $0.url == Canonicals.recordingMethod } ?? []
        #expect(methods.count == (expected.wasUserEntered ? 1 : 0))
    }

    @Test("A correlation without members states manual entry only through its own flag")
    func noMembersStateNoEntry() throws {
        let empty = try StoredSampleFixtures.correlation(HKCorrelationType(.bloodPressure), objects: [], facts: Self.facts([:], ordinal: 0xF0))
        #expect(try !Self.bridge(empty).wasUserEntered)
    }
}


extension HealthKitBloodPressureMemberTests {
    @Test("Members agreeing on a zone state the effective time in it, as the correlation's own zone would")
    func memberZoneStatesTheEffectiveTime() throws {
        let stated = try Self.export(Self.pressure(Parts(Self.zone(Self.pacific)))).observation.effective
        guard case .dateTime(let local)? = stated else {
            Issue.record("a blood-pressure correlation states a dateTime")
            return
        }
        #expect(local.value?.description == "2026-08-17T15:30:00-07:00")
        #expect(local.extension == [Extension(url: Canonicals.timezone, value: .code(Self.pacific.asFHIRStringPrimitive()))])
        for parts in [Parts(systolic: Self.zone(Self.pacific), diastolic: Self.zone(Self.pacific)), Parts(diastolic: Self.zone(Self.pacific))] {
            let conversion = try Self.export(Self.pressure(parts))
            #expect(conversion.observation.effective == stated, "\(parts.testDescription)")
            #expect(conversion.warnings.isEmpty, "\(parts.testDescription)")
        }
    }

    @Test("Members that name no zone or disagree leave the effective time in UTC, reported")
    func disagreeingMembersStayInUTC() throws {
        for parts in [Parts(), Parts(systolic: Self.zone(Self.pacific), diastolic: Self.zone(Self.eastern))] {
            let conversion = try Self.export(Self.pressure(parts))
            guard case .dateTime(let utc)? = conversion.observation.effective else {
                Issue.record("a blood-pressure correlation states a dateTime")
                continue
            }
            #expect(utc.value?.description == "2026-08-17T22:30:00Z", "\(parts.testDescription)")
            #expect(utc.extension == nil, "\(parts.testDescription)")
            let offset = ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectiveDateTime")
            #expect(conversion.warnings == [offset], "\(parts.testDescription)")
        }
    }

    @Test("A member zone the conversion consults and HealthKit does not know refuses the record")
    func invalidMemberZoneRefuses() throws {
        let pressure = try Self.pressure(Parts(systolic: Self.zone("Not/A-Time-Zone"), diastolic: Self.zone(Self.pacific)))
        let refusal = try #require(throws: HealthKitConversionError.self) {
            try Self.export(pressure)
        }
        #expect(refusal == .invalidValue(.bloodPressure, .unsupportedMetadataValue(.timeZone)))
        #expect(refusal.diagnostic.code == "mobile-input.unsupported-source-value")
    }

    @Test("Members' keys outside the allowlist join the correlation's, each once; their allowlisted keys are consumed")
    func memberKeysJoinTheUnmodeledWarning() throws {
        let parts = Parts(
            [HKMetadataKeyTimeZone: Self.pacific, "com.example.y": "correlation"],
            systolic: ["com.example.x": "systolic", "com.example.y": "systolic"],
            diastolic: [HKMetadataKeyHeartRateMotionContext: 1, HKMetadataKeySyncIdentifier: "member", HKMetadataKeySyncVersion: 1]
        )
        #expect(try Self.bridge(Self.pressure(parts)).withheldKeys == ["com.example.x", "com.example.y"])
        #expect(try Self.export(Self.pressure(parts)).warnings == [ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic])
    }

    @Test("A member's sync pair is never the record's writer identity")
    func memberSyncPairIsNotWriterIdentity() throws {
        let synced = Parts(Self.zone(Self.pacific), systolic: [HKMetadataKeySyncIdentifier: "member-1", HKMetadataKeySyncVersion: 1])
        let conversion = try Self.export(Self.pressure(synced, writer: GoldenFixtures.foreignWriter), writer: .application)
        let unsynced = try Self.export(Self.pressure(Parts(Self.zone(Self.pacific)), writer: GoldenFixtures.foreignWriter), writer: .application)
        #expect(conversion.warnings.isEmpty)
        #expect(conversion.writer != nil, "the correlation's writer travels")
        #expect(conversion.observation.extension?.map(\.url) == [Canonicals.healthKitSourceTypeExtension], "no writer-record version")
        #expect(conversion.graph.json == unsynced.graph.json)
    }
}


extension HealthKitBloodPressureMemberTests {
    /// A 120/80 correlation stating `parts`, written by `writer`; its members are attributed to no writer, as
    /// HealthKit's initializer requires.
    static func pressure(_ parts: Parts, writer: StoredSampleFixtures.Writer = .unattributed) throws -> HKCorrelation {
        func member(_ type: HKQuantityTypeIdentifier, _ value: Double, _ metadata: Metadata, ordinal: UInt8) throws -> HKQuantitySample {
            try StoredSampleFixtures.quantitySample(HKQuantityType(type), value: value, unit: .millimeterOfMercury(), facts: facts(metadata, ordinal: ordinal))
        }
        let members = [
            try member(.bloodPressureSystolic, 120, parts.systolic, ordinal: 0xF1),
            try member(.bloodPressureDiastolic, 80, parts.diastolic, ordinal: 0xF2)
        ]
        var correlationFacts = facts(parts.correlation, ordinal: 0xF0)
        correlationFacts.writer = writer
        return try StoredSampleFixtures.correlation(HKCorrelationType(.bloodPressure), objects: members, facts: correlationFacts)
    }

    /// The facts of a part stating `metadata` at the golden sample start, attributed to no writer.
    static func facts(_ metadata: Metadata, ordinal: UInt8) -> StoredSampleFixtures.SampleFacts {
        StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(ordinal),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart,
            device: nil,
            metadata: metadata.isEmpty ? nil : metadata,
            writer: .unattributed
        )
    }

    /// The bridge of `sample` under its type's plan.
    static func bridge(_ sample: HKSample) throws -> HealthKitSampleMetadata {
        let plan = try #require(HealthKitContentPlan.plan(for: sample))
        return HealthKitSampleMetadata(sample, rule: plan.metadata)
    }

    /// The export of `sample` under the default inputs, its source classified as `writer`.
    static func export(_ sample: HKSample, writer: HealthKitFHIRExporter.WriterPolicy.Classification = .omit) throws -> ExportedRecord {
        var inputs = ExportInputs()
        inputs.options.writer = .classify { _ in writer }
        return try ExporterFixtures.export(sample, inputs)
    }

    private static func zone(_ name: String) -> Metadata {
        [HKMetadataKeyTimeZone: name]
    }

    private static func entered(_ flag: Bool) -> Metadata {
        [HKMetadataKeyWasUserEntered: flag]
    }
}

#endif
