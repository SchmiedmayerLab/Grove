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


/// Batches that end where the ECG limits are reached, and that each is the batch a fetch from its cursor delivers.
@Suite(.timeLimit(.minutes(1)))
struct ECGBatchReplayTests {
    private typealias Fixture = ECGBatchBoundaryTests
    private typealias NativeStream = ECGBatchBoundaryTests.NativeStream

    @Test
    @available(iOS 18, *)
    func resultsAfterTheBoundaryAreProcessedAsAFetchFromItProcessesThem() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let first = NativeStream.session("first-session", offset: -60)
        let second = NativeStream.session("second-session")
        let later = NativeStream.session("later-session", offset: 60)
        // A complete session takes four entries. The batch ends after the first session once the second one exceeds
        // the limit. A fetch from that boundary doesn't know the first session; its late fragment has no begin state,
        // so it is skipped and doesn't end the second session, in the continuing fetch as in a fetch from the boundary.
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 7, maximumSessions: 128)
        let results = [
            stream.result(first, at: 10), stream.result([second[0]], at: 11), stream.result([first[1]], at: 12),
            stream.result([second[1]], at: 13), stream.result([second[2]], at: 14), stream.result(later, at: 15)
        ]
        let batches = try await Fixture.fetch(results, anchor: anchor, batchSize: 100, limits: limits)
        #expect(batches.map(\.samples) == (try [first, second, later].map(SensorKitECGSession.process)))
        #expect(try anchor.value.nativeTimestamp == stream.time(15).rawValue)
        for batch in batches {
            try await Fixture.expectReplay(of: batch, over: results, limits: limits)
        }
    }

    @Test
    @available(iOS 18, *)
    func lateFragmentAfterASessionLimitCutCountsAsItDoesInAFetchFromTheBoundary() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let sessions = (0..<4).map { NativeStream.session("session-\($0)", offset: Double($0)) }
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 1_000_000, maximumSessions: 2)
        // The late fragment of the second session follows the boundary; without its begin state it is skipped, so the
        // next batch doesn't count it as a session.
        let results = [
            stream.result(sessions[0], at: 10), stream.result(sessions[1], at: 11), stream.result([sessions[1][1]], at: 12),
            stream.result(sessions[2], at: 13), stream.result(sessions[3], at: 14)
        ]
        let batches = try await Fixture.fetch(results, anchor: anchor, batchSize: 100, limits: limits)
        #expect(batches.map(\.samples.count) == [2, 2])
        #expect(batches.flatMap(\.samples) == (try sessions.flatMap(SensorKitECGSession.process)))
        for batch in batches {
            try await Fixture.expectReplay(of: batch, over: results, limits: limits)
        }
    }

    @Test
    @available(iOS 18, *)
    func batchEndsBeforeAResultThatCompletesOneSessionAndStartsAnother() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let sessions = (0..<3).map { NativeStream.session("session-\($0)", offset: Double($0)) }
        let active = sessions[2][1]
        let fragments = active.readings.map {
            SensorKitECGSession.InputGroup(identifier: active.identifier, state: .active, guidance: active.guidance, readings: [$0])
        }
        // One result completes the second session and starts the third, so no batch can end between them. When the
        // third session exceeds the limit, the batch ends before that result and the next batch holds both sessions.
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 9, maximumSessions: 128)
        let results = [
            stream.result(sessions[0], at: 10), stream.result(sessions[1] + [sessions[2][0]], at: 11), stream.result([fragments[0]], at: 12),
            stream.result([fragments[1]], at: 13), stream.result([sessions[2][2]], at: 14)
        ]
        let batches = try await Fixture.fetch(results, anchor: anchor, batchSize: 100, limits: limits)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(sessions[0]), try SensorKitECGSession.process(sessions[1] + sessions[2])])
        #expect(try anchor.value.nativeTimestamp == stream.time(14).rawValue)
        for batch in batches {
            try await Fixture.expectReplay(of: batch, over: results, limits: limits)
        }
    }

    @Test
    @available(iOS 18, *)
    func batchCutAtTheLimitsBeforeAHeldSessionIsDeliveredAgain() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let sessions = (0..<3).map { NativeStream.session("session-\($0)", offset: Double($0)) }
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 1_000_000, maximumSessions: 2)
        let ended = [
            stream.result(sessions[0], at: 10), stream.result(sessions[1], at: 11), stream.result([sessions[2][0]], at: 12),
            stream.result([sessions[2][1]], at: 13)
        ]
        // The third session reaches the session limit, which ends the batch, and is still unfinished when the fetch ends.
        let first = try await Fixture.firstBatch(of: ended, anchor: anchor, batchSize: 100, limits: limits)
        #expect(first.samples == (try sessions.prefix(2).flatMap(SensorKitECGSession.process)))
        let grown = ended + [stream.result([sessions[2][2]], at: 14)]
        let batches = try await Fixture.fetch(grown, anchor: anchor, batchSize: 100, limits: limits)
        #expect(batches.map(\.samples.count) == [2, 1])
        #expect(batches[0].info.replayToken == first.info.replayToken)
        #expect(batches.flatMap(\.samples) == (try sessions.flatMap(SensorKitECGSession.process)))
        try await Fixture.expectReplay(of: first, over: grown, limits: limits)
    }

    @Test
    @available(iOS 18, *)
    func fullBatchWaitsForAResultAfterItsBoundaryTimestamp() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let complete = NativeStream.session("complete-session", offset: -60)
        let held = NativeStream.session("held-session")
        // The complete session fills the batch, but the held session starts at the same timestamp, so a fetch from that
        // boundary would not read its begin state again: the batch waits, and the fetch ends without one.
        let started = [stream.result(complete, at: 10), stream.result([held[0]], at: 10), stream.result([held[1]], at: 11)]
        #expect(try await Fixture.fetch(started, anchor: anchor, batchSize: 1).isEmpty)
        #expect(try anchor.value.batchSequence == 0)
        #expect(try anchor.value.pendingBatch == nil)
        let grown = started + [stream.result([held[2]], at: 12)]
        let batches = try await Fixture.fetch(grown, anchor: anchor, batchSize: 1)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(complete + held)])
        #expect(try anchor.value.nativeTimestamp == stream.time(12).rawValue)
        try await Fixture.expectReplay(of: batches[0], over: grown)
    }

    @Test
    @available(iOS 18, *)
    func filledBatchEndsAtTheLastBoundaryBeforeASessionAtItsTimestamp() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let sessions = (0..<2).map { NativeStream.session("session-\($0)", offset: Double($0) - 60) }
        let held = NativeStream.session("held-session")
        // The two complete sessions fill the batch, but the held session starts at the second one's timestamp. The
        // batch ends at the first session's boundary, which the second session's later timestamp confirmed.
        let started = [
            stream.result(sessions[0], at: 9), stream.result(sessions[1], at: 10), stream.result([held[0]], at: 10),
            stream.result([held[1]], at: 11)
        ]
        let first = try await Fixture.fetch(started, anchor: anchor, batchSize: 2)
        #expect(first.map(\.samples) == [try SensorKitECGSession.process(sessions[0])])
        #expect(try anchor.value.nativeTimestamp == stream.time(9).rawValue)
        let grown = started + [stream.result([held[2]], at: 12)]
        let next = try await Fixture.fetch(Array(grown.dropFirst()), anchor: anchor, batchSize: 2)
        #expect(next.map(\.samples) == [try SensorKitECGSession.process(sessions[1] + held)])
        try await Fixture.expectReplay(of: first[0], over: grown)
        try await Fixture.expectReplay(of: next[0], over: grown)
    }

    @Test
    @available(iOS 18, *)
    func sessionAtTheCandidateTimestampKeepsTheConfirmedBatchEnd() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let sessions = (0..<2).map { NativeStream.session("session-\($0)", offset: Double($0) - 60) }
        let third = NativeStream.session("third-session")
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 1_000_000, maximumSessions: 2)
        // The third session starts at the second one's timestamp and exceeds the session limit. The batch can't end
        // after the second session, but it can end after the first one, so the fetch splits there.
        let results = [
            stream.result(sessions[0], at: 9), stream.result(sessions[1], at: 10), stream.result([third[0]], at: 10),
            stream.result([third[1]], at: 11), stream.result([third[2]], at: 12)
        ]
        let batches = try await Fixture.fetch(results, anchor: anchor, batchSize: 10, limits: limits)
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(sessions[0]), try SensorKitECGSession.process(sessions[1] + third)])
        #expect(try anchor.value.nativeTimestamp == stream.time(12).rawValue)
        for batch in batches {
            try await Fixture.expectReplay(of: batch, over: results, limits: limits)
        }
    }

    @Test
    @available(iOS 18, *)
    func batchEndThatALaterResultConfirmedIsDeliveredBeforeItGrows() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let complete = NativeStream.session("complete-session", offset: -60)
        let unusable = NativeStream.session("unusable-session", offset: -30).map { group in
            SensorKitECGSession.InputGroup(
                identifier: group.identifier,
                state: group.state,
                guidance: group.guidance,
                readings: group.readings.map { .init(date: $0.date, frequency: $0.frequency, lead: $0.lead, samples: []) }
            )
        }
        let held = NativeStream.session("held-session")
        // The second result ends the unusable session without a sample, which removes the block on the batch end
        // after the complete session, and starts the held session. That batch end is then already confirmed, so a
        // replay with its sample count delivers it before the held session can join it.
        let results = [
            stream.result(complete + [unusable[0]], at: 1),
            stream.result(Array(unusable.dropFirst()) + Array(held.prefix(2)), at: 2)
        ]
        let first = try await Fixture.firstBatch(of: results, anchor: anchor, batchSize: 100)
        #expect(first.samples == (try SensorKitECGSession.process(complete)))
        let grown = results + [stream.result([NativeStream.session("later-session", offset: 60)[0]], at: 3)]
        try await Fixture.expectReplay(of: first, over: results)
        try await Fixture.expectReplay(of: first, over: grown)
    }

    @Test
    @available(iOS 18, *)
    func sessionSkippedBeforeADeliveryIsLoggedOnce() async throws {
        let stream = NativeStream()
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let unusable = NativeStream.session("unusable-session", offset: -30).map { group in
            SensorKitECGSession.InputGroup(
                identifier: group.identifier,
                state: group.state,
                guidance: group.guidance,
                readings: group.readings.map { .init(date: $0.date, frequency: $0.frequency, lead: $0.lead, samples: []) }
            )
        }
        // The second result skips the unusable session and confirms the batch end before it, so the batch is delivered
        // and the fetch processes that result again, where it skips the session's fragments a second time.
        let results = [
            stream.result(NativeStream.session("complete-session", offset: -60) + [unusable[0]], at: 1),
            stream.result(Array(unusable.dropFirst()) + Array(NativeStream.session("held-session").prefix(2)), at: 2)
        ]
        let fetcher = Fixture.fetcher(anchor: anchor, batchSize: 1)
        try fetcher.startNativeFetchForTesting()
        let feed = Fixture.feed(results, to: fetcher)
        while let batch = try await fetcher.next(isolation: nil) {
            try await batch.acknowledge()
        }
        await feed.value
        #expect(fetcher.loggedSkippedECGSessionCountForTesting() == 1)
    }

    @Test
    @available(iOS 18, *)
    func resultWithoutSessionDataDoesNotMoveAFinishedSessionsBoundary() async throws {
        // The results are older than the hold cutoff, so the end of a fetch finishes an unfinished session.
        let stream = NativeStream(start: Date.now.addingTimeInterval(-26 * 3600))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let unfinished = Array(NativeStream.session("unfinished-session").prefix(2))
        let first = try await Fixture.firstBatch(of: [stream.result(unfinished, at: 1)], anchor: anchor, batchSize: 1)
        #expect(first.samples == SensorKitECGSession.processLeniently(unfinished))
        // Newer results hold a fragment of a session without its begin state, which the fetch skips, and then another
        // session, which ends the unfinished one at the same boundary the end of the fetch did.
        let orphan = NativeStream.session("orphan-session", offset: 30)[1]
        let grown = [
            stream.result(unfinished, at: 1), stream.result([orphan], at: 2), stream.result(NativeStream.session("later-session", offset: 60), at: 3)
        ]
        try await Fixture.expectReplay(of: first, over: grown)
    }

    @Test
    @available(iOS 18, *)
    func resultWithoutSessionDataNamesNoPeripheral() async throws {
        let stream = NativeStream(start: Date.now.addingTimeInterval(-26 * 3600))
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let peripherals = ["unfinished", "orphan", "complete"].map { SensorKit.SourceDeviceInfo(localIdentifier: $0) }
        let unfinished = Array(NativeStream.session("unfinished-session").prefix(2))
        let orphan = NativeStream.session("orphan-session", offset: 30)[1]
        let complete = NativeStream.session("complete-session", offset: 60)
        let results = [(unfinished, 1), ([orphan], 2), (complete, 3)].enumerated().map { index, entry in
            (result: stream.result(entry.0, at: entry.1), peripheral: peripherals[index])
        }
        // The fragment adds no data, so its peripheral belongs to no batch, whether the fetch reads it before the
        // unfinished session's boundary or after it.
        let fetcher = Fixture.fetcher(anchor: anchor, batchSize: 1)
        try fetcher.startNativeFetchForTesting()
        let feed = Self.feed(results, to: fetcher)
        let first = try #require(try await fetcher.next(isolation: nil))
        #expect(first.info.sourceDevices == [peripherals[0]])
        try await first.acknowledge()
        let second = try #require(try await fetcher.next(isolation: nil))
        #expect(second.info.sourceDevices == [peripherals[2]])
        fetcher.stopForTesting()
        await feed.value
        let restarted = Fixture.fetcher(anchor: anchor, batchSize: 1)
        try restarted.startNativeFetchForTesting()
        let restartFeed = Self.feed(Array(results.dropFirst()), to: restarted)
        let again = try #require(try await restarted.next(isolation: nil))
        restarted.stopForTesting()
        await restartFeed.value
        #expect(again.samples == second.samples)
        #expect(again.info.sourceDevices == [peripherals[2]])
        #expect(again.info.sourceDevicesSuppliedEverySample)
    }
}


extension ECGBatchReplayTests {
    /// Delivers ECG results with their peripherals and then the fetch completion on a thread of its own.
    @available(iOS 18, *)
    fileprivate static func feed(
        _ results: [(result: ECGBatchBoundaryTests.NativeResult, peripheral: SensorKit.SourceDeviceInfo)], to fetcher: ECGBatchBoundaryTests.Fetcher
    ) -> Task<Void, Never> {
        nonisolated(unsafe) let reader = fetcher
        nonisolated(unsafe) let input = results
        let (finished, continuation) = AsyncStream<Void>.makeStream()
        Thread.detachNewThread {
            defer {
                continuation.finish()
            }
            for entry in input
            where !reader.processECGGroupsForTesting(entry.result.groups, timestamp: entry.result.timestamp, sourceDevice: entry.peripheral) {
                return
            }
            reader.completeFetchForTesting()
        }
        return Task {
            for await _ in finished {}
        }
    }
}
#endif
