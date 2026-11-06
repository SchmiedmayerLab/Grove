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
import Testing


/// Writes one Bundle of several records and one of several retractions, as an upload packs them.
///
/// They are keyed under the published test key, so the grove-fhir producer kit recomputes every key of them rather than
/// checking its shape; `Scripts/validate-fhir-conformance.sh` validates them beside the one-record fixtures.
@Suite
struct PackedBundleFixtureTests {
    private static var identityScope: OpaqueIdentityScope {
        get throws {
            let epoch = KeyEpoch(1)
            return try OpaqueIdentityScope.conformanceTesting(
                systems: DeploymentIdentifierSystems.derived(
                    root: "https://grovealliance.org/fhir/testing/identifiers/healthkit",
                    keyID: "test-key",
                    epoch: epoch
                ),
                keyID: "test-key",
                epoch: epoch
            )
        }
    }

    private static func exporter(application: ApplicationDevice = ExporterGolden.deploymentApplication) throws -> HealthKitFHIRExporter {
        let producer = try ExporterFixtures.producer(
            identityScope: identityScope,
            application: application,
            studies: [.test("study-a"), .test("study-b")]
        )
        return try ExporterFixtures.exporter(producer) { $0 = ExporterGolden.deploymentOptions }
    }

    private static func packed(_ records: [ExchangeRecord], kind: ExchangeRecord.Kind) throws -> ExchangeGraph {
        var packer = ExchangeBundlePacker(kind: kind)
        for record in records {
            #expect(try packer.add(record) == .added)
        }
        return try packer.bundle(packedAt: GoldenFixtures.conversionInstant)
    }

    @Test
    func writePackedBundles() async throws {
        let exporter = try Self.exporter()
        let workout = GoldenFixtures.workout(withEvents: true, device: GoldenFixtures.watch, userEntered: false)
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: GoldenCase.seriesFacts(uuid: 0xC9, duration: 2)
        )
        let exports = try await ExporterFixtures.collect(exporter, [
            .sample(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC0), device: GoldenFixtures.watch, writer: ExporterGolden.watchSource)),
            .sample(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC1), device: GoldenFixtures.watch, writer: ExporterGolden.watchSource)),
            .sample(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC2), writer: ExporterGolden.deploymentWriter)),
            .sample(try GoldenCase.bloodPressure(uuid: 0xC3, components: (0xC4, 0xC5))),
            .sample(try StoredSampleFixtures.stored(workout, uuid: GoldenFixtures.uuid(0xC6))),
            try ExporterFixtures.electrocardiogram(uuid: 0xC7, symptoms: [GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xC8))]),
            .heartbeatSeries(series, beats: [
                HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0, precededByGap: false),
                HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0.84, precededByGap: false)
            ])
        ])
        // A record staged before an update waits beside the records after it: its application is a Device of its own.
        let updated = ApplicationDevice.test(name: "Grove Study", bundleIdentifier: "org.example.study", version: "4.2.0", build: "420")
        let later = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xCA), device: GoldenFixtures.watch, writer: ExporterGolden.watchSource)
        let afterUpdate = try await ExporterFixtures.collect(
            Self.exporter(application: updated),
            samples: [later],
            at: GoldenFixtures.conversionInstant.addingTimeInterval(3_600)
        )
        let records = (exports + afterUpdate).compactMap(\.record)
        #expect(records.count == exports.count + 1 && records.count >= 9)
        let active = try Self.packed(records, kind: .active)
        #expect(try active.records().map(\.version) == records.map(\.version))

        let deletions = [0xC0, 0xC1, 0xC2].map { ExporterFixtures.deletion($0) }
        let retractions = try await ExporterFixtures.retract(exporter, deletions).compactMap(\.record)
        #expect(retractions.count == deletions.count)
        let retraction = try Self.packed(retractions, kind: .retraction)

        let directory = ConformanceFixtureTests.fixtureDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try active.json.write(to: directory.appendingPathComponent("packed-exchange-bundle.json"))
        try retraction.json.write(to: directory.appendingPathComponent("packed-retraction-bundle.json"))
    }
}

#endif
