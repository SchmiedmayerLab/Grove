//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import Testing


@Suite
struct CancelableChildTaskTests {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    @Test(.timeLimit(.minutes(1)))
    func normalCompletion() async {
        await withDiscardingTaskGroup { group in
            await confirmation { confirmation in
                let completed = AsyncStream<Void>.makeStream()
                let completedContinuation = completed.continuation
                let handle = group.addCancelableTask {
                    confirmation()
                    completedContinuation.yield()
                    completedContinuation.finish()
                }
                await waitForSignal(completed.stream)
                handle.cancel()
            }
        }
    }
    
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    @Test(.timeLimit(.minutes(1)))
    func cancelation() async {
        await withDiscardingTaskGroup { group in
            await confirmation { confirmation in
                let started = AsyncStream<Void>.makeStream()
                let canceled = AsyncStream<Void>.makeStream()
                let startedContinuation = started.continuation
                let canceledContinuation = canceled.continuation
                let handle = group.addCancelableTask {
                    startedContinuation.yield()
                    startedContinuation.finish()
                    do {
                        try await Task.sleep(for: .seconds(10), tolerance: .nanoseconds(0))
                        Issue.record("Task was not cancelled!")
                    } catch is CancellationError {
                        confirmation()
                    } catch {
                        Issue.record(error, "Task.sleep unexpectedly failed")
                    }
                    canceledContinuation.yield()
                    canceledContinuation.finish()
                }
                await waitForSignal(started.stream)
                handle.cancel()
                await waitForSignal(canceled.stream)
            }
        }
    }

    private func waitForSignal(_ stream: AsyncStream<Void>) async {
        for await _ in stream {
            return
        }
        Issue.record("Expected signal was not emitted.")
    }
}
