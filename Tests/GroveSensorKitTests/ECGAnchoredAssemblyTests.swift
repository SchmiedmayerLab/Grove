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
    func sessionSplitAcrossTwoFetchesIsDeliveredOnceAndComplete() async throws {
        let start = Date.now.addingTimeInterval(-120)
        // Each conversion reads the current clock, so the native timestamps are converted once and reused.
        let native10 = SRAbsoluteTime(start.addingTimeInterval(10))
        let native11 = SRAbsoluteTime(start.addingTimeInterval(11))
        let native12 = SRAbsoluteTime(start.addingTimeInterval(12))
        let native13 = SRAbsoluteTime(start.addingTimeInterval(13))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let groups = ECGProcessingTests.groups()
        let early = Self.groups(identifier: "early-session")
        // The first fetch ends inside the session: the earlier session is delivered and the batch ends with it.
        let first = Self.fetcher(anchor: anchor, batchSize: 10)
        try first.startNativeFetchForTesting()
        #expect(first.processECGGroupsForTesting(early, timestamp: native10))
        #expect(first.processECGGroupsForTesting([groups[0]], timestamp: native11))
        #expect(first.processECGGroupsForTesting([groups[1]], timestamp: native12))
        let firstBatch = try #require(try await Self.completeAndFetch(first))
        #expect(firstBatch.samples == (try SensorKitECGSession.process(early)))
        try await firstBatch.acknowledge()
        #expect(try anchor.value.nativeTimestamp == native10.rawValue)
        // The next fetch reads the held session whole, now with its end state.
        let second = Self.fetcher(anchor: anchor, batchSize: 10)
        try second.startNativeFetchForTesting()
        #expect(second.processECGGroupsForTesting([groups[0]], timestamp: native11))
        #expect(second.processECGGroupsForTesting([groups[1]], timestamp: native12))
        #expect(second.processECGGroupsForTesting([groups[2]], timestamp: native13))
        let secondBatch = try #require(try await Self.completeAndFetch(second))
        #expect(secondBatch.samples == (try SensorKitECGSession.process(groups)))
        #expect(secondBatch.samples.map(\.sessionStates) == [[.begin, .active, .end]])
        try await secondBatch.acknowledge()
        #expect(try #require(anchor.value.nativeTimestamp) >= native13.rawValue)
    }

    @Test
    @available(iOS 18, *)
    func onlyUnfinishedSessionLeavesTheCursorWithoutFailing() async throws {
        let start = Date.now.addingTimeInterval(-120)
        // Each conversion reads the current clock, so the native timestamps are converted once and reused.
        let native10 = SRAbsoluteTime(start.addingTimeInterval(10))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let fetcher = Self.fetcher(anchor: anchor)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting([ECGProcessingTests.groups()[0]], timestamp: native10))
        #expect(try await Self.completeAndFetch(fetcher) == nil)
        #expect(try anchor.value.timestamp == start)
        #expect(try anchor.value.pendingBatch == nil)
    }

    @Test
    @available(iOS 18, *)
    func abandonedSessionWithoutVoltageIsSkippedOnceLaterDataFollows() async throws {
        let start = Date.now.addingTimeInterval(-120)
        // Each conversion reads the current clock, so the native timestamps are converted once and reused.
        let native10 = SRAbsoluteTime(start.addingTimeInterval(10))
        let native12 = SRAbsoluteTime(start.addingTimeInterval(12))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let abandoned = SensorKitECGSession.InputGroup(identifier: "abandoned-session", state: .begin, guidance: .guided, readings: [])
        let groups = ECGProcessingTests.groups()
        let fetcher = Self.fetcher(anchor: anchor, batchSize: 10)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting([abandoned], timestamp: native10))
        #expect(fetcher.processECGGroupsForTesting(groups, timestamp: native12))
        let batch = try #require(try await Self.completeAndFetch(fetcher))
        #expect(batch.samples == (try SensorKitECGSession.process(groups)))
        try await batch.acknowledge()
        #expect(try #require(anchor.value.nativeTimestamp) >= native12.rawValue)
        #expect(try anchor.value.pendingBatch == nil)
    }

    @Test
    @available(iOS 18, *)
    func abandonedSessionWithoutItsEndIsDeliveredOnceLaterDataFollows() async throws {
        let start = Date.now.addingTimeInterval(-120)
        // Each conversion reads the current clock, so the native timestamps are converted once and reused.
        let native10 = SRAbsoluteTime(start.addingTimeInterval(10))
        let native12 = SRAbsoluteTime(start.addingTimeInterval(12))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let withoutEnd = Array(ECGProcessingTests.groups().prefix(2))
        let later = Self.groups(identifier: "later-session", offset: 60)
        let fetcher = Self.fetcher(anchor: anchor, batchSize: 10)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting(withoutEnd, timestamp: native10))
        #expect(fetcher.processECGGroupsForTesting(later, timestamp: native12))
        let batch = try #require(try await Self.completeAndFetch(fetcher))
        // The abandoned session ends where the later one starts, so it precedes it in the batch.
        #expect(batch.samples == (SensorKitECGSession.processLeniently(withoutEnd) + (try SensorKitECGSession.process(later))))
        #expect(batch.samples.map(\.sessionStates) == [[.begin, .active], [.begin, .active, .end]])
        try await batch.acknowledge()
        #expect(try #require(anchor.value.nativeTimestamp) >= native12.rawValue)
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
        anchor: ManagedQueryAnchor, batchSize: Int = 1, limits: SensorKitECGProcessingLimits = .init()
    ) -> AnchoredFetcher<SRElectrocardiogramSample>.SampleCountBasedFetcher {
        .init(sensor: .ecg, batchSize: batchSize, anchor: anchor, device: .current, ecgProcessingLimits: limits, startFetch: { _, _ in })
    }

    /// Completes the native fetch on another thread, as SensorKit does, and returns the batch it flushes.
    @available(iOS 18, *)
    private static func completeAndFetch(
        _ fetcher: AnchoredFetcher<SRElectrocardiogramSample>.SampleCountBasedFetcher
    ) async throws -> SensorKit.AnchoredBatch<SensorKitECGSession>? {
        let completion = ECGBatchBoundaryTests.feed([], to: fetcher)
        let batch = try await fetcher.next(isolation: nil)
        await completion.value
        return batch
    }

    /// The groups of one complete session with another identifier, `offset` seconds after the shared fixture.
    @available(iOS 17.4, *)
    private static func groups(identifier: String, offset: TimeInterval = -60) -> [SensorKitECGSession.InputGroup] {
        ECGProcessingTests.groups().map { group in
            SensorKitECGSession.InputGroup(
                identifier: identifier,
                state: group.state,
                guidance: group.guidance,
                readings: group.readings.map { .init(date: $0.date.addingTimeInterval(offset), frequency: $0.frequency, lead: $0.lead, samples: $0.samples) }
            )
        }
    }
}
#endif
