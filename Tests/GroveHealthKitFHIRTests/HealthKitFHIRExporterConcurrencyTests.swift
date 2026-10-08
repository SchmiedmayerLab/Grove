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


@Suite("HealthKitFHIRExporter concurrency")
struct HealthKitFHIRExporterConcurrencyTests {
    /// More heart rates than one chunk builds at once, so a call builds and hands over two chunks.
    static func samples() throws -> [HKSample] {
        try (0..<(ConcurrentBuild.chunkSize + 44)).map { index in
            let uuid = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index)))
            return try GoldenFixtures.heartRate(uuid: uuid)
        }
    }

    @Test("Building on one task or on several hands over the same exports, in input order")
    func concurrencyChangesNoExport() async throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let samples = try Self.samples()
        let serial = try ExporterFixtures.exporter(storage: storage) { $0.maximumConcurrency = 1 }
        let (serialExports, receipt) = try await ExporterFixtures.collect(serial, samples: samples)
        // The exact retry before the release reproduces every event, so equal bytes show the width changes nothing.
        let concurrent = try ExporterFixtures.exporter(storage: storage) { $0.maximumConcurrency = 8 }
        let (concurrentExports, _) = try await ExporterFixtures.collect(concurrent, samples: samples)

        #expect(serialExports.map(\.source.uuid) == samples.map(\.uuid))
        #expect(serialExports.allSatisfy { $0.graph != nil })
        #expect(concurrentExports.map(\.source.uuid) == samples.map(\.uuid))
        #expect(concurrentExports.map(\.graph?.json) == serialExports.map(\.graph?.json))
        receipt.release()
    }

    @Test("A cancelled export throws CancellationError and hands nothing over")
    func cancellationStopsTheCall() async throws {
        let exporter = try ExporterFixtures.exporter()
        let samples = try Self.samples()
        let outcome = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var received = 0
            do {
                _ = try await exporter.export(samples, at: GoldenFixtures.conversionInstant) { _ in received += 1 }
                return (received: received, cancelled: false)
            } catch {
                return (received: received, cancelled: error is CancellationError)
            }
        }.value

        #expect(outcome.cancelled)
        #expect(outcome.received == 0)
    }
}

#endif
