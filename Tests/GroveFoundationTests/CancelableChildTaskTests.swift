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
        await withDiscardingTaskGroup { group in
            await confirmation { confirmation in
                let handle = group.addCancelableTask {
                    do {
                        try await Task.sleep(for: .milliseconds(250), tolerance: .nanoseconds(0))
                    } catch {
                        Issue.record(error, "Task.sleep unexpectedly failed")
                    }
                    confirmation()
                }
                do {
                    try await Task.sleep(for: .milliseconds(2000), tolerance: .nanoseconds(0))
                } catch {
                    Issue.record(error, "Task.sleep unexpectedly failed")
                }
                handle.cancel()
            }
        }
    }
    
    @Test(.timeLimit(.minutes(1)))
    func cancelation() async {
        await withDiscardingTaskGroup { group in
            await confirmation { confirmation in
                let handle = group.addCancelableTask {
                    do {
                        try await Task.sleep(for: .milliseconds(350), tolerance: .nanoseconds(0))
                        Issue.record("Task was not cancelled!")
                    } catch {
                        confirmation()
                    }
                }
                try? await Task.sleep(for: .milliseconds(50), tolerance: .nanoseconds(0))
                handle.cancel()
                try? await Task.sleep(for: .milliseconds(1000), tolerance: .nanoseconds(0))
            }
        }
    }
}
