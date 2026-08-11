//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A continuation with exclusive access.
///
///
public final class ManagedAsynchronousAccess<Value, E: Error> {
    private final class CallSiteState {
        var wasCancelled = false

        init() {}
    }

    private let access: AsyncSemaphore
    private var continuation: CheckedContinuation<Value, E>?
    private var associatedState: CallSiteState?

    /// Determine if the is currently an ongoing access.
    public var ongoingAccess: Bool {
        continuation != nil
    }
    
    /// Create a new managed asynchronous access.
    public init() {
        self.access = AsyncSemaphore(value: 1)
    }

    private func markCancelled() {
        if let associatedState {
            associatedState.wasCancelled = true
            self.associatedState = nil
        }
    }

    /// Resume the continuation by either returning a value or throwing an error.
    /// - Parameter result: The result to return from the continuation.
    /// - Returns: Returns `true`, if there was another task waiting to access the continuation and it was resumed.
    @discardableResult
    public func resume(with result: sending Result<Value, E>) -> Bool {
        self.associatedState = nil
        if let continuation {
            self.continuation = nil
            let didSignalAnyone = access.signal()
            continuation.resume(with: result)
            return didSignalAnyone
        }

        return false
    }
    
    /// Resume the continuation by returning a value.
    /// - Parameter value: The value to return from the continuation.
    /// - Returns: Returns `true`, if there was another task waiting to access the continuation and it was resumed.
    @discardableResult
    public func resume(returning value: sending Value) -> Bool {
        resume(with: .success(value))
    }
    
    /// Resume the continuation by throwing an error.
    /// - Parameter error: The error that is thrown from the continuation.
    /// - Returns: Returns `true`, if there was another task waiting to access the continuation and it was resumed.
    @discardableResult
    public func resume(throwing error: E) -> Bool {
        resume(with: .failure(error))
    }
}


extension ManagedAsynchronousAccess where Value == Void {
    /// Resume the continuation.
    /// - Returns: Returns `true`, if there was another task waiting to access the continuation and it was resumed.
    @discardableResult
    public func resume() -> Bool {
        self.resume(returning: ())
    }
}


extension ManagedAsynchronousAccess where E == any Error {
    /// Perform an managed, asynchronous access.
    ///
    /// Call this method to perform an managed, asynchronous access. This method awaits exclusive access, creates a continuation and
    /// calls the provided closure and then suspends until ``resume(with:)`` is called.
    ///
    /// - Parameters:
    ///   - isolation: Inherits actor isolation from the call site.
    ///   - action: The action that is executed inside the continuation closure that triggers an asynchronous operation.
    /// - Returns: The value from the continuation.
    public func perform(
        isolation: isolated (any Actor)? = #isolation,
        action: () -> Void
    ) async throws -> Value {
        try await access.waitCheckingCancellation()

        let state = CallSiteState()

        defer {
            if state.wasCancelled {
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            assert(self.continuation == nil, "continuation was unexpectedly not nil")
            self.continuation = continuation
            assert(self.associatedState == nil, "associatedState was unexpectedly not nil")
            self.associatedState = state
            action()
        }
    }
    
    /// Cancel all ongoing accesses.
    ///
    /// Calling this methods will cancel all tasks that currently await exclusive access and will resume the continuation by throwing a
    /// cancellation error.
    /// - Parameter error: A custom error that is thrown instead of the cancellation error.
    public func cancelAll(error: E? = nil) {
        markCancelled()
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: error ?? CancellationError())
        }
        access.cancelAll()
    }
}


extension ManagedAsynchronousAccess where E == Never {
    /// Perform an managed, asynchronous access.
    ///
    /// Call this method to perform an managed, asynchronous access. This method awaits exclusive access, creates a continuation and
    /// calls the provided closure and then suspends until ``resume(with:)`` is called.
    ///
    /// - Parameters:
    ///   - isolation: Inherits actor isolation from the call site.
    ///   - action: The action that is executed inside the continuation closure that triggers an asynchronous operation.
    public func perform(
        isolation: isolated (any Actor)? = #isolation,
        action: () -> Void
    ) async throws(CancellationError) -> Value {
        try await access.waitCheckingCancellation()

        let state = CallSiteState()

        let value = await withCheckedContinuation { continuation in
            assert(self.continuation == nil, "continuation was unexpectedly not nil")
            self.continuation = continuation
            assert(self.associatedState == nil, "associatedState was unexpectedly not nil")
            self.associatedState = state
            action()
        }

        if state.wasCancelled {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            throw CancellationError()
        }

        return value
    }
}


extension ManagedAsynchronousAccess where Value == Void, E == Never {
    /// Cancel all ongoing accesses.
    ///
    /// Calling this methods will cancel all tasks that currently await exclusive access.
    /// The continuation will be resumed. Make sure to propagate cancellation information yourself.
    public func cancelAll() {
        markCancelled()
        if let continuation {
            self.continuation = nil
            continuation.resume()
        }
        access.cancelAll()
    }
}
