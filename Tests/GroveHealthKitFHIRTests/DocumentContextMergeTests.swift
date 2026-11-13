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
/// recording period and related outputs stay first.
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

    @Test("An exported HealthKit recording keeps its source period alongside the study references")
    func healthKitDocumentContextKeepsPeriodAndStudies() async throws {
        let record = try Self.record()
        let producer = try ExporterFixtures.producer(studies: Self.enrollments)
        let exports = try await ExporterFixtures.collect(
            try ExporterFixtures.exporter(producer),
            [.heartbeatSeries(record.series, beats: record.heartbeats)]
        )
        let (document, studies) = try Self.document(in: try #require(exports.first?.record?.graph))
        #expect(studies.count == 2)
        let period = try #require(document.context?.period)
        #expect(try #require(period.start?.value).asNSDate() == record.series.startDate)
        #expect(try #require(period.end?.value).asNSDate() == record.series.endDate)
        #expect(document.context?.related?.compactMap { $0.reference?.value?.string } == studies)
    }

    @Test("A document's own period and related references stay, and the study references follow them")
    func documentContextKeepsTheAdaptersStatements() throws {
        let record = try Self.record()
        let plan = HealthKitContentPlan[.heartbeatSeries]
        let recording = try plan.recordingDocument().beatIntervals(seriesStart: record.series.startDate, heartbeats: record.heartbeats)
        var document = try plan.recordingDocument().document(recording: recording)
        let period = Period(
            end: FHIRPrimitive(try ExchangeInstant.fhirDateTime(record.series.endDate)),
            start: FHIRPrimitive(try ExchangeInstant.fhirDateTime(record.series.startDate))
        )
        let adapterReference = Reference(display: "The adapter's own related output".asFHIRStringPrimitive())
        document.context = DocumentReferenceContext(period: period, related: [adapterReference])
        // Exercise assembly with an already mapped period and an adapter-owned related reference.
        let base = TestDeployment.test()
        let assembly = HealthKitAssembly(scope: ExchangeEnvelope.Scope(
            adapter: HealthKitAssembly.adapter,
            identityScope: base.identityScope,
            subject: base.subject,
            repositoryScope: base.repositoryScope
        ))
        let request = HealthKitAssembly.Request(
            instant: base.conversionInstant,
            facts: ConversionFacts(application: base.application, host: base.host, studies: Self.enrollments)
        )
        let conversion = try #require(try assembly.documentGraph(for: record.series, plan: plan, document: document, request: request).first)
        let (stated, studies) = try Self.document(in: conversion.record.graph)
        #expect(studies.count == 2)
        #expect(stated.context?.period == period)
        #expect(stated.context?.related?.first == adapterReference)
        #expect(stated.context?.related?.dropFirst().compactMap { $0.reference?.value?.string } == studies)
    }
}

#endif
