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
import ModelsR4
import Testing


@Suite
struct HealthKitSourceRecordRetractionTests {
    /// Every kind of output a type converts to: an Observation, a correlation, a parent with children, a recording document.
    @Test(arguments: [HealthKitSourceType.heartRate, .bloodPressure, .workout, .electrocardiogram, .heartbeatSeries])
    func deletionWithoutTheSampleRetractsAllItsOutputs(_ sourceType: HealthKitSourceType) async throws {
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: GoldenFixtures.uuid(0xE7),
            sourceType: sourceType,
            deletedAfter: nil,
            detectedAt: GoldenFixtures.conversionInstant
        )
        var inputs = ExportInputs()
        inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        let graph = try await ExporterFixtures.retraction(deletion, inputs)
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        try #require(provenance.target.count == 1)
        let target = try #require(provenance.target.first)
        #expect(target.type == nil)
        #expect(target.reference == nil)
        #expect(target.identifier == provenance.entity?.first?.what.identifier)
        #expect(try RoledIdentifier(#require(target.identifier)).role == .sourceRecord)
        let role = target.extension?.first { $0.url == Canonicals.retractionTargetRole }
        #expect(role?.value == .code("source-record".asFHIRStringPrimitive()))
        let native = target.extension?.first { $0.url == Canonicals.retractionTargetNativeIdentifier }
        guard case .identifier(let identifier)? = native?.value else {
            Issue.record("The authorized native identifier must remain on the source-record target")
            return
        }
        #expect(identifier.value?.value?.string == deletion.uuid.uuidString.lowercased())
    }

    @Test("A retraction's key is its source record's alone: neither the instants, the bounds nor the facts change it")
    func retractionKeyIsTheSourceRecords() async throws {
        let exporter = try ExporterFixtures.exporter()
        let deletion = ExporterFixtures.deletion(0xE8)
        let first = try #require(try await ExporterFixtures.retract(exporter, [deletion]).first?.record)
        let later = try await ExporterFixtures.retract(
            exporter,
            [ExporterFixtures.deletion(0xE8, deletedAfter: GoldenFixtures.sampleStart, detectedAt: GoldenFixtures.conversionInstant + 60)],
            at: GoldenFixtures.conversionInstant + 120
        )
        #expect(later.first?.record?.version == first.version)
        #expect(later.first?.record?.json != first.json)

        var updated = ExportInputs()
        updated.converterHost = try HostDevice(operatingSystemVersion: "20.2")
        let elsewhere = try await ExporterFixtures.retract(ExporterFixtures.exporter(updated), [deletion])
        #expect(elsewhere.first?.record?.version == first.version)
    }

    @Test("A retraction's key follows from the record it retracts, and a retraction Provenance repeats it nowhere")
    func retractionNamesTheExportedSourceRecord() async throws {
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xE9))
        let exported = try await ExporterFixtures.export(sample)
        let graph = try await ExporterFixtures.retraction(ExporterFixtures.deletion(0xE9))
        let record = try #require(try graph.records().first)
        #expect(record.kind == .retraction)
        #expect(record.sourceRecord == exported.record.sourceRecord)
        #expect(record.version.identifier.role == .recordRetraction)
        #expect(record.outputFullURLs.isEmpty)
        #expect(record.healthKitSamples().conversions.isEmpty)
        try record.verifyVersion(in: ExportInputs().base.identityScope)
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        #expect(provenance.extension == nil)
    }
}

#endif
