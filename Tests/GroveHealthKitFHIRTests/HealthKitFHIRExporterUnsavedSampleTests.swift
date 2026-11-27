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

    /// A 120/80 reading; the correlation takes `ordinal` and its two members the next two. Each is attributed to
    /// `writer`, as HealthKit attributes a saved correlation's members to the correlation's source.
    private static func bloodPressure(uuid ordinal: UInt8, writer: StoredSampleFixtures.Writer?) throws -> HKCorrelation {
        func member(_ type: HKQuantityTypeIdentifier, _ value: Double, ordinal: UInt8) throws -> HKQuantitySample {
            let sample = HKQuantitySample(
                type: HKQuantityType(type),
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: value),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart,
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(ordinal), writer: writer)
        }
        let members = [
            try member(.bloodPressureSystolic, 120, ordinal: ordinal + 1),
            try member(.bloodPressureDiastolic, 80, ordinal: ordinal + 2)
        ]
        guard let writer else {
            let correlation = HKCorrelation(
                type: HKCorrelationType(.bloodPressure),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart,
                objects: Set<HKSample>(members),
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try StoredSampleFixtures.stored(correlation, uuid: GoldenFixtures.uuid(ordinal))
        }
        // HealthKit's initializer refuses members that are attributed to a writer.
        return try StoredSampleFixtures.correlation(
            HKCorrelationType(.bloodPressure),
            objects: members,
            facts: StoredSampleFixtures.SampleFacts(
                uuid: GoldenFixtures.uuid(ordinal),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart,
                device: nil,
                metadata: GoldenFixtures.timeZoneMetadata,
                writer: writer
            )
        )
    }

    /// A meal of two protein entries; the correlation takes `ordinal` and its members the next two, each attributed to
    /// `writer` as HealthKit attributes a saved correlation's members.
    private static func food(uuid ordinal: UInt8, writer: StoredSampleFixtures.Writer?) throws -> HKCorrelation {
        let start = GoldenFixtures.sampleStart
        let members = try (1...2).map { offset in
            let sample = HKQuantitySample(
                type: HKQuantityType(.dietaryProtein),
                quantity: HKQuantity(unit: .gram(), doubleValue: 12),
                start: start,
                end: start.addingTimeInterval(60),
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(ordinal + UInt8(offset)), writer: writer)
        }
        guard let writer else {
            let correlation = HKCorrelation(
                type: HKCorrelationType(.food),
                start: start,
                end: start.addingTimeInterval(120),
                objects: Set<HKSample>(members),
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try StoredSampleFixtures.stored(correlation, uuid: GoldenFixtures.uuid(ordinal))
        }
        return try StoredSampleFixtures.correlation(
            HKCorrelationType(.food),
            objects: members,
            facts: StoredSampleFixtures.SampleFacts(
                uuid: GoldenFixtures.uuid(ordinal),
                start: start,
                end: start.addingTimeInterval(120),
                device: nil,
                metadata: GoldenFixtures.timeZoneMetadata,
                writer: writer
            )
        )
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
        let unsavedRecord = try await Self.record(.unsavedSample(.quantitySample(unsaved), source: Self.source))
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

    @Test("An unsaved blood-pressure correlation exports as the same correlation saved by the converting build")
    func unsavedCorrelationStatesTheSavingRevision() async throws {
        let unsaved = try Self.bloodPressure(uuid: 0xB0, writer: nil)
        #expect(!HealthKitAssembly.SourceFacts.namesSource(unsaved.sourceRevision))
        let saved = try Self.bloodPressure(uuid: 0xB0, writer: Self.savingWriter)
        let unsavedRecord = try await Self.record(.unsavedSample(.correlation(unsaved), source: Self.source))
        let savedRecord = try await Self.record(.sample(saved))
        #expect(unsavedRecord == savedRecord)
        // As a plain sample, the unsaved correlation names no source.
        let plainRecord = try await Self.record(.sample(unsaved))
        #expect(plainRecord != savedRecord)
    }

    @Test("An unsaved food correlation exports with its members as the same correlation saved by the converting build")
    func unsavedFoodStatesTheSavingRevision() async throws {
        let unsaved = try Self.food(uuid: 0xC0, writer: nil)
        let saved = try Self.food(uuid: 0xC0, writer: Self.savingWriter)
        let unsavedExports = try await ExporterFixtures.collect(Self.exporter(), [.unsavedSample(.correlation(unsaved), source: Self.source)])
        let savedExports = try await ExporterFixtures.collect(Self.exporter(), [.sample(saved)])
        try #require(unsavedExports.count == 3 && savedExports.count == 3)
        try #require(unsavedExports.allSatisfy { $0.record != nil })
        #expect(unsavedExports.compactMap { $0.record?.json } == savedExports.compactMap { $0.record?.json })
    }

    @Test("An unsaved sample whose revision names a source keeps its own revision")
    func heldSampleKeepsItsRevision() async throws {
        let held = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xA2), writer: GoldenFixtures.foreignWriter)
        let asUnsaved = try await Self.record(.unsavedSample(.quantitySample(held), source: Self.source))
        let asSample = try await Self.record(.sample(held))
        #expect(asUnsaved == asSample)
    }

    @Test("An unsaved sample of a source that names nothing states no origin, as a plain sample does")
    func unnamedSourceStatesNothing() async throws {
        let unsaved = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xA3))
        let unnamed = try StoredSampleFixtures.source(name: "", bundleIdentifier: "")
        let asUnsaved = try await Self.record(.unsavedSample(.quantitySample(unsaved), source: unnamed))
        let asSample = try await Self.record(.sample(unsaved))
        #expect(asUnsaved == asSample)
    }
}

#endif
