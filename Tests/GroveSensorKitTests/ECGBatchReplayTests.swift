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
@Suite
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
        // the limit. A fetch from that boundary doesn't know the first session, so it reads the first session's late
        // fragment as another session, which ends the second one; the continuing fetch must do the same.
        let limits = try SensorKitECGProcessingLimits(maximumEntries: 8, maximumSessions: 128)
        let results = [
            stream.result(first, at: 10), stream.result(Array(second.prefix(2)), at: 11), stream.result([first[1]], at: 12),
            stream.result([second[1]], at: 13), stream.result([second[2]], at: 14), stream.result(later, at: 15)
        ]
        let batches = try await Fixture.fetch(results, anchor: anchor, batchSize: 100, limits: limits)
        let interrupted = SensorKitECGSession.processLeniently(Array(second.prefix(2)))
        #expect(batches.map(\.samples) == [try SensorKitECGSession.process(first), interrupted + (try SensorKitECGSession.process(later))])
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
        // The late fragment of the second session follows the boundary, so the next batch counts it as a session.
        let results = [
            stream.result(sessions[0], at: 10), stream.result(sessions[1], at: 11), stream.result([sessions[1][1]], at: 12),
            stream.result(sessions[2], at: 13), stream.result(sessions[3], at: 14)
        ]
        let batches = try await Fixture.fetch(results, anchor: anchor, batchSize: 100, limits: limits)
        #expect(batches.map(\.samples.count) == [2, 1, 1])
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
}
#endif
