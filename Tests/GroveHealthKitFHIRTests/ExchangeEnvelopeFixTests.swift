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


/// The envelope rules the pinned guide states and the first assembler missed: what a document graph
/// carries, how event instants are written, and which deletions a route policy lets the exporter retract.
/// One revision and converter build, and whether the converter wrote the sample in the build it runs.
struct SameBuildCase: CustomTestStringConvertible, Sendable {
    let revisionVersion: String?
    let build: String?
    let expected: Bool
    var bundleIdentifier = ApplicationDevice.test.bundleIdentifier

    var testDescription: String {
        "revision \(revisionVersion.map { "'\($0)'" } ?? "nil") of \(bundleIdentifier), build \(build ?? "nil")"
    }
}


@Suite
struct ExchangeEnvelopeFixTests {
    private static let base = ExchangeEventContext.test()

    private static func exporter(
        application: ApplicationDevice = base.application,
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }
    ) throws -> HealthKitFHIRExporter {
        let producer = try ExchangeProducer(
            identityScope: base.identityScope,
            subject: base.subject,
            application: application,
            host: base.host,
            sequencer: .inMemory()
        )
        var options = HealthKitFHIRExporter.Options()
        configure(&options)
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: base.repositoryScope, options: options)
    }

    private static func heartbeatSeries(uuid ordinal: UInt8) throws -> HealthKitHeartbeatSeriesRecord {
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: GoldenCase.seriesFacts(uuid: ordinal, duration: 2)
        )
        return HealthKitHeartbeatSeriesRecord(series: series, heartbeats: [
            HealthKitHeartbeat(timeSinceSeriesStart: 0, precededByGap: false),
            HealthKitHeartbeat(timeSinceSeriesStart: 0.84, precededByGap: false)
        ])
    }

    @Test("A document graph under a distinct gateway application carries no gateway Device, as Observations alone name one")
    @available(*, deprecated, message: "Exercises the deprecated converter's document path")
    func documentGraphsOmitTheGatewayApplication() throws {
        let gateway = ApplicationDevice.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1")
        let context = HealthKitConversionContext(event: .test(converterRole: .gatewayApplication(gateway)))
        let conversion = try HealthKitConverter().convert(try Self.heartbeatSeries(uuid: 90), context: context)
        let snapshot = try context.identityScope.deviceSnapshot(
            event: context.event.event,
            role: .application,
            sourceDeviceToken: gateway.sourceDeviceToken
        )
        #expect(conversion.graph.resource(Device.self, at: snapshot) == nil)
        let assembled = try HealthKitConverter().convert(try Self.heartbeatSeries(uuid: 90), context: HealthKitConversionContext())
        #expect(conversion.graph.json == assembled.graph.json)
    }

    #if !os(watchOS)
    @Test("A document carries no writer-record identifier: the version that must travel with it has no carrier there")
    @available(*, deprecated, message: "Exercises the deprecated converter's document path")
    func documentsCarryNoWriterRecord() throws {
        var metadata = GoldenFixtures.timeZoneMetadata
        metadata[HKMetadataKeySyncIdentifier] = "document-1"
        metadata[HKMetadataKeySyncVersion] = 3
        let document = try HKCDADocumentSample(
            data: Data(GoldenCase.clinicalDocumentXML.utf8),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(1),
            metadata: metadata
        )
        let stored = try StoredSampleFixtures.stored(document, uuid: GoldenFixtures.uuid(91), writer: GoldenFixtures.foreignWriter)
        let conversion = try HealthKitConverter().convert(stored, context: HealthKitConversionContext())
        let roles = try conversion.document.identifier?.map { try RoledIdentifier($0).role } ?? []
        #expect(!roles.contains(.writerRecord))
        #expect(roles == [.sourceRecord, .sourceOutput, .sourceArtifact])
    }
    #endif

    /// The guide requires the pair be rejected on every HealthKit source record (mapping.md, logical identity and
    /// revisions), so a document refuses a malformed pair although it would not state the identity.
    @Test("A document refuses a malformed sync pair, as every HealthKit source record does")
    @available(*, deprecated, message: "Exercises the deprecated converter's document path")
    func documentsRefuseAMalformedSyncPair() throws {
        let malformed: [[String: any Sendable]] = [
            [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeySyncIdentifier: "series-1"],
            [HKMetadataKeyTimeZone: GoldenFixtures.timeZone, HKMetadataKeySyncIdentifier: "series-1", HKMetadataKeySyncVersion: 1.5]
        ]
        for metadata in malformed {
            var facts = GoldenCase.seriesFacts(uuid: 89, duration: 2)
            facts.metadata = metadata
            let series = try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts)
            let record = HealthKitHeartbeatSeriesRecord(series: series, heartbeats: [HealthKitHeartbeat(timeSinceSeriesStart: 0, precededByGap: false)])
            #expect(throws: HealthKitConversionError.invalidValue(.heartbeatSeries, .invalidMetadataValue(.syncVersion))) {
                try HealthKitConverter().convert(record, context: HealthKitConversionContext())
            }
        }
    }

    @Test("Event instants are written in UTC at millisecond precision, without binary noise")
    @available(*, deprecated, message: "Exercises the deprecated converter, which takes any instant")
    func eventInstantsAreMilliseconds() throws {
        let context = HealthKitConversionContext(event: .test(conversionInstant: Date(timeIntervalSince1970: 1_787_009_400.2514)))
        let conversion = try HealthKitConverter().convert(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(92)), context: context)
        #expect(conversion.bundle.timestamp?.value?.description == "2026-08-17T23:30:00.251Z")
        let provenance = try #require(conversion.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        #expect(provenance.recorded.value?.description == "2026-08-17T23:30:00.251Z")
        guard case .dateTime(let occurred)? = provenance.occurred else {
            Issue.record("A conversion Provenance occurs at the conversion instant")
            return
        }
        #expect(occurred.value?.description == "2026-08-17T23:30:00.251Z")
        // No FHIR instant states an event before year 1: the conversion is refused, never written as a sentinel.
        let unstatable = HealthKitConversionContext(event: .test(conversionInstant: .distantPast))
        let refusal = #expect(throws: HealthKitConversionError.self) {
            try HealthKitConverter().convert(try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(92)), context: unstatable)
        }
        guard case .dependency? = refusal else {
            Issue.record("An unstatable event instant is a dependency refusal, not \(String(describing: refusal))")
            return
        }
    }

    @Test("A retraction states its bounds and its recording in UTC at millisecond precision, and a start before year 1 as year 1")
    @available(*, deprecated, message: "Exercises the deprecated converter's retraction, which takes any instant")
    func retractionInstantsAreMilliseconds() throws {
        let context = HealthKitConversionContext(event: .test(conversionInstant: Date(timeIntervalSince1970: 1_787_009_400.2514)))
        func provenance(_ occurred: RetractionOccurrence) throws -> (bundle: ModelsR4.Bundle, provenance: Provenance) {
            let record = HealthKitSourceRecord(uuid: GoldenFixtures.uuid(96), type: .heartRate)
            let bundle = try HealthKitConverter().retraction(for: record, context: context, occurred: occurred).graph.bundle
            return (bundle, try #require(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first))
        }
        let bounded = try provenance(.period(
            start: Date(timeIntervalSince1970: 1_787_005_800.0004),
            end: Date(timeIntervalSince1970: 1_787_009_400.9996)
        ))
        guard case .period(let period)? = bounded.provenance.occurred else {
            Issue.record("A retraction with bounds occurs over a period")
            return
        }
        #expect(period.start?.value?.description == "2026-08-17T22:30:00Z")
        #expect(period.end?.value?.description == "2026-08-17T23:30:01Z", "rounding carries into the next second")
        #expect(bounded.provenance.recorded.value?.description == "2026-08-17T23:30:00.251Z")
        #expect(bounded.bundle.timestamp?.value?.description == "2026-08-17T23:30:00.251Z")
        guard case .dateTime(let instant)? = try provenance(.instant(Date(timeIntervalSince1970: 1_787_009_400.2516))).provenance.occurred else {
            Issue.record("A retraction at an instant occurs at that instant")
            return
        }
        #expect(instant.value?.description == "2026-08-17T23:30:00.252Z")
        guard case .period(let clamped)? = try provenance(.period(start: .distantPast, end: GoldenFixtures.conversionInstant)).provenance.occurred else {
            Issue.record("A retraction with bounds occurs over a period")
            return
        }
        #expect(clamped.start?.value?.description == "0001-01-01T00:00:00Z")
    }

    /// No FHIR dateTime states an instant before year 1 or from year 10000 on. Only a period's start is clamped, as a
    /// lower bound stays true; a retraction refuses any other such occurrence or recording rather than write a sentinel.
    @Test("A retraction refuses an occurrence or a recording no FHIR dateTime can state")
    func retractionRefusesUnstatableInstants() throws {
        let record = try Self.base.identityScope.sourceRecord(
            adapterID: HealthKitAssembly.adapter.adapterID,
            sourceType: HealthKitSourceType.heartRate.rawValue,
            repositoryScope: Self.base.repositoryScope,
            nativeRecordID: GoldenFixtures.uuid(96).uuidString.lowercased()
        )
        let target = try RetractionTarget(identifier: record.output(role: "primary", discriminator: "0"), resourceType: .observation, role: .primaryOutput)
        func retraction(_ occurred: RetractionOccurrence, recordedAt: Date = GoldenFixtures.conversionInstant) throws {
            _ = try RetractionEvent(targets: [target], context: .test(conversionInstant: recordedAt), sourceRecord: record.identifier, occurred: occurred)
        }
        let yearTenThousand = Date(timeIntervalSince1970: 253_402_300_800)
        let unstatable: [RetractionOccurrence] = [
            .instant(.distantPast), .instant(yearTenThousand), .period(start: nil, end: .distantPast), .period(start: nil, end: yearTenThousand)
        ]
        for occurred in unstatable {
            #expect(throws: RetractionEventError.invalidInstant, "occurred \(occurred)") {
                try retraction(occurred)
            }
        }
        #expect(throws: RetractionEventError.invalidInstant, "recorded before year 1") {
            try retraction(.instant(GoldenFixtures.conversionInstant), recordedAt: .distantPast)
        }
        try retraction(.period(start: .distantPast, end: GoldenFixtures.conversionInstant))
    }

    @Test("A document's date is the event instant in UTC at millisecond precision")
    @available(*, deprecated, message: "Exercises the deprecated converter's document path")
    func documentDateIsMilliseconds() throws {
        let context = HealthKitConversionContext(event: .test(conversionInstant: Date(timeIntervalSince1970: 1_787_009_400.2514)))
        let conversion = try HealthKitConverter().convert(try Self.heartbeatSeries(uuid: 97), context: context)
        #expect(conversion.document.date?.value?.description == "2026-08-17T23:30:00.251Z")
    }

    @Test("A route deletion is retracted only while routes are disclosed")
    func routeRetractionFollowsTheRoutePolicy() throws {
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: GoldenFixtures.uuid(93),
            sourceType: .workoutRoute,
            deletedAfter: nil,
            detectedAt: GoldenFixtures.conversionInstant
        )
        var omitted: [HealthKitFHIRExporter.Export] = []
        _ = try Self.exporter().retract([deletion], at: GoldenFixtures.conversionInstant) { omitted.append($0) }
        guard case .nothingToRetract? = omitted.first?.outcome else {
            Issue.record("An undisclosed route was never exported, so there is nothing to retract")
            return
        }
        var authorized: [HealthKitFHIRExporter.Export] = []
        _ = try Self.exporter { $0.route = .authorized }.retract([deletion], at: GoldenFixtures.conversionInstant) { authorized.append($0) }
        #expect(authorized.first?.graph?.kind == .retraction)
    }

    @Test("Under gatewayForOwnWrites only a sample written by the converting build is mediated by it")
    func gatewayForOwnWritesMatchesTheBuild() throws {
        let application = GoldenFixtures.selfConverter(version: "1.0", build: "42")
        let exporter = try Self.exporter(application: application) { $0.role = .gatewayForOwnWrites }
        let sameBuild = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(94), writer: GoldenFixtures.selfWriter(revisionVersion: "42"))
        let olderBuild = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(95), writer: GoldenFixtures.selfWriter(revisionVersion: "41"))
        var exports: [HealthKitFHIRExporter.Export] = []
        _ = try exporter.export([sameBuild, olderBuild], at: GoldenFixtures.conversionInstant) { exports.append($0) }
        func statesGateway(_ export: HealthKitFHIRExporter.Export) -> Bool {
            let observation = export.graph?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first
            return observation?.extension?.contains { $0.url == Canonicals.gatewayDevice } == true
        }
        try #require(exports.count == 2)
        #expect(statesGateway(exports[0]))
        #expect(!statesGateway(exports[1]))
    }

    /// Spec F3: only the exact build matches; HealthKit copies the source's `CFBundleVersion` into the revision.
    @Test(arguments: [
        SameBuildCase(revisionVersion: "42", build: "42", expected: true),
        SameBuildCase(revisionVersion: "41", build: "42", expected: false),
        SameBuildCase(revisionVersion: nil, build: "42", expected: false),
        SameBuildCase(revisionVersion: "   ", build: "42", expected: false),
        SameBuildCase(revisionVersion: "42 ", build: "42", expected: false),
        SameBuildCase(revisionVersion: "42", build: "42", expected: false, bundleIdentifier: "org.example.writer"),
        // An application stating no build is never matched, even when its version equals the revision's.
        SameBuildCase(revisionVersion: "42", build: nil, expected: false)
    ])
    func sameBuildIsExact(_ testCase: SameBuildCase) throws {
        var writer = GoldenFixtures.selfWriter(revisionVersion: testCase.revisionVersion)
        writer.bundleIdentifier = testCase.bundleIdentifier
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(98), writer: writer)
        let application = GoldenFixtures.selfConverter(version: testCase.build == nil ? "42" : "1.2.3", build: testCase.build)
        #expect(HealthKitAssembly.isSameBuild(sample.sourceRevision, as: application) == testCase.expected)
    }

    /// Spec F2: a gateway no output names is no snapshot, so a writer whose token equals it gets its own entries.
    @Test("A writer equal to a gateway no output names is its own snapshot and author, beside its own host")
    @available(*, deprecated, message: "Exercises the deprecated converter's document path")
    func writerEqualToAnUnnamedGatewayIsItsOwnSnapshot() throws {
        var inputs = GoldenFixtures.Inputs.applicationWriter
        inputs.converterRole = .gatewayApplication(.test(name: "Cuff Companion", bundleIdentifier: "org.example.writer", version: "42"))
        var documentInputs = inputs
        documentInputs.repositoryIDs = [.writer: try RepositoryID("w-1")]
        let document = try HealthKitConverter().convert(try Self.heartbeatSeries(uuid: 99), context: GoldenFixtures.context(sequence: 99, documentInputs))
        let writer = try #require(document.writer)
        let writerHost = try #require(document.identifiers.writerHostSnapshot)
        #expect(writer.deviceName?.first?.name.value?.string == "Example Writer")
        #expect(writer.parent?.reference?.value?.string == (try writerHost.fullURLString))
        #expect(writer.id?.value?.string == "w-1")
        let author = document.provenance.entity?.first?.agent?.first { $0.type?.coding?.first?.code?.value?.string == "author" }
        #expect(author?.who.reference?.value?.string == (try document.identifiers.writerSnapshot?.fullURLString))
        // On an Observation, which names the gateway, the same writer is the gateway's entry.
        let observation = try HealthKitConverter().convert(
            GoldenCase.attributedHeartRate(uuid: 0x99, writer: GoldenFixtures.foreignWriter),
            context: GoldenFixtures.context(sequence: 100_099, inputs)
        )
        #expect(observation.writer?.deviceName?.first?.name.value?.string == "Cuff Companion")
        #expect(observation.identifiers.writerHostSnapshot == nil)
        let gateway = observation.observation.extension?.first { $0.url == Canonicals.gatewayDevice }
        guard case .reference(let reference)? = gateway?.value else {
            Issue.record("The Observation names its gateway")
            return
        }
        #expect(reference.reference?.value?.string == (try observation.identifiers.writerSnapshot?.fullURLString))
    }
}

#endif
