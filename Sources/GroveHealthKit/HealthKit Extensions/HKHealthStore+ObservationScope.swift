//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHealthStore {
    /// Observes changes for the duration of an asynchronous operation without owning query anchors.
    ///
    /// - Important: Experimental SPI. Requires `@_spi(Experimental) import GroveHealthKit`;
    ///   this interface may change or be removed without source-compatibility guarantees.
    ///
    /// Use this when an application already owns durable query checkpoints. The update handler receives
    /// wake signals, not samples. Query and durably stage the corresponding changes before returning;
    /// Grove acknowledges each callback after the handler returns, including cancellation and error paths.
    /// Handlers can overlap and must coordinate access to application-owned checkpoints themselves.
    ///
    /// The operation keeps the observation alive. On success, failure or cancellation, this method stops
    /// the query, cancels and awaits its handlers, then releases background-delivery ownership. SDK disable
    /// failures use Grove's existing bounded retry and logging. Other Grove collectors retain their ownership.
    /// Both the operation and update handler must cooperate with cancellation; this is not a hard deadline.
    ///
    /// This method does not request HealthKit permission or establish study consent. The caller must
    /// install its observation during application launch and provide the background-delivery entitlement.
    /// Use `startBackgroundObservation` from a synchronous launch hook; starting this async scope
    /// in a view task does not guarantee registration before the launch hook returns.
    /// Test operating-system background wakes on a physical device, not only in Simulator.
    /// See Apple's [observer setup](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
    /// and [acknowledgement contract](https://developer.apple.com/documentation/healthkit/hkobserverquerycompletionhandler).
    ///
    /// - Parameters:
    ///   - sampleTypes: Types to observe. An empty set runs the operation without registering a query.
    ///   - updateHandler: A bounded processing attempt for each wake or observer error. A failed attempt
    ///     must leave the application's checkpoint retryable; acknowledgement is not a custody receipt.
    ///   - operation: Work defining the observation's lifetime, usually awaiting application-owned cancellation.
    /// - Returns: The operation's result, after observation cleanup.
    /// - Throws: Registration or operation errors, or `CancellationError` when the caller is cancelled.
    @_spi(Experimental)
    @MainActor
    public func withBackgroundObservation<Result: Sendable>(
        for sampleTypes: Set<HKSampleType>,
        updateHandler: @escaping @MainActor @Sendable (Swift.Result<Set<HKSampleType>, any Error>) async -> Void,
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let task = startBackgroundObservation(for: sampleTypes, updateHandler: updateHandler, operation: operation)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Installs the observer before returning, then owns asynchronous delivery registration and cleanup.
    ///
    /// - Important: Experimental SPI. Requires `@_spi(Experimental) import GroveHealthKit`;
    ///   this interface may change or be removed without source-compatibility guarantees.
    ///
    /// Call from application launch, retain the returned task, and cancel and await it when the
    /// observation is no longer needed. Parent cancellation is not inherited by this unstructured
    /// task; `withBackgroundObservation` provides that forwarding for asynchronous callers.
    /// An already-cancelled caller installs nothing. Registration failures and operation completion
    /// stop the query and await all handlers before releasing background-delivery ownership.
    ///
    /// This adds no query checkpoint, permission prompt, retry scheduler or participant authority.
    /// The same entitlement, bounded-handler and physical-device requirements as the async scope apply.
    @_spi(Experimental)
    @MainActor
    public func startBackgroundObservation<Result: Sendable>(
        for sampleTypes: Set<HKSampleType>,
        updateHandler: @escaping @MainActor @Sendable (Swift.Result<Set<HKSampleType>, any Error>) async -> Void,
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, any Error> {
        guard !Task.isCancelled else {
            return Task { throw CancellationError() }
        }
        let observation = sampleTypes.isEmpty ? nil : installBackgroundObserver(for: sampleTypes, updateHandler: updateHandler)
        return Task { @MainActor in
            try await withInstalledObservation(observation, operation: operation)
        }
    }

    @MainActor
    private func withInstalledObservation<Result>(
        _ observation: BackgroundObserverQueryInvalidator?,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        var enabled = false
        let result: Result
        do {
            try Task.checkCancellation()
            if let observation {
                try await enableBackgroundDelivery(for: observation.objectTypes)
                enabled = true
            }
            try Task.checkCancellation()
            result = try await operation()
        } catch {
            await observation?.invalidateAndWait()
            if enabled, let observation { await disableBackgroundDelivery(for: observation.objectTypes) }
            throw error
        }
        await observation?.invalidateAndWait()
        if enabled, let observation { await disableBackgroundDelivery(for: observation.objectTypes) }
        try Task.checkCancellation()
        return result
    }
}

#endif
