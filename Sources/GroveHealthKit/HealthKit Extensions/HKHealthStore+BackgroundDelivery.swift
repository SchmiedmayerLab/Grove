//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import class GroveFoundation.AsyncSemaphore
import HealthKit
import OSLog
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHealthStore {
    struct BackgroundDeliveryOwnership {
        enum DisableCompletion: Equatable {
            case completed
            case supersededByOwner
            case stale
        }

        private(set) var active: [HKObjectType: Int] = [:]
        private(set) var pendingDisables: Set<HKObjectType> = []

        mutating func didEnable(_ objectType: HKObjectType) {
            active[objectType, default: 0] += 1
            pendingDisables.remove(objectType)
        }

        mutating func requestDisable(for objectTypes: Set<HKObjectType>) -> Set<HKObjectType> {
            var result: Set<HKObjectType> = []
            for objectType in objectTypes {
                if let activeObservation = active[objectType] {
                    let newActiveObservation = activeObservation - 1
                    if newActiveObservation <= 0 {
                        active[objectType] = nil
                        pendingDisables.insert(objectType)
                        result.insert(objectType)
                    } else {
                        active[objectType] = newActiveObservation
                    }
                } else if pendingDisables.contains(objectType) {
                    result.insert(objectType)
                }
            }
            return result
        }

        mutating func didDisable(_ objectType: HKObjectType) -> DisableCompletion {
            if pendingDisables.remove(objectType) != nil {
                return .completed
            }
            return active[objectType, default: 0] > 0 ? .supersededByOwner : .stale
        }

        func needsDisable(_ objectType: HKObjectType) -> Bool {
            pendingDisables.contains(objectType)
        }

        func hasActiveOwner(_ objectType: HKObjectType) -> Bool {
            active[objectType, default: 0] > 0
        }
    }

    /// The handler is taken under the lock before it is invoked, so concurrent callers
    /// acknowledge the observer exactly once.
    final class ObserverQueryCompletion: Sendable {
        /// HealthKit's acknowledgement block is not `Sendable` although the SDK calls and expects it
        /// on its own background queues; the box carries it out of the lock to be called once.
        private struct Acknowledgement: @unchecked Sendable {
            let call: HKObserverQueryCompletionHandler
        }

        private let acknowledgement: Mutex<Acknowledgement?>

        init(_ completionHandler: @escaping HKObserverQueryCompletionHandler) {
            self.acknowledgement = Mutex(Acknowledgement(call: completionHandler))
        }

        func call() {
            let acknowledgement = self.acknowledgement.withLock { acknowledgement in
                defer { acknowledgement = nil }
                return acknowledgement
            }
            acknowledgement?.call()
        }
    }

    final class BackgroundDeliveryTaskTracker: Sendable {
        private struct State {
            var invalidated = false
            var tasks: [UUID: Task<Void, Never>] = [:]
        }

        private let state = Mutex(State())

        @discardableResult
        func schedule(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Bool {
            let id = UUID()
            return state.withLock { state in
                guard !state.invalidated else {
                    return false
                }
                state.tasks[id] = Task { @MainActor [self] in
                    defer { self.remove(id) }
                    await operation()
                }
                return true
            }
        }

        func scheduleAcknowledging(
            _ completion: ObserverQueryCompletion,
            operation: @escaping @MainActor @Sendable () async -> Void
        ) {
            let scheduled = schedule {
                defer { completion.call() }
                await operation()
            }
            if !scheduled {
                completion.call()
            }
        }

        private func remove(_ id: UUID) {
            state.withLock { $0.tasks[id] = nil }
        }

        func cancelAndWait() async {
            state.withLock { $0.invalidated = true }
            while true {
                let tasks = state.withLock { Array($0.tasks.values) }
                guard !tasks.isEmpty else {
                    return
                }
                tasks.forEach { $0.cancel() }
                for task in tasks {
                    await task.value
                }
            }
        }
    }

    /// `@unchecked Sendable` safety: all strong fields are immutable, `query` is assigned once and
    /// only weak-zeroed by the Swift runtime, and `HKHealthStore` supports cross-thread query stop.
    final class BackgroundObserverQueryInvalidator: @unchecked Sendable {
        let objectTypes: Set<HKObjectType>
        private let healthStore: HKHealthStore
        private weak var query: HKQuery?
        private let taskTracker: BackgroundDeliveryTaskTracker
        
        init(healthStore: HKHealthStore, query: HKQuery, objectTypes: Set<HKObjectType>, taskTracker: BackgroundDeliveryTaskTracker) {
            self.healthStore = healthStore
            self.query = query
            self.objectTypes = objectTypes
            self.taskTracker = taskTracker
        }
        
        func invalidate() {
            if let query {
                healthStore.stop(query)
            }
        }

        func invalidateAndWait() async {
            invalidate()
            await taskTracker.cancelAndWait()
        }
    }
    
    /// A member has no remaining local owner, but the last SDK disable failed. Keeping that state
    /// distinct from an active registration lets a later teardown retry without pretending the
    /// departed collector still owns a reference.
    private static let backgroundDeliveryOwnership = Mutex(BackgroundDeliveryOwnership())

    @MainActor
    static func retryBackgroundDeliveryOperation(
        maxAttempts: Int = 3,
        shouldContinue: () -> Bool,
        operation: () async throws -> Void,
        waitBeforeRetry: (Int) async -> Bool,
        onFailure: (any Error, Int) -> Void
    ) async -> Bool {
        precondition(maxAttempts > 0)
        for attempt in 1...maxAttempts {
            guard shouldContinue() else {
                return false
            }
            do {
                try await operation()
                return true
            } catch {
                onFailure(error, attempt)
                guard attempt < maxAttempts, await waitBeforeRetry(attempt) else {
                    return false
                }
            }
        }
        return false
    }
    
    @MainActor
    @discardableResult
    func startBackgroundDelivery(
        for sampleType: HKSampleType,
        withPredicate predicate: NSPredicate? = nil,
        updateHandler: @escaping @MainActor @Sendable (
            Result<Set<HKSampleType>, any Error>
        ) async -> Void
    ) async throws -> BackgroundObserverQueryInvalidator {
        let observation = installBackgroundObserver(for: [sampleType], withPredicate: predicate, updateHandler: updateHandler)
        try await registerBackgroundDelivery(for: observation)
        return observation
    }

    /// Installs synchronously so launch callers do not depend on an asynchronous task being scheduled.
    @MainActor
    func installBackgroundObserver(
        for sampleTypes: Set<HKSampleType>,
        withPredicate predicate: NSPredicate? = nil,
        updateHandler: @escaping @MainActor @Sendable (Result<Set<HKSampleType>, any Error>) async -> Void
    ) -> BackgroundObserverQueryInvalidator {
        let taskTracker = BackgroundDeliveryTaskTracker()
        let objectTypes = Set(sampleTypes
            .flatMap { $0.effectiveObjectTypesForAuthorization }
            .compactMap { $0 as? HKSampleType })
        let queryDescriptors = objectTypes.map { HKQueryDescriptor(sampleType: $0, predicate: predicate) }
        let observerQuery = HKObserverQuery(queryDescriptors: queryDescriptors) { query, sampleTypes, completionHandler, error in
            // From https://developer.apple.com/documentation/healthkit/hkobserverquery/executing_observer_queries
            // "Whenever a matching sample is added to or deleted from the HealthKit store,
            // the system calls the query’s update handler on the same background queue (but not necessarily the same thread)."
            // So, the observerQuery has to be @Sendable!
            
            let completion = ObserverQueryCompletion(completionHandler)
            if let error {
                HealthKit.logger.error(
                    """
                    Failed HealthKit background delivery for observer query \(query) on sample types \(String(describing: sampleTypes)) with error: \(error)
                    """
                )
                taskTracker.scheduleAcknowledging(completion) {
                    await updateHandler(.failure(error))
                }
                return
            }
            guard let sampleTypes else {
                // invalid observer query update (both error and sampleTypes were nil).
                // There's nothing we can do here, so we just ignore it.
                completion.call()
                return
            }
            taskTracker.scheduleAcknowledging(completion) {
                await updateHandler(.success(sampleTypes))
            }
        }
        self.execute(observerQuery)
        return .init(healthStore: self, query: observerQuery, objectTypes: Set(objectTypes), taskTracker: taskTracker)
    }

    /// Acquires delivery ownership for an installed observer. Failed registration owns its cleanup;
    /// callers must not release the observation again after this method throws.
    @MainActor
    func registerBackgroundDelivery(for observation: BackgroundObserverQueryInvalidator) async throws {
        var acquired = Set<HKObjectType>()
        do {
            try Task.checkCancellation()
            for objectType in observation.objectTypes {
                try Task.checkCancellation()
                try await enableBackgroundDelivery(for: objectType)
                acquired.insert(objectType)
            }
            try Task.checkCancellation()
        } catch {
            // Installation starts callbacks immediately. Stop and drain them before releasing any
            // ownership, and roll back only acquisitions made by this registration attempt.
            await observation.invalidateAndWait()
            await disableBackgroundDelivery(for: acquired)
            throw error
        }
    }

    /// Releases a successfully registered observation after its callbacks have finished.
    @MainActor
    func stopBackgroundDelivery(for observation: BackgroundObserverQueryInvalidator) async {
        await observation.invalidateAndWait()
        await disableBackgroundDelivery(for: observation.objectTypes)
    }

    @MainActor
    private func disableBackgroundDelivery(for objectTypes: Set<HKObjectType>) async {
        // A cancelled owner must still finish bounded SDK retries, including their retry delays.
        // Each scalar operation owns the gate; holding it around this loop would deadlock.
        await Task { @MainActor in
            for objectType in objectTypes {
                do {
                    try await disableBackgroundDelivery(for: objectType)
                } catch {
                    HealthKit.logger.error(
                        "Failed to release background delivery for \(objectType.identifier); error type: \(String(reflecting: type(of: error)), privacy: .public)"
                    )
                }
            }
        }.value
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHealthStore {
    private static let backgroundDeliveryOperationsGate = AsyncSemaphore()


    @MainActor
    func enableBackgroundDelivery(for objectType: HKObjectType) async throws {
        await Self.backgroundDeliveryOperationsGate.wait()
        defer { Self.backgroundDeliveryOperationsGate.signal() }

        let alreadyEnabled = Self.backgroundDeliveryOwnership.withLock { ownership in
            guard ownership.hasActiveOwner(objectType) else {
                return false
            }
            ownership.didEnable(objectType)
            return true
        }
        guard !alreadyEnabled else {
            return
        }
        try await self.HealthKit::enableBackgroundDelivery(for: objectType, frequency: .immediate)
        Self.backgroundDeliveryOwnership.withLock { $0.didEnable(objectType) }
    }


    @MainActor
    func disableBackgroundDelivery(for objectType: HKObjectType) async throws {
        await Self.backgroundDeliveryOperationsGate.wait()
        defer { Self.backgroundDeliveryOperationsGate.signal() }

        // Release this owner once. SDK retries must not decrement another collector's ownership.
        let needsDisable = Self.backgroundDeliveryOwnership.withLock {
            $0.requestDisable(for: [objectType]).contains(objectType)
        }
        guard needsDisable else {
            return
        }

        // Keep the gate until the SDK operation and bookkeeping finish, so a new registration
        // cannot be disabled by an older teardown. Failures leave delivery pending, not owned.
        var lastError: (any Error)?
        let disabled = await Self.retryBackgroundDeliveryOperation(
            shouldContinue: {
                Self.backgroundDeliveryOwnership.withLock { $0.needsDisable(objectType) }
            },
            operation: {
                try await self.HealthKit::disableBackgroundDelivery(for: objectType)
            },
            waitBeforeRetry: { attempt in
                do {
                    let delay: Duration = attempt == 1 ? .milliseconds(250) : .seconds(1)
                    try await Task.sleep(for: delay)
                    return true
                } catch {
                    return false
                }
            },
            onFailure: { error, attempt in
                lastError = error
                HealthKit.logger.error(
                    "HealthKit background-delivery teardown attempt \(attempt) failed for \(objectType): \(error.localizedDescription)"
                )
            }
        )
        if disabled {
            _ = Self.backgroundDeliveryOwnership.withLock { $0.didDisable(objectType) }
        } else if let lastError {
            // Keep the pending disable for later recovery. Never invent another active owner or
            // broaden cleanup to types whose ownership this operation did not release.
            throw lastError
        }
    }
}

#endif
