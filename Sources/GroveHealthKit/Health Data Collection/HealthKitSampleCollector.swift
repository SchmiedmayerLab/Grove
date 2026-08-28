//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Grove
import GroveFoundation
import HealthKit
import OSLog
import SwiftUI

// Query/consumer/anchor commit remain together so the acknowledgement boundary is auditable.
// swiftlint:disable closure_body_length function_body_length type_body_length

@available(iOS 18, macOS 15, watchOS 11, *)
final class HealthKitSampleCollector<Sample: _HKSampleWithSampleType>: HealthDataCollector {
    private enum AnchorCommitError: Error {
        case staleAnchor
    }

    /// How this ``HealthKitSampleCollector`` was created, i.e. what it was created for.
    ///
    /// The reason why this type exists is that in the case of the ``CollectSamples`` API specifically,
    /// we want to offer the ability to reset the underlying anchor and start date, which requires us to have the ability to stop a collector.
    /// Should GroveHealthKit, at some point in the future, start registering additional sample collectors, we'd end up accidentally disabling those as well
    /// when we really just want to disable the ``CollectSamples``-associated ones.
    enum Source {
        /// This instance of the ``HealthKitSampleCollector`` was created by a ``CollectSamples`` instance.
        case collectSamples
    }
    
    private enum QueryVariant {
        case anchorQuery(Task<Void, Never>)
        case backgroundDelivery(HKHealthStore.BackgroundObserverQueryInvalidator)
    }
    
    let source: Source
    // This needs to be unowned since the HealthKit module will establish a strong reference to the data source.
    private unowned let healthKit: HealthKit
    private let standard: any HealthKitConstraint
    
    let sampleType: SampleType<Sample>
    private let timeRange: HealthKitQueryTimeRange
    private let predicate: NSPredicate?
    let deliverySetting: HealthDataCollectorDeliverySetting
    @MainActor private(set) var isActive = false
    private var queryVariant: QueryVariant?
    private var backgroundRetryTask: Task<Void, Never>?
    private var backgroundRetryRequested = false
    private let querySerialization = AsyncSemaphore(value: 1)
    
    private var healthStore: HKHealthStore { healthKit.healthStore }
    

    required init(
        source: Source,
        healthKit: HealthKit,
        standard: any HealthKitConstraint,
        sampleType: SampleType<Sample>,
        timeRange: HealthKitQueryTimeRange,
        predicate: NSPredicate?,
        deliverySetting: HealthDataCollectorDeliverySetting
    ) {
        self.source = source
        self.healthKit = healthKit
        self.standard = standard
        self.sampleType = sampleType
        self.deliverySetting = deliverySetting
        self.timeRange = timeRange.adjustedToWholeMinute()
        self.predicate = predicate
    }
    

    @MainActor
    func startDataCollection() async {
        guard !isActive else {
            return
        }
        let logger = healthKit.logger
        isActive = true
        do {
            if deliverySetting.continueInBackground {
                // set up a background query
                let queryInvalidator = try await healthStore.startBackgroundDelivery(for: [sampleType.hkSampleType]) { [weak self] result in
                    guard let self, self.isActive else {
                        // if the sample collector has been turned off, we don't want to process these.
                        return
                    }
                    await self.handleBackgroundDelivery(result, logger: logger)
                }
                guard isActive else {
                    await queryInvalidator.invalidateAndWait()
                    await healthStore.disableBackgroundDelivery(for: [sampleType.hkSampleType])
                    return
                }
                queryVariant = .backgroundDelivery(queryInvalidator)
            } else {
                // set up a non-background query
                try await anchoredContinuousObjectQuery()
            }
        } catch {
            isActive = false
            logger.error(
                "HealthKit data collection failed; error type: \(String(reflecting: type(of: error)), privacy: .public)"
            )
        }
    }


    @MainActor
    private func handleBackgroundDelivery(
        _ result: Result<Set<HKSampleType>, any Error>,
        logger: Logger
    ) async {
        switch result {
        case .failure(let error):
            logger.error(
                "HealthKit background delivery failed; error type: \(String(reflecting: type(of: error)), privacy: .public)"
            )
        case .success(let sampleTypes):
            guard !sampleTypes.isEmpty else {
                return
            }
            let expectedSampleTypes = sampleType.effectiveSampleTypesForAuthentication.compactMapIntoSet { $0.hkSampleType }
            guard !sampleTypes.isDisjoint(with: expectedSampleTypes) else {
                logger.warning(
                    "Received Observation query types (\(sampleTypes)) are not corresponding to the CollectSamples type \(self.sampleType.hkSampleType)"
                )
                return
            }
            do {
                // The observer completion is invoked by the wrapper only after this handler returns.
                // Perform one anchored fetch, durable consumer handoff, and anchor CAS while
                // HealthKit grants background execution; scheduling a later task can suspend first.
                try await anchoredSingleObjectQuery()
            } catch is CancellationError {
                return
            } catch {
                logger.error(
                    "Observer delivery was retained for retry; error type: \(String(reflecting: type(of: error)), privacy: .public)"
                )
                startBackgroundRetryIfNeeded()
            }
        }
    }
    
    
    @MainActor
    func stopDataCollection() async {
        guard isActive else {
            return
        }
        isActive = false
        switch exchange(&queryVariant, with: nil) {
        case nil:
            break
        case .anchorQuery(let task):
            task.cancel()
            _ = await task.result
        case .backgroundDelivery(let invalidator):
            await invalidator.invalidateAndWait()
            await healthStore.disableBackgroundDelivery(for: [sampleType.hkSampleType])
        }
        let backgroundRetryTask = exchange(&backgroundRetryTask, with: nil)
        backgroundRetryRequested = false
        backgroundRetryTask?.cancel()
        _ = await backgroundRetryTask?.result
        // Fence reset/removal against a callback which entered immediately before invalidation.
        // This wait is intentionally not cancellation-sensitive: returning before the in-flight query
        // exits would let its anchor compare/exchange restore the cursor after reset.
        await querySerialization.wait()
        querySerialization.signal()
    }


    @MainActor
    private func startBackgroundRetryIfNeeded() {
        backgroundRetryRequested = true
        guard isActive, backgroundRetryTask == nil else {
            return
        }
        backgroundRetryTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { self.backgroundRetryTask = nil }
            var retryDelay = Duration.seconds(1)
            while self.isActive, !Task.isCancelled {
                self.backgroundRetryRequested = false
                do {
                    try await self.anchoredSingleObjectQuery()
                    guard self.backgroundRetryRequested else {
                        return
                    }
                    retryDelay = .seconds(1)
                } catch is CancellationError {
                    return
                } catch {
                    self.backgroundRetryRequested = true
                    self.healthKit.logger.error(
                        "HealthKit background retry retained its anchor; error type: \(String(reflecting: type(of: error)), privacy: .public)"
                    )
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, .seconds(60))
                }
            }
        }
    }


    @MainActor
    private func anchoredSingleObjectQuery() async throws {
        try await querySerialization.waitCheckingCancellation()
        defer { querySerialization.signal() }
        guard isActive else {
            throw CancellationError()
        }

        let persistedAnchor = try healthKit.queryAnchors.load(for: sampleType)
        var anchor = persistedAnchor ?? QueryAnchor()
        nonisolated(unsafe) let predicate = self.predicate
        let (added, deleted) = try await healthKit.query(
            sampleType,
            timeRange: timeRange,
            anchor: &anchor,
            predicate: predicate
        )
        try await handleQueryResult(added: added, deleted: deleted)
        guard try healthKit.queryAnchors.compareExchange(
            expected: persistedAnchor,
            desired: anchor,
            for: sampleType
        ) else {
            // Another callback committed from the same cursor while this actor was suspended.
            // Retrying is safe because the consumer must stage exact duplicates idempotently.
            throw AnchorCommitError.staleAnchor
        }
    }

    
    @MainActor
    private func anchoredContinuousObjectQuery() async throws {
        let task = Task {
            var retryDelay = Duration.seconds(1)
            while !Task.isCancelled {
                let persistedAnchor: QueryAnchor?
                do {
                    persistedAnchor = try healthKit.queryAnchors.load(for: sampleType)
                } catch {
                    healthKit.logger.error(
                        "HealthKit query-anchor load failed; error type: \(String(reflecting: type(of: error)), privacy: .public)"
                    )
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, .seconds(60))
                    continue
                }
                let samplePredicate = sampleType._makeSamplePredicate(
                    filter: NSCompoundPredicate(
                        andPredicateWithSubpredicates: [timeRange.predicate, predicate].compactMap(\.self)
                    )
                )
                let queryDescriptor = HKAnchoredObjectQueryDescriptor(
                    predicates: [samplePredicate],
                    anchor: persistedAnchor?.hkAnchor
                )
                do {
                    var expectedAnchor = persistedAnchor
                    for try await update in queryDescriptor.results(for: healthStore) {
                        guard isActive, !Task.isCancelled else {
                            return
                        }
                        try await handleQueryResult(added: update.addedSamples, deleted: update.deletedObjects)
                        let newAnchor = QueryAnchor(update.newAnchor)
                        guard try healthKit.queryAnchors.compareExchange(
                            expected: expectedAnchor,
                            desired: newAnchor,
                            for: sampleType
                        ) else {
                            throw AnchorCommitError.staleAnchor
                        }
                        expectedAnchor = newAnchor
                        retryDelay = .seconds(1)
                    }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    healthKit.logger.error(
                        "HealthKit continuous delivery retained its anchor; error type: \(String(reflecting: type(of: error)), privacy: .public)"
                    )
                    guard isActive, !Task.isCancelled else {
                        return
                    }
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, .seconds(60))
                }
            }
        }
        queryVariant = .anchorQuery(task)
    }
    
    
    @MainActor
    private func handleQueryResult(
        added: some Collection<Sample> & Sendable,
        deleted: some Collection<HKDeletedObject> & Sendable
    ) async throws {
        if !added.isEmpty {
            try await standard.handleNewSamples(added, ofType: sampleType)
        }
        // An anchored delta may contain a sample that was both created and deleted between
        // checkpoints. Stage additions first so the deletion can atomically elide/tombstone the
        // never-published graph; the anchor still advances only after both callbacks succeed.
        if !deleted.isEmpty {
            try await standard.handleDeletedObjects(deleted, ofType: sampleType)
        }
    }
}


extension HealthKitQueryTimeRange {
    /// Returns a new ``HealthKitQueryTimeRange``, with all components from the second down set to 0, and the minute rounded away from the current date.
    ///
    /// The purpose here is that we want to start the data collection at the previous full minute mark,
    /// to make it deterministic to manually entered data in HealthKit.
    func adjustedToWholeMinute() -> Self {
        let cal = Calendar.current
        func imp(_ date: Date) -> Date {
            var components = cal.dateComponents(in: .current, from: date)
            components.second = 0
            components.nanosecond = 0
            if date > .now {
                components.minute = (components.minute ?? 0) + 1
            }
            if let date = cal.date(from: components) {
                return date
            } else {
                preconditionFailure("Unable to compute date")
            }
        }
        return Self(imp(range.lowerBound)...imp(range.upperBound))
    }
}

#endif
