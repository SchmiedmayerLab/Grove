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


/// Which metadata keys a graph reports as withheld (spec F10-metadata-warnings): a key is carried only through the
/// element the guide maps it to, on an output that has that element, and every other key the record, or a correlation
/// member, workout event or workout activity it contains, states is reported once, in one sorted list.
@Suite
struct HealthKitMetadataWarningTests {
    /// A valid sync pair, which an attributable writer's Observation carries and a document never does.
    static let syncPair: [String: any Sendable] = [HKMetadataKeySyncIdentifier: "sync-abc", HKMetadataKeySyncVersion: 3]

    /// The warning a graph that withholds metadata keys reports, whichever keys they are.
    static let unmodeled = ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKSample.metadata")

    /// The facts of a sample at the goldens' start, `duration` long, stating exactly `metadata` (past HealthKit's
    /// checks) and written by the foreign application, which makes a sync pair attributable.
    static func facts(
        _ ordinal: UInt8,
        duration: TimeInterval = 0,
        metadata: [String: any Sendable],
        writer: StoredSampleFixtures.Writer = GoldenFixtures.foreignWriter
    ) -> StoredSampleFixtures.SampleFacts {
        StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(ordinal),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(duration),
            device: nil,
            metadata: metadata.isEmpty ? nil : metadata,
            writer: writer
        )
    }

    /// The primary graph of `sample` under the default policies.
    static func convert(_ sample: HKSample, _ inputs: ExportInputs = ExportInputs()) throws -> HealthKitAssembly.Conversion {
        try AssemblyFixtures.conversion(sample, inputs)
    }

    /// The ECG of the goldens' reading, without symptoms, stating exactly `metadata`.
    static func electrocardiogram(metadata: [String: any Sendable]) throws -> HealthKitAssembly.Conversion {
        let record = try GoldenCase.electrocardiogramRecord(uuid: 0xF4, symptoms: [])
        _ = try StoredSampleFixtures.withMetadata(record.electrocardiogram, metadata)
        return try #require(try AssemblyFixtures.conversions(ExporterFixtures.electrocardiogram(record, symptoms: [])).first)
    }

    /// The recording document of a heartbeat series stating exactly `metadata`.
    static func heartbeatSeries(metadata: [String: any Sendable]) throws -> HealthKitAssembly.Conversion {
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: facts(0xF5, duration: 2, metadata: metadata)
        )
        let record = HealthKitFHIRExporter.Record.heartbeatSeries(series, beats: ContentCorpusGrid.heartbeats.map(\.heartbeat))
        return try #require(try AssemblyFixtures.conversions(record).first)
    }

    /// A 72 bpm heart rate stating exactly `metadata`.
    static func heartRate(
        metadata: [String: any Sendable],
        writer: StoredSampleFixtures.Writer = GoldenFixtures.foreignWriter
    ) throws -> HealthKitAssembly.Conversion {
        try convert(StoredSampleFixtures.quantitySample(
            HKQuantityType(.heartRate),
            value: 72,
            unit: GoldenFixtures.beatsPerMinute,
            facts: facts(0xF6, metadata: metadata, writer: writer)
        ))
    }

    /// A 120-step count over a minute stating exactly `metadata`.
    static func stepCount(metadata: [String: any Sendable]) throws -> HealthKitAssembly.Conversion {
        try convert(StoredSampleFixtures.quantitySample(HKQuantityType(.stepCount), value: 120, unit: .count(), facts: facts(0xF7, duration: 60, metadata: metadata)))
    }

    @Test("A recording document carries no writer identity and reports every key it was given")
    func documentsReportTheirMetadata() throws {
        let metadata = GoldenFixtures.timeZoneMetadata.merging(Self.syncPair) { $1 }
            .merging([HKMetadataKeyWasUserEntered: true, "com.example.note": "x"]) { $1 }
        var conversions = [try Self.heartbeatSeries(metadata: metadata)]
        var inputs = ExportInputs()
        inputs.options.route = .authorized
        let route = try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), facts: Self.facts(0xF8, duration: 1, metadata: metadata))
        conversions.append(try #require(try AssemblyFixtures.conversions(.workoutRoute(route, locations: GoldenCase.routeLocations), inputs).first))
        #if !os(watchOS)
        let document = try HKCDADocumentSample(
            data: Data(GoldenCase.clinicalDocumentXML.utf8),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(1),
            metadata: nil
        )
        let stored = try StoredSampleFixtures.stored(document, uuid: GoldenFixtures.uuid(0xF9), writer: GoldenFixtures.foreignWriter)
        conversions.append(try Self.convert(StoredSampleFixtures.withMetadata(stored, metadata)))
        #endif
        for conversion in conversions {
            #expect(conversion.withheldMetadataKeys == metadata.keys.sorted(), "\(conversion.source.typeIdentifier)")
            #expect(conversion.warnings == [Self.unmodeled], "\(conversion.source.typeIdentifier)")
            let documents = conversion.graph.bundle.entry?.compactMap { $0.resource?.get(if: DocumentReference.self) } ?? []
            let roles = try documents.flatMap { try ($0.identifier ?? []).map { try RoledIdentifier($0).role } }
            #expect(roles == [.sourceRecord, .sourceOutput, .sourceArtifact], "\(conversion.source.typeIdentifier)")
            #expect(try HealthKitWriterRecordPairingTests.unpairedWriterRecords(in: LosslessJSONValue(parsing: conversion.graph.json)).isEmpty)
        }
    }

    @Test("Manual entry stated false is never reported, and states no recording method")
    func unenteredFlagIsSilent() throws {
        let unentered: [String: any Sendable] = [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeyWasUserEntered: false]
        let observation = try Self.heartRate(metadata: unentered)
        #expect(observation.warnings.isEmpty)
        #expect(!String(decoding: observation.graph.json, as: UTF8.self).contains("grove-recording-method"))
        #expect(try Self.heartbeatSeries(metadata: [HKMetadataKeyWasUserEntered: false]).withheldMetadataKeys.isEmpty)
    }

    @Test("A key another source type reads is reported on this one, and its graph is the one without it")
    func otherTypesKeysAreReported() throws {
        let zone = GoldenFixtures.timeZoneMetadata
        let baseline = try Self.stepCount(metadata: zone)
        let foreign: [String: any Sendable] = [
            HKMetadataKeyHeartRateMotionContext: 1,
            HKMetadataKeyInsulinDeliveryReason: 2,
            HKMetadataKeyMenstrualCycleStart: true,
            HKMetadataKeySexualActivityProtectionUsed: true,
            HKMetadataKeyAppleECGAlgorithmVersion: 2
        ]
        for (key, value) in foreign {
            let conversion = try Self.stepCount(metadata: zone.merging([key: value]) { $1 })
            #expect(conversion.withheldMetadataKeys == [key], "\(key)")
            #expect(conversion.warnings == [Self.unmodeled], "\(key)")
            #expect(conversion.graph.json == baseline.graph.json, "\(key)")
        }
    }

    @Test("A type's own content key is carried, and so not reported")
    func ownContentKeysAreCarried() throws {
        let zone = GoldenFixtures.timeZoneMetadata
        let flow = try StoredSampleFixtures.categorySample(
            HKCategoryType(.menstrualFlow),
            value: HKCategoryValueVaginalBleeding.light.rawValue,
            facts: Self.facts(0xFA, duration: 60, metadata: zone.merging([HKMetadataKeyMenstrualCycleStart: true]) { $1 })
        )
        let activity = try StoredSampleFixtures.categorySample(
            HKCategoryType(.sexualActivity),
            value: HKCategoryValue.notApplicable.rawValue,
            facts: Self.facts(0xFA, duration: 60, metadata: zone.merging([HKMetadataKeySexualActivityProtectionUsed: true]) { $1 })
        )
        for sample in [flow, activity] {
            #expect(try Self.convert(sample).warnings.isEmpty, "\(sample.sampleType.identifier)")
        }
    }

    @Test("A value a lenient reader drops is reported: a textual motion context, a textual manual-entry flag")
    func droppedValuesAreReported() throws {
        let zone = GoldenFixtures.timeZoneMetadata
        let motion = try Self.heartRate(metadata: zone.merging([HKMetadataKeyHeartRateMotionContext: "active"]) { $1 })
        #expect(motion.withheldMetadataKeys == [HKMetadataKeyHeartRateMotionContext])
        #expect(motion.warnings == [Self.unmodeled])
        #expect(motion.graph.json == (try Self.heartRate(metadata: zone)).graph.json, "no component")
        let entered = try Self.heartRate(metadata: zone.merging([HKMetadataKeyWasUserEntered: "yes"]) { $1 })
        #expect(entered.withheldMetadataKeys == [HKMetadataKeyWasUserEntered])
        #expect(entered.warnings == [Self.unmodeled])
        #expect(entered.graph.json == (try Self.heartRate(metadata: zone)).graph.json, "no recording method")
    }

    @Test("A valid sync pair without an attributable writer is validated, not carried, and reported")
    func unattributablePairIsReported() throws {
        let metadata = GoldenFixtures.timeZoneMetadata.merging(Self.syncPair) { $1 }
        let conversion = try Self.heartRate(metadata: metadata, writer: .unattributed)
        #expect(conversion.withheldMetadataKeys == [HKMetadataKeySyncIdentifier, HKMetadataKeySyncVersion].sorted())
        #expect(conversion.warnings == [Self.unmodeled])
        #expect(!String(decoding: conversion.graph.json, as: UTF8.self).contains("writer-record"))
        #expect(try Self.heartRate(metadata: metadata).warnings.isEmpty, "an attributable writer's Observation carries the pair")
    }

    @Test("An ECG carries its algorithm version, manual entry and sync pair; it states its zone's offset, not its name")
    func electrocardiogramReportsItsZoneName() throws {
        let metadata = GoldenFixtures.timeZoneMetadata.merging(Self.syncPair) { $1 }
            .merging([HKMetadataKeyWasUserEntered: true, HKMetadataKeyAppleECGAlgorithmVersion: 2]) { $1 }
        let conversion = try Self.electrocardiogram(metadata: metadata)
        #expect(conversion.withheldMetadataKeys == [HKMetadataKeyTimeZone])
        #expect(conversion.warnings == [Self.unmodeled])
        #expect(!String(decoding: conversion.graph.json, as: UTF8.self).contains(Canonicals.timezone.value?.url.absoluteString ?? "timezone"))
    }

    @Test("The withheld-metadata diagnostic is located at the source's metadata, also as the exporter reports it")
    func withheldMetadataIsLocatedAtTheMetadata() async throws {
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: GoldenCase.seriesFacts(uuid: 0xFB, duration: 2)
        )
        let beats = ContentCorpusGrid.heartbeats.map(\.heartbeat)
        let (exports, _) = try await ExporterFixtures.collect(ExporterFixtures.exporter(), [.heartbeatSeries(series, beats: beats)])
        try #require(exports.count == 1)
        #expect(exports[0].warnings == [ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKSample.metadata")])
    }
}

#endif
