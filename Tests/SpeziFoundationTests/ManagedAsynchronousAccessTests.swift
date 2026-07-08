//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziFoundation
import Testing

@MainActor
@Suite
struct ManagedAsynchronousAccessTests {
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func resumeWithSuccess() async throws {
        let access = ManagedAsynchronousAccess<String, any Error>()
        let expectedValue = "Success"

        try await confirmation("perform() returns with success") { confirm in
            let task = Task {
                do {
                    let value = try await access.perform {
                        // this is were you would trigger your operation
                    }
                    #expect(value == expectedValue)
                } catch {
                    Issue.record("Unexpected error: \(error)")
                }
                confirm()
            }
            
            try await Task.sleep(for: .milliseconds(100))
            #expect(access.ongoingAccess)
            let didResume = access.resume(returning: expectedValue)

            #expect(!didResume)
            #expect(!access.ongoingAccess)
            
            await task.value
        }
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func resumeWithError() async throws {
        let access = ManagedAsynchronousAccess<String, any Error>()

        try await confirmation("perform() returns with error") { confirm in
            let task = Task {
                do {
                    _ = try await access.perform { }
                    Issue.record("Expected error, but got success.")
                } catch {
                    #expect(error is TimeoutError)
                }
                confirm()
            }
            
            try await Task.sleep(for: .milliseconds(100))
            #expect(access.ongoingAccess)
            let didResume = access.resume(throwing: TimeoutError())

            #expect(!didResume)
            #expect(!access.ongoingAccess)
            
            await task.value
        }
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func cancelAll() async throws {
        let access = ManagedAsynchronousAccess<Void, any Error>()

        try await confirmation("perform() returns with cancellation error") { confirm in
            let task = Task {
                do {
                    _ = try await access.perform {}
                    Issue.record("Expected cancellation error.")
                } catch {
                    #expect(error is CancellationError)
                }
                confirm()
            }
            
            try await Task.sleep(for: .milliseconds(100))
            #expect(access.ongoingAccess)
            #expect(!task.isCancelled)
            
            access.cancelAll()

            #expect(!access.ongoingAccess)
            
            await task.value
            
            #expect(task.isCancelled, "Task should be marked as cancelled.")
        }
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func cancelAllNeverError() async throws {
        let access = ManagedAsynchronousAccess<Void, Never>()

        try await confirmation("perform() returns with cancellation error") { confirm in
            let task = Task {
                do {
                    try await access.perform {}
                    Issue.record("Expected cancellation to turn into a cancellation error")
                } catch {
                    #expect(error is CancellationError)
                }
                confirm()
            }
            
            try await Task.sleep(for: .milliseconds(100))
            
            #expect(access.ongoingAccess)
            #expect(!task.isCancelled)
            
            access.cancelAll()
            
            #expect(!access.ongoingAccess)
            
            await task.value
            
            #expect(task.isCancelled, "Task should be marked as cancelled.")
        }
    }
    
    @Test
    func resumeWithoutOngoingAccess() {
        let access = ManagedAsynchronousAccess<String, any Error>()

        let didResume = access.resume(returning: "No Access")

        #expect(!didResume)
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func resumeWithVoidValue() async throws {
        let access = ManagedAsynchronousAccess<Void, Never>()

        try await confirmation("perform() returns with cancellation error") { confirm in
            let task = Task {
                try await access.perform {}
                confirm()
            }
            
            try await Task.sleep(for: .milliseconds(100))
            
            #expect(access.ongoingAccess)
            
            let didResume = access.resume()
            
            #expect(!didResume)
            #expect(!access.ongoingAccess)
            
            try await task.value
        }
    }

    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func exclusiveAccess() async throws {
        let access = ManagedAsynchronousAccess<String, any Error>()
        let expectedValue0 = "Success0"
        let expectedValue1 = "Success1"

        try await confirmation("expectation of task0") { expectation0 in
            try await confirmation("expectation of task1") { expectation1 in
                let task0 = Task {
                    do {
                        let value = try await access.perform {}
                        #expect(value == expectedValue0)
                    } catch {
                        Issue.record("Unexpected error: \(error)")
                    }
                    expectation0()
                }
                
                try await Task.sleep(for: .milliseconds(100))
                
                let task1 = Task {
                    do {
                        let value = try await access.perform {}
                        #expect(value == expectedValue1)
                    } catch {
                        Issue.record("Unexpected error: \(error)")
                    }
                    expectation1()
                }
                
                try await Task.sleep(for: .milliseconds(100))
                
                #expect(access.ongoingAccess)
                
                let didResume0 = access.resume(returning: expectedValue0)
                
                #expect(didResume0)
                #expect(!access.ongoingAccess)
                
                await task0.value
                
                try await Task.sleep(for: .milliseconds(100))
                
                #expect(access.ongoingAccess)
                
                let didResume1 = access.resume(returning: expectedValue1)
                
                #expect(!didResume1)
                #expect(!access.ongoingAccess)

                await task1.value
            }
        }
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func exclusiveAccessNeverError() async throws {
        let access = ManagedAsynchronousAccess<String, Never>()
        let expectedValue0 = "Success0"
        let expectedValue1 = "Success1"
        try await confirmation("expectation of task0") { expectation0 in
            try await confirmation("expectation of task1") { expectation1 in
                let task0 = Task {
                    do {
                        let value = try await access.perform {}
                        #expect(value == expectedValue0)
                    } catch is CancellationError {
                        Issue.record("Unexpected error cancellation")
                    }
                    expectation0()
                }
                
                try await Task.sleep(for: .milliseconds(100))
                
                let task1 = Task {
                    do {
                        let value = try await access.perform {}
                        #expect(value == expectedValue1)
                    } catch is CancellationError {
                        Issue.record("Unexpected error cancellation")
                    }
                    expectation1()
                }
                
                try await Task.sleep(for: .milliseconds(100))
                
                #expect(access.ongoingAccess)
                
                let didResume0 = access.resume(returning: expectedValue0)
                
                #expect(didResume0)
                #expect(!access.ongoingAccess)
                
                try await task0.value
                
                try await Task.sleep(for: .milliseconds(100))
                
                #expect(access.ongoingAccess)
                
                let didResume1 = access.resume(returning: expectedValue1)
                
                #expect(!didResume1)
                #expect(!access.ongoingAccess)
                
                try await task1.value
            }
        }
    }
}
