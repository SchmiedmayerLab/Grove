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
    private var pending: Set<String> = []
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]


    func expect(_ itemId: String) {
        pending.insert(itemId)
    }

    func complete(_ itemId: String) {
        pending.remove(itemId)
        if pending.isEmpty {
            settle()
        }
    }

    /// Returns once every expected transcript arrived, or after `timeout`, whichever comes first.
    func waitUntilSettled(timeout: Duration) async {
        guard !pending.isEmpty else {
            return
        }
        let waiterId = UUID()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.waitForSettled(as: waiterId) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                // Only a timeout that actually ran out gives up; a cancelled sleep is the other side winning.
                guard !Task.isCancelled else {
                    return
                }
                await self.release(waiterId)
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func waitForSettled(as waiterId: UUID) async {
        await withCheckedContinuation { continuation in
            if pending.isEmpty {
                continuation.resume()
            } else {
                waiters[waiterId] = continuation
            }
        }
    }

    private func release(_ waiterId: UUID) {
        waiters.removeValue(forKey: waiterId)?.resume()
    }

    private func settle() {
        for waiter in waiters.values {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
