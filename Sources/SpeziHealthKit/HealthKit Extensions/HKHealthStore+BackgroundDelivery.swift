//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
import OSLog
import class SpeziFoundation.AsyncSemaphore


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKHealthStore {
    final class BackgroundObserverQueryInvalidator: @unchecked Sendable {
        private let healthStore: HKHealthStore
        private weak var query: HKQuery?
        
        init(healthStore: HKHealthStore, query: HKQuery) {
            self.healthStore = healthStore
            self.query = query
        }
        
        func invalidate() {
            if let query {
                healthStore.stop(query)
            }
        }
    }
    
    @MainActor
    @discardableResult
    func startBackgroundDelivery(
        for sampleType: HKSampleType,
        withPredicate predicate: NSPredicate? = nil,
        updateHandler: @escaping @MainActor @Sendable (
            Result<(sampleTypes: Set<HKSampleType>, completionHandler: HKObserverQueryCompletionHandler), any Error>
        ) async -> Void
    ) async throws -> BackgroundObserverQueryInvalidator {
        let queryDescriptors: [HKQueryDescriptor] = sampleType
            .effectiveObjectTypesForAuthorization
            .compactMap { $0 as? HKSampleType }
            .map { HKQueryDescriptor(sampleType: $0, predicate: predicate) }
        let observerQuery = HKObserverQuery(queryDescriptors: queryDescriptors) { query, sampleTypes, completionHandler, error in
            // From https://developer.apple.com/documentation/healthkit/hkobserverquery/executing_observer_queries
            // "Whenever a matching sample is added to or deleted from the HealthKit store,
            // the system calls the query’s update handler on the same background queue (but not necessarily the same thread)."
            // So, the observerQuery has to be @Sendable!
            
            // Sadly necessary to enable capture of the `completionHandler` within the `Task`s below (isolation error)
            nonisolated(unsafe) let completionHandler = completionHandler
            if let error {
                HealthKit.logger.error(
                    """
                    Failed HealthKit background delivery for observer query \(query) on sample types \(String(describing: sampleTypes)) with error: \(error)
                    """
                )
                Task { @MainActor in
                    await updateHandler(.failure(error))
                    completionHandler()
                }
                return
            }
            guard let sampleTypes else {
                // invalid observer query update (both error and sampleTypes were nil).
                // There's nothing we can do here, so we just ignore it.
                return
            }
            Task { @MainActor in
                await updateHandler(.success((sampleTypes, completionHandler)))
            }
        }
        do {
            var enabled = Set<HKSampleType>()
            do {
                for descriptor in queryDescriptors {
                    try await enableBackgroundDelivery(for: descriptor.sampleType)
                    enabled.insert(descriptor.sampleType)
                }
            } catch {
                // if one of the sample types fails to enabled, we want to roll back the whole thing as best we can
                for sampleType in enabled {
                    try? await disableBackgroundDelivery(for: sampleType)
                }
                throw error
            }
        }
        self.execute(observerQuery)
        return .init(healthStore: self, query: observerQuery)
    }
}


extension HKHealthStore {
    private static let backgroundDeliveryOperationsGate = AsyncSemaphore()
    nonisolated(unsafe) private static var backgroundObserverCounts: [HKObjectType: Int] = [:]
    
    
    func enableBackgroundDelivery(for objectType: HKObjectType) async throws {
        await Self.backgroundDeliveryOperationsGate.wait()
        defer {
            Self.backgroundDeliveryOperationsGate.signal()
        }
        if Self.backgroundObserverCounts[objectType, default: 0] > 0 {
            // already registered, we simply need to increcment the count.
            Self.backgroundObserverCounts[objectType, default: 0] += 1
            return
        }
        try await self.HealthKit::enableBackgroundDelivery(for: objectType, frequency: .immediate)
        Self.backgroundObserverCounts[objectType] = 1
    }
    
    
    func disableBackgroundDelivery(for objectType: HKObjectType) async throws {
        await Self.backgroundDeliveryOperationsGate.wait()
        defer {
            Self.backgroundDeliveryOperationsGate.signal()
        }
        let numActiveObservers = HKHealthStore.backgroundObserverCounts[objectType, default: 0]
        guard numActiveObservers > 0 else {
            return
        }
        if numActiveObservers == 1 {
            try await self.HealthKit::disableBackgroundDelivery(for: objectType)
        }
        HKHealthStore.backgroundObserverCounts[objectType] = numActiveObservers - 1
    }
}

#endif
