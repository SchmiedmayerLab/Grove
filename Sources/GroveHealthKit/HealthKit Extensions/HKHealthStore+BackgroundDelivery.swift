//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Grove
import HealthKit
import OSLog


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

    /// `@unchecked Sendable` safety: `completionHandler` is the only mutable field and every
    /// access is serialized by `lock`; `call()` removes it under the lock before invoking the
    /// captured handler, so concurrent callers can acknowledge the observer exactly once.
    final class ObserverQueryCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var completionHandler: HKObserverQueryCompletionHandler?

        init(_ completionHandler: @escaping HKObserverQueryCompletionHandler) {
            self.completionHandler = completionHandler
        }

        func call() {
            let completionHandler = lock.withLock {
                defer { self.completionHandler = nil }
                return self.completionHandler
            }
            completionHandler?()
        }
    }

    /// `@unchecked Sendable` safety: every read and mutation of `state` is serialized by `lock`.
    /// The stored tasks and their `@MainActor @Sendable` operations cross isolation as immutable
    /// values; cancellation snapshots are taken under the lock and awaited after releasing it.
    final class BackgroundDeliveryTaskTracker: @unchecked Sendable {
        private struct State {
            var invalidated = false
            var tasks: [UUID: Task<Void, Never>] = [:]
        }

        private let lock = NSLock()
        private var state = State()

        @discardableResult
        func schedule(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Bool {
            let id = UUID()
            lock.lock()
            guard !state.invalidated else {
                lock.unlock()
                return false
            }
            let task = Task { @MainActor [self] in
                defer { self.remove(id) }
                await operation()
            }
            state.tasks[id] = task
            lock.unlock()
            return true
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
            lock.withLock {
                state.tasks[id] = nil
            }
        }

        func cancelAndWait() async {
            lock.withLock {
                state.invalidated = true
            }
            while true {
                let tasks = lock.withLock { Array(state.tasks.values) }
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
    /// only weak-zeroed by the Swift runtime, `HKHealthStore` supports cross-thread query stop, and
    /// concurrent task teardown is serialized by `BackgroundDeliveryTaskTracker`'s lock.
    final class BackgroundObserverQueryInvalidator: @unchecked Sendable {
        private let healthStore: HKHealthStore
        private weak var query: HKQuery?
        private let taskTracker: BackgroundDeliveryTaskTracker
        
        init(healthStore: HKHealthStore, query: HKQuery, taskTracker: BackgroundDeliveryTaskTracker) {
            self.healthStore = healthStore
            self.query = query
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
    
    private static let activeObservationsLock = NSLock()
    /// Guarded by `activeObservationsLock`.
    ///
    /// A member has no remaining local owner, but the last SDK disable failed. Keeping that state
    /// distinct from an active registration lets a later teardown retry without pretending the
    /// departed collector still owns a reference.
    nonisolated(unsafe) private static var backgroundDeliveryOwnership = BackgroundDeliveryOwnership()

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
    
    @MainActor @discardableResult
    func startBackgroundDelivery(
        for sampleTypes: Set<HKSampleType>,
        withPredicate predicate: NSPredicate? = nil,
        updateHandler: @escaping @MainActor @Sendable (
            Result<Set<HKSampleType>, any Error>
        ) async -> Void
    ) async throws -> BackgroundObserverQueryInvalidator {
        let taskTracker = BackgroundDeliveryTaskTracker()
        let queryDescriptors: [HKQueryDescriptor] = sampleTypes
            .flatMap { $0.effectiveObjectTypesForAuthorization }
            .compactMap { $0 as? HKSampleType }
            .map { HKQueryDescriptor(sampleType: $0, predicate: predicate) }
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
        do {
            try await enableBackgroundDelivery(for: queryDescriptors.mapIntoSet(\.sampleType))
        } catch {
            // `execute` starts delivering immediately. If registration fails, there is no
            // invalidator to hand back to the caller, so tear down both halves here.
            self.stop(observerQuery)
            await taskTracker.cancelAndWait()
            throw error
        }
        return .init(healthStore: self, query: observerQuery, taskTracker: taskTracker)
    }
    
    
    func enableBackgroundDelivery(for objectTypes: Set<HKObjectType>) async throws {
        var enabledObjectTypes: Set<HKObjectType> = []
        do {
            for objectType in objectTypes {
                try await self.enableBackgroundDelivery(for: objectType, frequency: .immediate)
                enabledObjectTypes.insert(objectType)
                Self.activeObservationsLock.withLock {
                    Self.backgroundDeliveryOwnership.didEnable(objectType)
                }
            }
        } catch {
            HealthKit.logger.error("Could not enable HealthKit Backgound access for \(objectTypes): \(error.localizedDescription)")
            // Revert all changes as enable background delivery for the object types failed.
            await disableBackgroundDelivery(for: enabledObjectTypes)
            throw error
        }
    }
    
    
    @MainActor
    func disableBackgroundDelivery(
        for objectTypes: Set<HKObjectType>
    ) async {
        let objectTypesToDisable = Self.activeObservationsLock.withLock {
            Self.backgroundDeliveryOwnership.requestDisable(for: objectTypes)
        }
        for objectType in objectTypesToDisable {
            await disablePendingBackgroundDelivery(for: objectType)
        }
    }

    @MainActor
    private func disablePendingBackgroundDelivery(for objectType: HKObjectType) async {
        guard await retryPendingBackgroundDeliveryDisable(for: objectType) else {
            return
        }
        let completion = Self.activeObservationsLock.withLock {
            Self.backgroundDeliveryOwnership.didDisable(objectType)
        }
        guard completion == .supersededByOwner else {
            return
        }
        await restoreBackgroundDeliveryIfOwned(for: objectType)
    }

    @MainActor
    private func retryPendingBackgroundDeliveryDisable(for objectType: HKObjectType) async -> Bool {
        await Self.retryBackgroundDeliveryOperation(
            shouldContinue: {
                Self.activeObservationsLock.withLock {
                    Self.backgroundDeliveryOwnership.needsDisable(objectType)
                }
            },
            operation: {
                try await self.disableBackgroundDelivery(for: objectType)
            },
            waitBeforeRetry: { attempt in
                do {
                    let delay: Duration = attempt == 1 ? .milliseconds(250) : .seconds(1)
                    try await Task.sleep(for: delay)
                    return true
                } catch {
                    HealthKit.logger.error(
                        "Cancelled HealthKit background-delivery teardown retry for \(objectType): \(error.localizedDescription)"
                    )
                    return false
                }
            },
            onFailure: { error, attempt in
                HealthKit.logger.error(
                    "HealthKit background-delivery teardown attempt \(attempt) failed for \(objectType): \(error.localizedDescription)"
                )
            }
        )
    }

    @MainActor
    private func restoreBackgroundDeliveryIfOwned(for objectType: HKObjectType) async {
        // An owner can arrive while the SDK disable is suspended. The stale disable may then win
        // the race at the OS boundary, so restore delivery with the same owned bounded retry.
        let restored = await Self.retryBackgroundDeliveryOperation(
            shouldContinue: {
                Self.activeObservationsLock.withLock {
                    Self.backgroundDeliveryOwnership.hasActiveOwner(objectType)
                }
            },
            operation: {
                try await self.enableBackgroundDelivery(for: objectType, frequency: .immediate)
            },
            waitBeforeRetry: { attempt in
                do {
                    let delay: Duration = attempt == 1 ? .milliseconds(250) : .seconds(1)
                    try await Task.sleep(for: delay)
                    return true
                } catch {
                    HealthKit.logger.error(
                        "Cancelled HealthKit background-delivery restoration retry for \(objectType): \(error.localizedDescription)"
                    )
                    return false
                }
            },
            onFailure: { error, attempt in
                HealthKit.logger.error(
                    "HealthKit background-delivery restoration attempt \(attempt) failed for \(objectType): \(error.localizedDescription)"
                )
            }
        )
        if !restored {
            HealthKit.logger.error(
                "HealthKit background delivery for \(objectType) could not be restored for its active owner"
            )
        } else if Self.activeObservationsLock.withLock({
            Self.backgroundDeliveryOwnership.needsDisable(objectType)
        }) {
            // The restoring owner departed while SDK enable was suspended. Complete that newer
            // teardown instead of leaving delivery enabled without a local owner.
            await disablePendingBackgroundDelivery(for: objectType)
        }
    }
}

#endif
