//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziFoundation
import Testing


@Suite
struct TimeoutTests {
    @MainActor
    private final class Storage {
        var continuation: CheckedContinuation<Void, any Error>?
    }
    
    private let storage = Storage()
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @MainActor
    func operation(for duration: Duration) {
        Task { @MainActor in
            do {
                try await Task.sleep(for: duration)
                if let continuation = exchange(&storage.continuation, with: nil) {
                    continuation.resume()
                }
            } catch {
                if let continuation = exchange(&storage.continuation, with: nil) {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @MainActor
    func operationMethod(timeout: Duration, operation: Duration) async throws {
        let storage = storage
        async let _ = withTimeout(of: timeout) { @MainActor [storage] in
            #expect(!Task.isCancelled)
            if let continuation = exchange(&storage.continuation, with: nil) {
                continuation.resume(throwing: TimeoutError())
            }
        }
        
        try await withCheckedThrowingContinuation { continuation in
            storage.continuation = continuation
            self.operation(for: operation)
        }
    }
    
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test("Operation finishes", .timeLimit(.minutes(1)))
    func completesWithinTimeout() async throws {
        try await confirmation("operation finishes") { confirmed in
            try await operationMethod(
                timeout: .seconds(10),
                operation: .milliseconds(250)
            )
            confirmed()
        }
    }
    
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test("Operation times out", .timeLimit(.minutes(1)))
    func throwsOnTimeout() async throws {
        await confirmation("operation times out") { confirmed in
            do {
                try await operationMethod(
                    timeout: .milliseconds(250),
                    operation: .seconds(10)
                )
            } catch {
                #expect(error is TimeoutError)
                confirmed()
            }
        }
    }
}
