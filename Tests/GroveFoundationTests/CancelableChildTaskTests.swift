//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import Testing


@Suite
struct CancelableChildTaskTests {
    @Test(.timeLimit(.minutes(1)))
    func normalCompletion() async {
        let (completed, completedContinuation) = AsyncStream<Void>.makeStream()
        await withDiscardingTaskGroup { group in
            await confirmation { confirmation in
                let handle = group.addCancelableTask {
                    confirmation()
                    completedContinuation.yield()
                    completedContinuation.finish()
                }
                for await _ in completed {
                    break
                }
                handle.cancel()
            }
        }
    }
    
    @Test(.timeLimit(.minutes(1)))
    func cancelation() async {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        await withDiscardingTaskGroup { group in
            await confirmation { confirmation in
                let handle = group.addCancelableTask {
                    startedContinuation.yield()
                    startedContinuation.finish()
                    do {
                        try await Task.sleep(for: .seconds(60), tolerance: .nanoseconds(0))
                        Issue.record("Task was not cancelled!")
                    } catch is CancellationError {
                        confirmation()
                    } catch {
                        Issue.record(error, "Cancelable task failed with an unexpected error")
                    }
                    cancelledContinuation.yield()
                    cancelledContinuation.finish()
                }
                for await _ in started {
                    break
                }
                handle.cancel()
                for await _ in cancelled {
                    break
                }
            }
        }
    }
}
