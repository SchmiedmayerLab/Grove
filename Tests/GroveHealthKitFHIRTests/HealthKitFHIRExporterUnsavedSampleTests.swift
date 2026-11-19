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


/// A sample the application created and did not save into HealthKit states the revision HealthKit would have stamped
/// on saving it, so its record is the one the saved sample's would be.
@Suite
struct HealthKitFHIRExporterUnsavedSampleTests {
    private static let application = GoldenFixtures.selfConverter(version: "1.0", build: "42")

    /// The converting application as HealthKit names it.
    private static let source: HKSource = {
        // swiftlint:disable:next force_try
        try! StoredSampleFixtures.source(name: "Grove Test", bundleIdentifier: application.bundleIdentifier)
    }()

    /// The writer HealthKit would stamp if the converting build saved a sample on this host now.
    private static let savingWriter = StoredSampleFixtures.Writer(
        name: "Grove Test",
        bundleIdentifier: application.bundleIdentifier,
        version: "42",
        productType: ExporterFixtures.base.host.productType,
        operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
    )

    /// States the converting application as the writer of its own samples, and as their gateway in the build it runs.
    private static func exporter() throws -> HealthKitFHIRExporter {
        try ExporterFixtures.exporter(ExporterFixtures.producer(application: application)) { options in
            options.writer = .applications([application.bundleIdentifier])
            options.role = .gatewayForOwnWrites
        }
    }

    private static func record(_ record: HealthKitFHIRExporter.Record) async throws -> ExchangeRecord {
        let exports = try await ExporterFixtures.collect(exporter(), [record])
        try #require(exports.count == 1)
        return try #require(exports.first?.record)
    }

    @Test("An unsaved sample exports as the same sample saved by the converting build and fetched back")
    func unsavedSampleStatesTheSavingRevision() async throws {
        let uuid = GoldenFixtures.uuid(0xA1)
        let unsaved = try GoldenFixtures.heartRate(uuid: uuid)
        #expect(!HealthKitAssembly.SourceFacts.namesSource(unsaved.sourceRevision))
        let saved = try GoldenFixtures.heartRate(uuid: uuid, writer: Self.savingWriter)
        let unsavedRecord = try await Self.record(.unsavedSample(unsaved, source: Self.source))
        let savedRecord = try await Self.record(.sample(saved))
        #expect(unsavedRecord == savedRecord)
        // The saved sample states its writer as the Provenance author, and the converting build as its gateway.
        let bundle = savedRecord.bundle
        let provenance = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        #expect(provenance.entity?.first?.agent?.contains { agent in
            agent.type?.coding?.contains { $0.code?.value?.string == "author" } == true
        } == true)
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first)
        #expect(observation.extension?.contains { $0.url == Canonicals.gatewayDevice } == true)
        // As a plain sample, the unsaved one names no source: no writer, no source revision, no gateway.
        let plainRecord = try await Self.record(.sample(unsaved))
        #expect(plainRecord != savedRecord)
        let plainObservation = try #require(plainRecord.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first)
        #expect(plainObservation.extension?.contains { $0.url == Canonicals.gatewayDevice } != true)
    }

    @Test("An unsaved sample whose revision names a source keeps its own revision")
    func heldSampleKeepsItsRevision() async throws {
        let held = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xA2), writer: GoldenFixtures.foreignWriter)
        let asUnsaved = try await Self.record(.unsavedSample(held, source: Self.source))
        let asSample = try await Self.record(.sample(held))
        #expect(asUnsaved == asSample)
    }

    @Test("An unsaved sample of a source that names nothing states no origin, as a plain sample does")
    func unnamedSourceStatesNothing() async throws {
        let unsaved = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xA3))
        let unnamed = try StoredSampleFixtures.source(name: "", bundleIdentifier: "")
        let asUnsaved = try await Self.record(.unsavedSample(unsaved, source: unnamed))
        let asSample = try await Self.record(.sample(unsaved))
        #expect(asUnsaved == asSample)
    }
}

#endif
