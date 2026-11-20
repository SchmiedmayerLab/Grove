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


/// Where ECG batches end, and that a batch fetched again from its pending anchor is the batch first delivered.
@Suite(.timeLimit(.minutes(1)))
struct ECGBatchBoundaryTests {
    @Test
    @available(iOS 18, *)
    func unacknowledgedBatchBeforeAHeldSessionIsDeliveredAgain() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let early = NativeStream.session("early-session", offset: -60)
        let held = NativeStream.session("held-session")
        let later = NativeStream.session("later-session", offset: 60)
        // The fetch ends inside the second session, so the batch ends before it.
        let ended = [stream.result(early, at: 10), stream.result([held[0]], at: 11), stream.result([held[1]], at: 12)]
        let first = try await Self.firstBatch(of: ended, anchor: anchor, batchSize: 10)
        #expect(first.samples == (try SensorKitECGSession.process(early)))
        let pending = try #require(anchor.value.pendingBatch)
        #expect(pending.sampleCount == 1)
        #expect(pending.nativeUpperBoundBits == stream.time(10).rawValue.bitPattern)
        // The process ends before the acknowledgement. By the next fetch SensorKit returns the rest and newer data.
        let grown = ended + [stream.result([held[2]], at: 13), stream.result(later, at: 14)]
        // The restart delivers the pending batch with its sample count, then the rest with the configured batch size.
        let batches = try await Self.fetch(grown, anchor: anchor, batchSize: 10)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(early), try [held, later].flatMap(SensorKitECGSession.process)])
        #expect(batches[0].info.replayToken == first.info.replayToken)
        #expect(batches[0].info.acquisitionBatch == first.info.acquisitionBatch)
        #expect(try anchor.value.nativeTimestamp == stream.time(14).rawValue)
        #expect(try anchor.value.pendingBatch == nil)
        try await Self.expectReplay(of: first, over: grown)
    }

    @Test
    @available(iOS 18, *)
    func unfinishedSessionEndsWhereAnotherSessionStartsAndBlocksNoBatch() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let unfinished = Array(NativeStream.session("unfinished-session", offset: -60).prefix(2))
        let sessions = (0..<3).map { NativeStream.session("session-\($0)", offset: Double($0)) }
        let results = [stream.result(unfinished, at: 10)] + sessions.enumerated().map { stream.result($1, at: 11 + $0) }
        // One native fetch delivers four batches of one session each.
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 1)
        let expected = [SensorKitECGSession.processLeniently(unfinished)] + (try sessions.map(SensorKitECGSession.process))
        #expect(batches.map(\.samples) == expected)
        #expect(batches[0].samples.map(\.sessionStates) == [[.begin, .active]])
        // The unfinished session ends before the result that starts the next one, so its batch ends there too.
        let boundaries = try batches.map { try #require($0.info.replayToken.anchor.pendingBatch?.nativeUpperBoundBits) }
        #expect(boundaries == (10...13).map { stream.time($0).rawValue.bitPattern })
        #expect(Set(batches.map(\.info.acquisitionBatch)).count == 4)
        for batch in batches {
            try await Self.expectReplay(of: batch, over: results)
        }
    }

    @Test
    @available(iOS 18, *)
    func lateFragmentOfADeliveredSessionIsSkippedInTheNextBatch() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let first = NativeStream.session("first-session", offset: -60)
        let second = NativeStream.session("second-session")
        let results = [
            stream.result(first, at: 10), stream.result([first[1]], at: 11), stream.result(second, at: 12), stream.result([second[1]], at: 13)
        ]
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 1)
        #expect(batches.map(\.samples) == (try [first, second].map(SensorKitECGSession.process)))
        // A result that adds no sample stays after the boundary, so the next fetch reads it again.
        #expect(try anchor.value.nativeTimestamp == stream.time(12).rawValue)
        #expect(try await Self.fetch([results[3]], anchor: anchor, batchSize: 1).isEmpty)
        #expect(try anchor.value.nativeTimestamp == stream.time(12).rawValue)
        for batch in batches {
            try await Self.expectReplay(of: batch, over: results)
        }
    }

    @Test
    @available(iOS 18, *)
    func sessionThatStartsAtTheBoundaryTimestampWithholdsTheBatch() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let complete = NativeStream.session("complete-session", offset: -60)
        let held = NativeStream.session("held-session")
        // The held session starts at the timestamp of the result that completed the other one, in a result of its own
        // or in the same one. No boundary lies between them, so neither is delivered until the held one ends.
        for sameResult in [false, true] {
            let start = sameResult
                ? [stream.result(complete + [held[0]], at: 10)]
                : [stream.result(complete, at: 10), stream.result([held[0]], at: 10)]
            #expect(try await Self.fetch(start + [stream.result([held[1]], at: 11)], anchor: anchor, batchSize: 10).isEmpty)
            #expect(try anchor.value.batchSequence == 0)
            #expect(try anchor.value.pendingBatch == nil)
        }
        let grown = [
            stream.result(complete, at: 10), stream.result([held[0]], at: 10), stream.result([held[1]], at: 11), stream.result([held[2]], at: 12)
        ]
        let batches = try await Self.fetch(grown, anchor: anchor, batchSize: 10)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(complete + held)])
        #expect(try anchor.value.nativeTimestamp == stream.time(12).rawValue)
        try await Self.expectReplay(of: batches[0], over: grown + [stream.result(NativeStream.session("later-session", offset: 60), at: 13)])
    }

    @Test
    @available(iOS 18, *)
    func resultAtTheBoundaryTimestampJoinsTheBatch() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let unfinished = Array(NativeStream.session("unfinished-session", offset: -60).prefix(2))
        let complete = NativeStream.session("complete-session")
        // The session that ends the unfinished one arrives at the same timestamp, so no batch can end between them,
        // even though the unfinished session alone fills a batch.
        let results = [stream.result(unfinished, at: 10), stream.result(complete, at: 10)]
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 1)
        #expect(batches.map(\.samples) == [SensorKitECGSession.processLeniently(unfinished) + (try SensorKitECGSession.process(complete))])
        #expect(try anchor.value.nativeTimestamp == stream.time(10).rawValue)
        try await Self.expectReplay(of: batches[0], over: results)
    }

    @Test(arguments: [false, true])
    @available(iOS 18, *)
    func resultBeyondTheLimitsWithoutABatchEndFailsTheFetch(sameResult: Bool) async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let complete = NativeStream.session("complete-session", offset: -60)
        let held = NativeStream.session("held-session")
        // The held session starts at the timestamp of the complete one, in a result of its own or in the same one, so
        // no batch can end between them. Its end state exceeds the limits, and without a batch end the fetch can't make
        // room: it fails and keeps the cursor. Limits that fit both sessions deliver them in one batch.
        let start = sameResult
            ? [stream.result(complete + [held[0]], at: 10)]
            : [stream.result(complete, at: 10), stream.result([held[0]], at: 10)]
        let results = start + [stream.result([held[1]], at: 11), stream.result([held[2]], at: 12)]
        let tight = try SensorKitECGProcessingLimits(maximumEntries: 7, maximumSessions: 128)
        await #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) {
            try await Self.fetch(results, anchor: anchor, batchSize: 10, limits: tight)
        }
        #expect(try anchor.value.batchSequence == 0)
        #expect(try anchor.value.pendingBatch == nil)
        let fitting = try SensorKitECGProcessingLimits(maximumEntries: 8, maximumSessions: 128)
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 10, limits: fitting)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(complete + held)])
    }

    @Test
    @available(iOS 18, *)
    func overlappingSessionsAreEachDeliveredOnce() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let interrupted = NativeStream.session("interrupted-session", offset: -60)
        let other = NativeStream.session("other-session")
        let later = NativeStream.session("later-session", offset: 60)
        // Another session's data arrives before the first session's end state, which ends the first session there.
        let unfinished = Array(interrupted.prefix(2))
        let results = [stream.result(unfinished, at: 10), stream.result(other, at: 11), stream.result([interrupted[2]], at: 12)]
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 10)
        #expect(batches.map(\.samples) == [SensorKitECGSession.processLeniently(unfinished) + (try SensorKitECGSession.process(other))])
        #expect(try anchor.value.nativeTimestamp == stream.time(11).rawValue)
        // The next fetch reads the late end state again and skips it; it delivers neither session a second time.
        let grown = results + [stream.result(later, at: 13)]
        let next = try await Self.fetch(Array(grown.dropFirst(2)), anchor: anchor, batchSize: 10)
        #expect(next.map(\.samples) == [try SensorKitECGSession.process(later)])
        try await Self.expectReplay(of: batches[0], over: grown)
        try await Self.expectReplay(of: next[0], over: grown)
    }

    @Test(arguments: [false, true])
    @available(iOS 18, *)
    func backlogAboveTheLimitsIsDeliveredInBatches(limitingEntries: Bool) async throws {
        let limits = try SensorKitECGProcessingLimits(maximumEntries: limitingEntries ? 8 : 1_000_000, maximumSessions: limitingEntries ? 128 : 2)
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        // Each session takes four entries, so either limit admits two sessions in one batch.
        let sessions = (0..<5).map { NativeStream.session("session-\($0)", offset: Double($0)) }
        let results = sessions.enumerated().map { stream.result($1, at: 10 + $0) }
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 100_000, limits: limits)
        #expect(batches.map(\.samples.count) == [2, 2, 1])
        #expect(batches.flatMap(\.samples) == (try sessions.flatMap(SensorKitECGSession.process)))
        #expect(try anchor.value.nativeTimestamp == stream.time(14).rawValue)
        for batch in batches {
            try await Self.expectReplay(of: batch, over: results, limits: limits)
        }
    }

    @Test
    @available(iOS 18, *)
    func skippedSessionsAloneNeverExceedTheSessionLimit() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let abandoned = (0..<5).map { index in
            stream.result([.init(identifier: "abandoned-\(index)", state: .begin, guidance: .guided, readings: [])], at: 10 + index)
        }
        let complete = NativeStream.session("complete-session")
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 1_000_000, maximumSessions: 2)
        let batches = try await Self.fetch(abandoned + [stream.result(complete, at: 15)], anchor: anchor, batchSize: 10, limits: limits)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(complete)])
        #expect(try anchor.value.nativeTimestamp == stream.time(15).rawValue)
    }

    @Test
    @available(iOS 18, *)
    func unfinishedSessionOlderThanTheHoldIntervalIsDeliveredWithoutItsEnd() async throws {
        // The ECG sensor's data is quarantined for 24 hours, and an unfinished session is held for one more hour.
        let stream = NativeStream(start: Date.now.addingTimeInterval(-26 * 60 * 60))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let unfinished = Array(NativeStream.session("unfinished-session").prefix(2))
        let ended = [stream.result(unfinished, at: 10)]
        let batches = try await Self.fetch(ended, anchor: anchor, batchSize: 10)
        #expect(batches.map(\.samples) == [SensorKitECGSession.processLeniently(unfinished)])
        #expect(try anchor.value.nativeTimestamp == stream.time(10).rawValue)
        // Fetched again with newer data, the session ends where the next one starts: the same batch.
        try await Self.expectReplay(of: batches[0], over: ended + [stream.result(NativeStream.session("later-session", offset: 60), at: 20)])
    }

    @Test
    @available(iOS 18, *)
    func batchStatesOnlyThePeripheralsOfTheResultsBeforeItsBoundary() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let peripherals = ["peripheral-1", "peripheral-2"].map { SensorKit.SourceDeviceInfo(localIdentifier: $0) }
        let complete = NativeStream.session("complete-session", offset: -60)
        let held = NativeStream.session("held-session")
        let fetcher = Self.fetcher(anchor: anchor, batchSize: 10)
        try fetcher.startNativeFetchForTesting()
        #expect(fetcher.processECGGroupsForTesting(complete, timestamp: stream.time(10), sourceDevice: peripherals[0]))
        #expect(fetcher.processECGGroupsForTesting([held[0]], timestamp: stream.time(11), sourceDevice: peripherals[1]))
        let feed = Self.feed([], to: fetcher)
        let batch = try #require(try await fetcher.next(isolation: nil))
        await feed.value
        #expect(batch.info.sourceDevices == [peripherals[0]])
        #expect(batch.info.sourceDevicesSuppliedEverySample)
    }

    @Test
    @available(iOS 18, *)
    func boundaryDateBeforeTheCursorDateStillDeliversTheBatch() async throws {
        let stream = NativeStream()
        // The cursor's date was projected before a backward wall-clock correction, so it lies after the new boundary's date.
        let cursor = QueryAnchor(timestamp: stream.start.addingTimeInterval(3600), nativeTimestampBits: stream.time(0).rawValue.bitPattern)
        let anchor = ManagedQueryAnchor.ephemeral(anchor: cursor)
        let complete = NativeStream.session("complete-session")
        let results = [stream.result(complete, at: 10)]
        let first = try await Self.firstBatch(of: results, anchor: anchor, batchSize: 10)
        let pending = try #require(anchor.value.pendingBatch)
        #expect(pending.upperBound < cursor.timestamp)
        // The batch stays deliverable after a restart, and can be acknowledged.
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 10)
        #expect(batches.map(\.info.replayToken) == [first.info.replayToken])
        #expect(try anchor.value.nativeTimestamp == stream.time(10).rawValue)
    }

    @Test
    @available(iOS 18, *)
    func restartOnAPendingBatchKeepsTheConfiguredBatchSizeAfterIt() async throws {
        let stream = NativeStream()
        let results = (1...6).map { stream.result(NativeStream.session("session-\($0)", offset: Double($0) * 10), at: $0) }
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        // A batch of one session is delivered and not acknowledged, so the anchor keeps it pending.
        let pending = try await Self.firstBatch(of: results, anchor: anchor, batchSize: 1)
        #expect(pending.samples.count == 1)
        // The restart delivers the pending batch with its sample count, and the batches after it with the configured
        // batch size.
        let batches = try await Self.fetch(results, anchor: anchor, batchSize: 3)
        #expect(batches.map(\.samples.count) == [1, 3, 2])
        #expect(batches.first?.info.replayToken == pending.info.replayToken)
    }
}


extension ECGBatchBoundaryTests {
    typealias Fetcher = AnchoredFetcher<SRElectrocardiogramSample>.SampleCountBasedFetcher
    typealias Batch = SensorKit.AnchoredBatch<SensorKitECGSession>

    struct NativeResult: Sendable {
        let groups: [SensorKitECGSession.InputGroup]
        let timestamp: SRAbsoluteTime
    }

    /// The native results of one device, at timestamps a fixed number of seconds after a start.
    struct NativeStream {
        let start: Date
        /// Each conversion of a date reads the current clock, so the origin is converted once.
        private let origin: SRAbsoluteTime

        init(start: Date = Date.now.addingTimeInterval(-120)) {
            self.start = start
            self.origin = SRAbsoluteTime(start)
        }

        /// The groups of one complete session, `offset` seconds after the shared fixture.
        static func session(_ identifier: String, offset: TimeInterval = 0) -> [SensorKitECGSession.InputGroup] {
            ECGProcessingTests.groups().map { group in
                SensorKitECGSession.InputGroup(
                    identifier: identifier,
                    state: group.state,
                    guidance: group.guidance,
                    readings: group.readings.map {
                        .init(date: $0.date.addingTimeInterval(offset), frequency: $0.frequency, lead: $0.lead, samples: $0.samples)
                    }
                )
            }
        }

        func time(_ seconds: Int) -> SRAbsoluteTime {
            SRAbsoluteTime(rawValue: origin.rawValue + Double(seconds))
        }

        func result(_ groups: [SensorKitECGSession.InputGroup], at seconds: Int) -> NativeResult {
            NativeResult(groups: groups, timestamp: time(seconds))
        }
    }

    @available(iOS 18, *)
    static func fetcher(anchor: ManagedQueryAnchor, batchSize: Int, limits: SensorKitECGProcessingLimits = .init()) -> Fetcher {
        .init(sensor: .ecg, batchSize: batchSize, anchor: anchor, device: .current, ecgProcessingLimits: limits, startFetch: { _, _ in })
    }

    /// Delivers native results and then the fetch completion on a thread of its own, as SensorKit does. A full batch
    /// parks that thread until the consumer asks for it, so it must not be one of the threads the consumers run on.
    @available(iOS 18, *)
    static func feed(_ results: [NativeResult], to fetcher: Fetcher) -> Task<Void, Never> {
        nonisolated(unsafe) let reader = fetcher
        let (finished, continuation) = AsyncStream<Void>.makeStream()
        Thread.detachNewThread {
            defer {
                continuation.finish()
            }
            for result in results where !reader.processECGGroupsForTesting(result.groups, timestamp: result.timestamp) {
                return
            }
            reader.completeFetchForTesting()
        }
        return Task {
            for await _ in finished {}
        }
    }

    /// Runs one native fetch over the results SensorKit returns after the cursor and acknowledges every batch.
    @available(iOS 18, *)
    static func fetch(
        _ results: [NativeResult], anchor: ManagedQueryAnchor, batchSize: Int, limits: SensorKitECGProcessingLimits = .init()
    ) async throws -> [Batch] {
        let fetcher = Self.fetcher(anchor: anchor, batchSize: batchSize, limits: limits)
        try fetcher.startNativeFetchForTesting()
        let feed = Self.feed(results, to: fetcher)
        var batches: [Batch] = []
        while let batch = try await fetcher.next(isolation: nil) {
            batches.append(batch)
            try await batch.acknowledge()
        }
        await feed.value
        return batches
    }

    /// Runs a native fetch up to its first batch and abandons it there, without an acknowledgement.
    @available(iOS 18, *)
    static func firstBatch(
        of results: [NativeResult], anchor: ManagedQueryAnchor, batchSize: Int, limits: SensorKitECGProcessingLimits = .init()
    ) async throws -> Batch {
        let fetcher = Self.fetcher(anchor: anchor, batchSize: batchSize, limits: limits)
        try fetcher.startNativeFetchForTesting()
        let feed = Self.feed(results, to: fetcher)
        let batch = try #require(try await fetcher.next(isolation: nil))
        fetcher.stopForTesting()
        await feed.value
        return batch
    }

    /// Fetches a batch again as `SensorKit.replay(_:from:ecgProcessingLimits:)` does: from a copy of its pending
    /// anchor, with its sample count as the batch size, over the results SensorKit returns after that anchor.
    @available(iOS 18, *)
    static func expectReplay(
        of batch: Batch, over results: [NativeResult], limits: SensorKitECGProcessingLimits = .init()
    ) async throws {
        let pendingAnchor = batch.info.replayToken.anchor
        let cursor = try #require(pendingAnchor.nativeTimestamp)
        let replayed = try await firstBatch(
            of: results.filter { $0.timestamp.rawValue > cursor },
            anchor: .ephemeral(anchor: pendingAnchor),
            batchSize: try #require(pendingAnchor.pendingBatch).sampleCount,
            limits: limits
        )
        #expect(replayed.samples == batch.samples)
        #expect(replayed.info.replayToken == batch.info.replayToken)
        #expect(replayed.info.acquisitionBatch == batch.info.acquisitionBatch)
    }
}
#endif
