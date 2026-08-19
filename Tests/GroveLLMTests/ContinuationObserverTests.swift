//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLM
import Testing


/// Covers the signal every generation path reads to decide whether to keep working.
///
/// Stopping a session finishes its stream with a `CancellationError` instead of dropping it, so a stream that only
/// treated `.cancelled` as cancellation would report `isCancelled == false` forever and the generation would run on
/// past the user's Stop.
@Suite("Continuation Observer")
struct ContinuationObserverTests {
    /// `onTermination` runs off the caller, so the flag lands shortly after the stream ends rather than during it.
    private static func waitForCancellation<T, E>(of observer: ContinuationObserver<T, E>) async throws {
        for _ in 0..<100 where !observer.isCancelled {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Stopping a session marks its continuation cancelled")
    func stoppingMarksCancelled() async throws {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let observer = ContinuationObserver(track: continuation)
        #expect(!observer.isCancelled, "a live continuation is not cancelled")

        let holder = LLMInferenceQueueContinuationHolder()
        _ = holder.add(continuation)
        holder.cancelAll()

        try await Self.waitForCancellation(of: observer)
        #expect(observer.isCancelled, "a session that was stopped has to read as cancelled")

        // The consumer still learns why the stream ended.
        await #expect(throws: CancellationError.self) {
            for try await _ in stream {}
        }
    }

    @Test("A consumer walking away marks the continuation cancelled")
    func droppedStreamMarksCancelled() async throws {
        let observer: ContinuationObserver<String, any Error>
        do {
            let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            observer = ContinuationObserver(track: continuation)
            _ = stream
        }

        try await Self.waitForCancellation(of: observer)
        #expect(observer.isCancelled, "dropping the stream cancels it")
    }

    @Test("Finishing normally leaves the continuation uncancelled")
    func normalCompletionIsNotCancellation() async throws {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let observer = ContinuationObserver(track: continuation)

        continuation.yield("done")
        continuation.finish()
        for try await _ in stream {}

        #expect(!observer.isCancelled, "an answer that simply ended is not a cancellation")
    }
}
