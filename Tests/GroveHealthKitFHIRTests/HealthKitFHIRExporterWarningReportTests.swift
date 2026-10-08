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


/// A warning report summarizes the warnings of many exports by kind: it counts samples, not located elements, names
/// each kind's HealthKit cause, and renders the same text for the same exports.
@Suite
struct HealthKitFHIRExporterWarningReportTests {
    /// A metadata key no source type's graph represents.
    static let unmodeledKey: [String: any Sendable] = ["com.example.note": "x"]

    /// The exports of one call covering every warning the adapter raises, a clean sample and a refusal:
    /// - two heart rates without a time zone, one on a device without a per-unit token;
    /// - a step count over a minute without a time zone, which states both ends of its Period in UTC, carrying a key
    ///   its graph does not represent;
    /// - a heart rate with a time zone carrying that key, and one with a time zone on a device without a token;
    /// - a heart rate with a time zone on a device with a token, which raises nothing;
    /// - a bare ECG, refused for want of its voltages.
    static func exports() async throws -> [HealthKitFHIRExporter.Export] {
        let zoned = GoldenFixtures.timeZoneMetadata
        let steps = try StoredSampleFixtures.quantitySample(
            HKQuantityType(.stepCount),
            value: 120,
            unit: .count(),
            facts: StoredSampleFixtures.SampleFacts(
                uuid: GoldenFixtures.uuid(0x53),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart.addingTimeInterval(60),
                device: nil,
                metadata: unmodeledKey,
                writer: .unattributed
            )
        )
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            facts: GoldenCase.seriesFacts(uuid: 0x57, duration: 30)
        )
        let samples: [HKSample] = [
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x51), metadata: nil),
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x52), device: GoldenFixtures.watchWithoutUnitToken, metadata: nil),
            steps,
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x54), metadata: zoned.merging(unmodeledKey) { $1 }),
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x55), device: GoldenFixtures.watchWithoutUnitToken),
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x56), device: GoldenFixtures.watch),
            ecg
        ]
        let (exports, _) = try await ExporterFixtures.collect(ExporterFixtures.exporter(), samples: samples)
        return exports
    }

    /// One report of every export of `exports`.
    static func report(_ exports: [HealthKitFHIRExporter.Export]) -> HealthKitFHIRExporter.WarningReport {
        var report = HealthKitFHIRExporter.WarningReport()
        for export in exports {
            report.add(export)
        }
        return report
    }

    @Test("Each kind counts samples by type identifier and collects its locations; a clean sample and a refusal add nothing")
    func kindsCountSamples() async throws {
        let exports = try await Self.exports()
        try #require(exports.count == 7)
        #expect(exports[2].warnings == [
            ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKSample.metadata"),
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectivePeriod.start"),
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: "Observation.effectivePeriod.end")
        ], "the step count raises the offset at both ends of its Period")
        #expect(exports[5].warnings.isEmpty)
        #expect(exports[6].graph == nil && exports[6].warnings.isEmpty)
        let heartRate = HKQuantityTypeIdentifier.heartRate.rawValue
        let stepCount = HKQuantityTypeIdentifier.stepCount.rawValue
        let kinds = Self.report(exports).kinds
        #expect(kinds.map(\.code) == [
            ExchangeGraphRule.mobileOmissionSourceOffset,
            .mobileOmissionRecordingDevice,
            .mobileOmissionUnmodeledMetadata
        ].map(\.rawValue), "the most samples first, then by code")
        try #require(kinds.count == 3)
        #expect(kinds.map(\.sampleCount) == [3, 2, 2], "the step count's two offset warnings count it once")
        #expect(kinds.map(\.sampleCountByType) == [[heartRate: 2, stepCount: 1], [heartRate: 2], [heartRate: 1, stepCount: 1]])
        #expect(kinds.map(\.locations) == [
            ["Observation.effectiveDateTime", "Observation.effectivePeriod.start", "Observation.effectivePeriod.end"],
            ["Observation.device"],
            ["HKSample.metadata"]
        ])
        #expect(kinds.map(\.reason) == [
            ExchangeGraphRule.mobileOmissionSourceOffset,
            .mobileOmissionRecordingDevice,
            .mobileOmissionUnmodeledMetadata
        ].map(\.reason))
    }

    @Test("The description renders one block per kind, its types the most first, then by identifier")
    func descriptionIsExact() async throws {
        let expected = [
            "mobile-omission.source-offset at Observation.effectiveDateTime, Observation.effectivePeriod.end, "
                + "Observation.effectivePeriod.start",
            "  Effective time written in UTC: the sample names no HKMetadataKeyTimeZone (nor, for blood pressure, do its members "
                + "agree on one) — 3 samples: HKQuantityTypeIdentifierHeartRate 2, HKQuantityTypeIdentifierStepCount 1",
            "mobile-omission.recording-device at Observation.device",
            "  No recording Device: the recording-device policy resolved the sample's HKDevice to no physical unit (by default, "
                + "the device has no localIdentifier) — 2 samples: HKQuantityTypeIdentifierHeartRate 2",
            "mobile-omission.unmodeled-metadata at HKSample.metadata",
            "  Metadata withheld: the sample, or a correlation member, workout event or workout activity it contains, carries "
                + "metadata keys its graph does not represent — 2 samples: HKQuantityTypeIdentifierHeartRate 1, "
                + "HKQuantityTypeIdentifierStepCount 1"
        ]
        let exports = try await Self.exports()
        #expect(Self.report(exports).description == expected.joined(separator: "\n"))
        #expect(Self.report(exports.reversed()).description == expected.joined(separator: "\n"), "independent of the order")
    }

    @Test("An empty report says so; counts group their thousands; an unknown code's cause is its reason")
    func edgesRenderPlainly() async throws {
        var report = HealthKitFHIRExporter.WarningReport()
        #expect(report.isEmpty)
        #expect(report.description == "No warnings")
        let exports = try await Self.exports()
        report.add(exports[5])
        report.add(exports[6])
        #expect(report.isEmpty, "a clean graph and a refusal raise nothing")
        let unknown = ProducerDiagnostic(
            code: "example.unknown",
            reason: "An unknown rule's reason.",
            location: "Observation.note",
            severity: .warning
        )
        let export = HealthKitFHIRExporter.Export(source: exports[0].source, outcome: exports[0].outcome, warnings: [unknown])
        for _ in 0..<1_234 {
            report.add(export)
        }
        #expect(!report.isEmpty)
        #expect(report.kinds.map(\.cause) == ["An unknown rule's reason."])
        #expect(report.description == """
            example.unknown at Observation.note
              An unknown rule's reason. — 1,234 samples: HKQuantityTypeIdentifierHeartRate 1,234
            """)
    }
}

#endif
