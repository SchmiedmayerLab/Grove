//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation

/// Timeout occurred inside an async operation.
public struct TimeoutError {
    /// Create a new timeout error.
    public init() {}
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension TimeoutError: LocalizedError {
    public var errorDescription: String? {
        #if canImport(Darwin)
            String(localized: LocalizedStringResource("Timeout", bundle: .atURL(Bundle.module.bundleURL)))
        #else
            "Timeout"
        #endif
    }

    public var failureReason: String? {
        #if canImport(Darwin)
            String(localized: LocalizedStringResource("The operation timed out.", bundle: .atURL(Bundle.module.bundleURL)))
        #else
            "The operation timed out."
        #endif
    }
}


/// Race a timeout.
///
/// This method can be used to race an operation against a timeout.
///
/// ### Timeout in Async Context
///
/// Below is a code example showing how to best use the `withTimeout(of:perform:)` method in an async method.
/// The example uses [Structured Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency)
/// creating a child task running the timeout task. This makes sure that the timeout is automatically cancelled when the method goes out of scope.
///
/// - Note: The example isolates the `continuation` property to the MainActor to ensure accesses are synchronized.
///     Further, the method throws an error if the operation is already running. We use the `OperationAlreadyInUseError`
///     error as an example.
///
/// ```swift
/// @MainActor
/// var operation: CheckedContinuation<Void, Error>?
///
/// @MainActor
/// func foo() async throws {
///     guard continuation == nil else {
///         throw OperationAlreadyInUseError() // exemplary way of handling concurrent accesses
///     }
///
///     async let _ = withTimeout(of: .seconds(30)) { @MainActor in
///         // operation timed out,  resume continuation by throwing a `TimeoutError`.
///         if let continuation = operation {
///             operation = nil
///             continuation.resume(throwing: TimeoutError())
///         }
///     }
///
///     runOperation()
///     try await withCheckedThrowingContinuation { continuation in
///         self.continuation = continuation
///     }
/// }
///
/// @MainActor
/// func handleOperationCompleted() {
///     if let continuation = operation {
///         operation = nil
///         continuation.resume()
///     }
/// }
/// ```
///
/// ### Timeout in Sync Context
///
/// Using `withTimeout(of:perform:)` in a synchronous method is similar. However, you will need to take care of cancellation yourself.
///
/// ```swift
/// func foo() throws {
///     let timeoutTask = Task {
///         await withTimeout(of: .seconds(30)) {
///             // cancel operation ...
///         }
///     }
///
///     defer {
///         timeoutTask.cancel()
///     }
///
///     try operation()
/// }
/// ```
///
/// - Parameters:
///   - timeout: The duration of the timeout.
///   - action: The action to run once the timeout passed.
@available(iOS 18, macOS 15, watchOS 11, *)
@inlinable
public func withTimeout(of timeout: Duration, perform action: sending () async -> Void) async {
    try? await Task.sleep(for: timeout)
    guard !Task.isCancelled else {
        return
    }
    await action()
}
