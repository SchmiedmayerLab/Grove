//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import Dispatch
import SpeziFoundation
import Testing


#if canImport(Darwin)
/// Internal helper actor to be able to have code run guaranteed off the main actor (by scheduling it onto a background queue)
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
@globalActor
private actor TestActor: GlobalActor {
    static let shared = TestActor()
    let queue = DispatchQueue(label: "Queue") as! DispatchSerialQueue // swiftlint:disable:this force_cast
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }
}


@Suite
struct MainActorExecutionTests {
    @Test
    @MainActor
    func ifAlreadyRunningOnMainActor() {
        // XCTest by default runs all test cases on the main thread, ie the main queue, ie the main actor.
        dispatchPrecondition(condition: .onQueue(.main))
        var didRun = false
        runOrScheduleOnMainActor {
            didRun = true
        }
        #expect(didRun)
    }
    
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *)
    @Test
    @TestActor
    func ifRunningOffTheMainActor() async throws {
        dispatchPrecondition(condition: .notOnQueue(.main))
        dispatchPrecondition(condition: .onQueue(TestActor.shared.queue))
        try await confirmation { confirm in
            runOrScheduleOnMainActor {
                confirm()
            }
            try await Task.sleep(for: .seconds(0.5))
        }
    }
}
#endif
