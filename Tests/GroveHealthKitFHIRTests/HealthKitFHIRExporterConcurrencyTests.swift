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
    /// More heart rates than eight child tasks build ahead of the caller, so a call hands over slices while it still builds.
    static func samples() throws -> [HKSample] {
        try (0..<(2 * 8 * ConcurrentBuild.maximumSliceSize + 44)).map { index in
            let uuid = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index)))
            return try GoldenFixtures.heartRate(uuid: uuid)
        }
    }

    @Test("Building on one task or on several hands over the same exports, in input order")
    func concurrencyChangesNoExport() async throws {
        let samples = try Self.samples()
        let serial = try ExporterFixtures.exporter { $0.maximumConcurrency = 1 }
        let serialExports = try await ExporterFixtures.collect(serial, samples: samples)
        let concurrent = try ExporterFixtures.exporter { $0.maximumConcurrency = 8 }
        let concurrentExports = try await ExporterFixtures.collect(concurrent, samples: samples)

        #expect(serialExports.map(\.source.uuid) == samples.map(\.uuid))
        #expect(serialExports.allSatisfy { $0.record != nil })
        #expect(concurrentExports.map(\.source.uuid) == samples.map(\.uuid))
        #expect(concurrentExports.map(\.record) == serialExports.map(\.record))
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
