//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
@testable import GroveSensorKit
import SensorKit
import Testing


@Suite
struct ECGAnchoredAssemblyTests {
    @Test
    @available(iOS 18, *)
    func splitCallbacksPreservePreSessionCursorAndCrashReplayIdentity() async throws {
        let start = Date.now.addingTimeInterval(-120)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let groups = ECGProcessingTests.groups()
        let deliveryTimestamp = SRAbsoluteTime(start.addingTimeInterval(12))
        let fetcher = Self.fetcher(anchor: anchor)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting([groups[0]], timestamp: SRAbsoluteTime(start.addingTimeInterval(10))))
        #expect(fetcher.processECGGroupsForTesting([groups[1]], timestamp: SRAbsoluteTime(start.addingTimeInterval(11))))
        #expect(try anchor.value.timestamp == start)
        #expect(try anchor.value.pendingBatch == nil)
        #expect(SRAbsoluteTime(start.addingTimeInterval(11)) < deliveryTimestamp)
        nonisolated(unsafe) let reader = fetcher
        let callbacks = Task.detached {
            reader.processECGGroupsForTesting([groups[2]], timestamp: deliveryTimestamp)
        }
        let batch = try #require(try await fetcher.next(isolation: nil))
        _ = await callbacks.value
        #expect(batch.samples == (try SensorKitECGSession.process(groups)))
        #expect(try anchor.value.timestamp == start)
        let pending = try #require(anchor.value.pendingBatch)
        #expect(pending.sampleCount == 1)
        #expect(pending.nativeUpperBoundBits == deliveryTimestamp.rawValue.bitPattern)
        let restarted = Self.fetcher(anchor: anchor)
        try restarted.startNativeFetchForTesting()
        nonisolated(unsafe) let retryReader = restarted
        let retryCallbacks = Task.detached {
            retryReader.processECGGroupsForTesting(groups, timestamp: deliveryTimestamp)
        }
        let replay = try #require(try await restarted.next(isolation: nil))
        _ = await retryCallbacks.value
        #expect(replay.info.acquisitionBatch == batch.info.acquisitionBatch)
        #expect(replay.samples == batch.samples)
        try await replay.acknowledge()
        #expect(try anchor.value.timestamp > start)
        #expect(try anchor.value.pendingBatch == nil)
    }

    @Test
    @available(iOS 18, *)
    func fetchEndSkipsASessionWithoutVoltageSamplesAndAdvances() async throws {
        let start = Date.now.addingTimeInterval(-120)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let fetcher = Self.fetcher(anchor: anchor)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting([ECGProcessingTests.groups()[0]], timestamp: SRAbsoluteTime(start.addingTimeInterval(10))))
        nonisolated(unsafe) let reader = fetcher
        let completion = Task.detached { reader.completeFetchForTesting() }
        #expect(try await fetcher.next(isolation: nil) == nil)
        await completion.value
        #expect(try anchor.value.timestamp > start)
        #expect(try anchor.value.pendingBatch == nil)
    }

    @Test
    @available(iOS 18, *)
    func fetchEndDeliversASessionWithoutItsEndState() async throws {
        let start = Date.now.addingTimeInterval(-120)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let groups = Array(ECGProcessingTests.groups().prefix(2))
        let fetcher = Self.fetcher(anchor: anchor)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting(groups, timestamp: SRAbsoluteTime(start.addingTimeInterval(10))))
        nonisolated(unsafe) let reader = fetcher
        let completion = Task.detached { reader.completeFetchForTesting() }
        let batch = try #require(try await fetcher.next(isolation: nil))
        await completion.value
        #expect(batch.samples == SensorKitECGSession.processLeniently(groups))
        #expect(batch.samples.map(\.sessionStates) == [[.begin, .active]])
        try await batch.acknowledge()
        #expect(try anchor.value.timestamp > start)
        #expect(try anchor.value.pendingBatch == nil)
    }

    @Test
    @available(iOS 18, *)
    func processingCapacityRefusalRetainsCursorForALargerBudgetRetry() async throws {
        let start = Date(timeIntervalSince1970: 90)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let fetcher = Self.fetcher(anchor: anchor, limits: try .init(maximumEntries: 2, maximumSessions: 128))
        let groups = ECGProcessingTests.groups()
        #expect(fetcher.processECGGroupsForTesting([groups[0]], timestamp: SRAbsoluteTime(start)))
        #expect(!fetcher.processECGGroupsForTesting([groups[1]], timestamp: SRAbsoluteTime(start.addingTimeInterval(1))))
        await #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try await fetcher.next(isolation: nil) }
        #expect(try anchor.value.timestamp == start)
        #expect(try anchor.value.pendingBatch == nil)
    }
}


extension ECGAnchoredAssemblyTests {
    @available(iOS 18, *)
    private static func fetcher(
        anchor: ManagedQueryAnchor, limits: SensorKitECGProcessingLimits = .init()
    ) -> AnchoredFetcher<SRElectrocardiogramSample>.SampleCountBasedFetcher {
        .init(sensor: .ecg, batchSize: 1, anchor: anchor, device: .current, ecgProcessingLimits: limits, startFetch: { _, _ in })
    }
}
#endif
