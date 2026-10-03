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
            shape: GoldenCase.seriesShape(uuid: ordinal, duration: 2)
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
}

#endif
