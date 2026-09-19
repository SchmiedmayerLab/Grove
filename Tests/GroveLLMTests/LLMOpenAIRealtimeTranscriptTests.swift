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
        let waiter = Task { await tracker.waitUntilSettled(timeout: .seconds(30)) }
        if !cancelBeforeRegistration {
            await tracker.waitForWaiters(1)
        }
        let start = ContinuousClock.now
        waiter.cancel()
        // A bounded fallback makes a regression fail instead of leaving the test process hung.
        let fallback = Task {
            try await Task.sleep(for: .seconds(2))
            await tracker.complete("item-1")
        }
        await waiter.value
        fallback.cancel()
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(await tracker.waiterCount == 0)
    }

    @Test("A zero grace period cannot beat continuation registration")
    func immediateTimeout() async {
        let tracker = UserTranscriptTracker()
        await tracker.expect("item-1")
        let fallback = Task {
            try await Task.sleep(for: .seconds(2))
            await tracker.complete("item-1")
        }
        let start = ContinuousClock.now
        for _ in 0..<100 {
            await tracker.waitUntilSettled(timeout: .zero)
        }
        fallback.cancel()
        #expect(ContinuousClock.now - start < .seconds(1))
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
        let start = ContinuousClock.now
        await tracker.waitUntilSettled(timeout: .seconds(2))
        #expect(ContinuousClock.now - start < .seconds(1))
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
}


extension UserTranscriptTracker {
    func waitForWaiters(_ count: Int) async {
        while waiterCount < count {
            await Task.yield()
        }
    }
}
