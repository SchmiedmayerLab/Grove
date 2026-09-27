//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLMOpenAIRealtime
import Testing


@Suite("Realtime Transcript Waits")
struct LLMOpenAIRealtimeTranscriptTests {
    @Test("Cancelling a transcript wait returns without a transcript", arguments: [false, true])
    func cancellationReturns(cancelBeforeRegistration: Bool) async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        // The normal grace period must not rescue broken cancellation before the watchdog fails the test.
        let waiter = Task { await tracker.waitUntilSettled(timeout: .seconds(3600)) }
        if !cancelBeforeRegistration {
            await tracker.waitForWaiters(1)
        }
        let watchdog = startWatchdog(for: tracker)
        defer { watchdog.cancel() }
        waiter.cancel()
        await waiter.value
        #expect(await tracker.waiterCount == 0)
    }

    @Test("A zero grace period cannot beat continuation registration")
    func immediateTimeout() async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        let watchdog = startWatchdog(for: tracker)
        defer { watchdog.cancel() }
        for _ in 0..<100 {
            await tracker.waitUntilSettled(timeout: .zero)
        }
        #expect(await tracker.waiterCount == 0)
    }

    @Test("Cancelling one waiter keeps the other registered")
    func cancellationOnlyReleasesCaller() async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        let first = Task { await tracker.waitUntilSettled(timeout: .seconds(5)) }
        await tracker.waitForWaiters(1)
        let second = Task { await tracker.waitUntilSettled(timeout: .seconds(5)) }
        await tracker.waitForWaiters(2)
        first.cancel()
        await first.value
        #expect(await tracker.waiterCount == 1)
        await tracker.complete("item-1")
        await second.value
        #expect(await tracker.waiterCount == 0)
    }

    @Test("A later committed event cannot reopen a completed transcript")
    func completedTurnStaysSettled() async {
        let tracker = UserTranscriptTracker()
        await tracker.complete("item-1")
        await tracker.expect("item-1")
        let watchdog = startWatchdog(for: tracker)
        defer { watchdog.cancel() }
        await tracker.waitUntilSettled(timeout: .seconds(3600))
        #expect(await tracker.waiterCount == 0)
    }

    @Test("Resetting releases pending transcripts and forgets the previous session")
    func resetPendingTranscripts() async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        let waiter = Task { await tracker.waitUntilSettled(timeout: .seconds(5)) }
        await tracker.waitForWaiters(1)
        await tracker.reset()
        await waiter.value
        #expect(await tracker.waiterCount == 0)
        await tracker.expect("item-1")
        let next = Task { await tracker.waitUntilSettled(timeout: .seconds(5)) }
        await tracker.waitForWaiters(1)
        await tracker.complete("item-1")
        await next.value
    }

    /// Checks completion without imposing a performance requirement on a busy simulator.
    /// A stalled wait must fail before being released, or the rescue could hide the regression.
    private func startWatchdog(
        for tracker: UserTranscriptTracker,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(for: .seconds(30))
                try Task.checkCancellation()
            } catch {
                return
            }
            Issue.record("Transcript wait did not complete before the 30-second watchdog", sourceLocation: sourceLocation)
            await tracker.reset()
        }
    }
}


extension UserTranscriptTracker {
    func waitForWaiters(_ count: Int) async {
        while waiterCount < count {
            await Task.yield()
        }
    }
}
