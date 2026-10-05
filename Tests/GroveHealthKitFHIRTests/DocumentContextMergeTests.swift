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


/// The assembler adds the study references to a document's own context instead of replacing it, so an adapter's
/// period and related outputs stay first; no HealthKit document states a context of its own, so its bytes do not change.
@Suite
struct DocumentContextMergeTests {
    private static let enrollments = [StudyEnrollment.test("a"), StudyEnrollment.test("b")]

    private static func record() throws -> (series: HKHeartbeatSeriesSample, heartbeats: [HealthKitFHIRExporter.Record.Heartbeat]) {
        let series = try StoredSampleFixtures.seriesSample(
            HKHeartbeatSeriesSample.self,
            sampleType: HKSeriesType.heartbeat(),
            facts: GoldenCase.seriesFacts(uuid: 0xE1, duration: 2)
        )
        return (series, [
            HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0, precededByGap: false),
            HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: 0.84, precededByGap: false)
        ])
    }

    /// The graph's DocumentReference and the fullUrls of its ResearchStudy entries, in entry order.
    private static func document(in graph: ExchangeGraph) throws -> (document: DocumentReference, studies: [String]) {
        let entries = graph.bundle.entry ?? []
        let documents = entries.compactMap { $0.resource?.get(if: DocumentReference.self) }
        let document = try #require(documents.first)
        let studies = entries.filter { $0.resource?.get(if: ResearchStudy.self) != nil }.compactMap { $0.fullUrl?.value?.url.absoluteString }
        return (document, studies)
    }

    @Test("An exported HealthKit document states exactly the study references as its context")
    func healthKitDocumentContextIsTheStudies() throws {
        let record = try Self.record()
        let producer = try ExporterFixtures.producer(studies: Self.enrollments, storage: ExchangeProducer.InMemoryStorage())
        let (exports, _) = try ExporterFixtures.collect(
            try ExporterFixtures.exporter(producer),
            [.heartbeatSeries(record.series, beats: record.heartbeats)]
        )
        let (document, studies) = try Self.document(in: try #require(exports.first?.graph))
        #expect(studies.count == 2)
        #expect(document.context == DocumentReferenceContext(related: document.context?.related))
        #expect(document.context?.related?.compactMap { $0.reference?.value?.string } == studies)
    }

    @Test("A document's own period and related references stay, and the study references follow them")
    func documentContextKeepsTheAdaptersStatements() throws {
        let record = try Self.record()
        let plan = HealthKitContentPlan[.heartbeatSeries]
        var document = try plan.recordingDocument().document(record.series, beats: record.heartbeats)
        let period = Period(
            end: FHIRPrimitive(try ExchangeInstant.fhirDateTime(record.series.endDate)),
            start: FHIRPrimitive(try ExchangeInstant.fhirDateTime(record.series.startDate))
        )
        let adapterReference = Reference(display: "The adapter's own related output".asFHIRStringPrimitive())
        document.context = DocumentReferenceContext(period: period, related: [adapterReference])
        // No exporter input states a document context of its own, so the assembly is handed one directly.
        let base = ExchangeEventContext.test()
        let assembly = HealthKitAssembly(scope: ExchangeEnvelope.Scope(
            adapter: HealthKitAssembly.adapter,
            identityScope: base.identityScope,
            subject: base.subject,
            repositoryScope: base.repositoryScope
        ))
        let request = HealthKitAssembly.Request(
            event: base.event,
            instant: base.conversionInstant,
            facts: ExchangeEventFacts(application: base.application, host: base.host, studies: Self.enrollments)
        )
        let conversion = try #require(try assembly.documentGraph(for: record.series, plan: plan, document: document, request: request).first)
        let (stated, studies) = try Self.document(in: conversion.graph)
        #expect(studies.count == 2)
        #expect(stated.context?.period == period)
        #expect(stated.context?.related?.first == adapterReference)
        #expect(stated.context?.related?.dropFirst().compactMap { $0.reference?.value?.string } == studies)
    }
}

#endif
