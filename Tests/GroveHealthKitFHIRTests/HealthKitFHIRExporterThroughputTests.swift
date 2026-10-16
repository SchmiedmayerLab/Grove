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


@Suite("HealthKitFHIRExporter throughput")
struct HealthKitFHIRExporterThroughputTests {
    /// Two heart rates and a bare ECG, which `export(_:)` refuses after reserving its event.
    static func samples() throws -> [HKSample] {
        [
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x61)),
            try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x62)),
            try StoredSampleFixtures.seriesSample(
                HKElectrocardiogram.self,
                sampleType: HKObjectType.electrocardiogramType(),
                facts: GoldenCase.seriesFacts(uuid: 0x63, duration: 30)
            )
        ]
    }

    @Test("An exporter measures nothing unless asked, and measuring changes no graph byte")
    func measuringChangesNoByte() async throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let plain = try ExporterFixtures.exporter(storage: storage)
        #expect(plain.throughput == nil)
        let (plainExports, receipt) = try await ExporterFixtures.collect(plain, samples: try Self.samples())
        // The exact retry before the release reproduces every event, so equal bytes show measuring is not fingerprinted.
        let measuring = try ExporterFixtures.exporter(storage: storage) { $0.measuresThroughput = true }
        let (measuredExports, _) = try await ExporterFixtures.collect(measuring, samples: try Self.samples())

        #expect(measuredExports.map(\.graph?.json) == plainExports.map(\.graph?.json))
        receipt.release()
    }

    @Test("A measuring exporter counts records, graphs, refusals and bytes per type, times every phase and adds up calls")
    func countsAndTimes() async throws {
        let exporter = try ExporterFixtures.exporter { $0.measuresThroughput = true }
        let (exports, _) = try await ExporterFixtures.collect(exporter, samples: try Self.samples())
        let throughput = try #require(exporter.throughput)

        #expect(throughput.calls == 1)
        #expect(throughput.records == 3)
        let heartRate = try #require(throughput.sourceTypes[HKQuantityTypeIdentifier.heartRate.rawValue])
        #expect(heartRate.records == 2)
        #expect(heartRate.graphs == 2)
        #expect(heartRate.refusals == 0)
        #expect(heartRate.bytes == exports.compactMap(\.graph).map(\.json.count).reduce(0, +))
        let ecg = try #require(throughput.sourceTypes[HKObjectType.electrocardiogramType().identifier])
        #expect(ecg.records == 1)
        #expect(ecg.graphs == 0)
        #expect(ecg.refusals == 1)
        #expect(throughput.phases.plan > .zero)
        #expect(throughput.phases.reserve > .zero)
        #expect(throughput.phases.assemble > .zero)
        #expect(throughput.phases.validate > .zero)
        #expect(throughput.busy > .zero)

        _ = try await ExporterFixtures.collect(exporter, samples: [try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x64))])
        let twice = try #require(exporter.throughput)
        #expect(twice.calls == 2)
        #expect(twice.records == 4)
        #expect(twice.sourceTypes[HKQuantityTypeIdentifier.heartRate.rawValue]?.graphs == 3)
    }

    @Test("The report states the totals, then each type by record count")
    func report() async throws {
        #expect(HealthKitFHIRExporter.Throughput().description == "No HealthKit export measured")
        let exporter = try ExporterFixtures.exporter { $0.measuresThroughput = true }
        _ = try await ExporterFixtures.collect(exporter, samples: try Self.samples())
        let lines = try #require(exporter.throughput).description.split(separator: "\n").map(String.init)

        try #require(lines.count == 4)
        #expect(lines[0].hasPrefix("HealthKit export: 3 records in 1 call, "))
        #expect(lines[1].hasPrefix("  plan "))
        #expect(lines[2].hasPrefix("  \(HKQuantityTypeIdentifier.heartRate.rawValue): 2 records, 2 graphs, 0 refusals · "))
        #expect(lines[3].hasPrefix("  \(HKObjectType.electrocardiogramType().identifier): 1 record, 0 graphs, 1 refusal · "))
    }
}

#endif
