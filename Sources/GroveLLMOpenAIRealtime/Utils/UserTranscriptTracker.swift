//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Tracks the user turns whose transcription is still on its way, so work that needs the words can wait for them.
@available(iOS 18, macOS 15, watchOS 11, *)
actor UserTranscriptTracker {
    private struct Waiter {
        let continuation: CheckedContinuation<Void, Never>
        let timeoutTask: Task<Void, Never>
    }

    private var pending: Set<String> = []
    private var completed: Set<String> = []
    private var waiters: [UUID: Waiter] = [:]

    var waiterCount: Int { waiters.count }

    func expect(_ itemId: String) {
        // A committed event can follow a transcript that already completed for the same turn.
        if !completed.contains(itemId) {
            pending.insert(itemId)
        }
    }

    func complete(_ itemId: String) {
        completed.insert(itemId)
        pending.remove(itemId)
        if pending.isEmpty {
            settle()
        }
    }

    func reset() {
        pending.removeAll()
        completed.removeAll()
        settle()
    }

    /// Returns once every expected transcript arrived, the timeout expires, or the caller is cancelled.
    func waitUntilSettled(timeout: Duration) async {
        let waiterId = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !pending.isEmpty, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                // Register before this actor can run the timeout, including a zero-duration timeout.
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        release(waiterId)
                    } catch {
                        // Completion or cancellation already released this waiter.
                    }
                }
                waiters[waiterId] = Waiter(continuation: continuation, timeoutTask: timeoutTask)
            }
        } onCancel: {
            Task { await self.release(waiterId) }
        }
    }

    private func release(_ waiterId: UUID) {
        guard let waiter = waiters.removeValue(forKey: waiterId) else {
            return
        }
        waiter.timeoutTask.cancel()
        waiter.continuation.resume()
    }

    private func settle() {
        for id in Array(waiters.keys) {
            release(id)
        }
    }
}
