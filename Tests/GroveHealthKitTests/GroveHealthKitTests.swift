//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

@testable import GroveHealthKit
import GroveHealthKitUI
import HealthKit
import Synchronization
import Testing


private actor ObserverProcessingGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while !entered {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}


@Suite("GroveHealthKitTests")
struct GroveHealthKitTests {
    @Test("Equal Time Ranges")
    func equalTimeRanges() {
        #expect(HealthKitQueryTimeRange.last(hours: 1) == .currentHour)
        #expect(HealthKitQueryTimeRange.last(days: 1) == .today)
        #expect(HealthKitQueryTimeRange.last(weeks: 1) == .currentWeek)
        #expect(HealthKitQueryTimeRange.last(months: 1) == .currentMonth)
        #expect(HealthKitQueryTimeRange.last(years: 1) == .currentYear)
    }

    @Test("Equal Well Known Identifiers")
    func equalWellKnownIdentifiers() {
        #expect(HKQuantityType.allKnownQuantities.count == HKQuantityTypeIdentifier.allKnownIdentifiers.count)
        #expect(HKCorrelationType.allKnownCorrelations.count == HKCorrelationTypeIdentifier.allKnownIdentifiers.count)
        #expect(HKCategoryType.allKnownCategories.count == HKCategoryTypeIdentifier.allKnownIdentifiers.count)
        #expect(HKObjectType.allKnownObjectTypes.count == 214)
    }

    @Test("Background delivery ownership preserves failed teardown for an exact retry")
    func backgroundDeliveryDisableFailureIsRetried() throws {
        let heartRate = try #require(HKObjectType.quantityType(forIdentifier: .heartRate))
        var ownership = HKHealthStore.BackgroundDeliveryOwnership()

        ownership.didEnable(heartRate)
        ownership.didEnable(heartRate)
        #expect(ownership.active[heartRate] == 2)
        #expect(ownership.requestDisable(for: [heartRate]).isEmpty)
        #expect(ownership.active[heartRate] == 1)

        let firstSDKDisable = ownership.requestDisable(for: [heartRate])
        #expect(firstSDKDisable == [heartRate])
        #expect(ownership.active[heartRate] == nil)
        #expect(ownership.pendingDisables == [heartRate])

        // The SDK call failed: deliberately do not mark it complete. A later teardown retries the
        // exact type, but no departed local owner is resurrected and no duplicate owner appears.
        #expect(ownership.requestDisable(for: [heartRate]) == [heartRate])
        #expect(ownership.active[heartRate] == nil)
        #expect(ownership.didDisable(heartRate) == .completed)
        #expect(ownership.pendingDisables.isEmpty)
        #expect(ownership.requestDisable(for: [heartRate]).isEmpty)
    }

    @MainActor
    @Test("A failed SDK background-delivery operation retries automatically")
    func backgroundDeliveryOperationRetriesAutomatically() async {
        enum ExpectedFailure: Error {
            case firstAttempt
        }
        var attempts = 0
        var waits = 0
        let completed = await HKHealthStore.retryBackgroundDeliveryOperation(
            shouldContinue: { true },
            operation: {
                attempts += 1
                if attempts == 1 {
                    throw ExpectedFailure.firstAttempt
                }
            },
            waitBeforeRetry: { _ in
                waits += 1
                return true
            },
            onFailure: { _, _ in }
        )

        #expect(completed)
        #expect(attempts == 2)
        #expect(waits == 1)
    }

    @MainActor
    @Test("A new owner supersedes an in-flight disable and triggers restoration")
    func backgroundDeliveryReenableRaceRestoresDelivery() async throws {
        let heartRate = try #require(HKObjectType.quantityType(forIdentifier: .heartRate))
        var ownership = HKHealthStore.BackgroundDeliveryOwnership()
        ownership.didEnable(heartRate)
        #expect(ownership.requestDisable(for: [heartRate]) == [heartRate])

        let disabled = await HKHealthStore.retryBackgroundDeliveryOperation(
            shouldContinue: { ownership.needsDisable(heartRate) },
            operation: {
                // Models a new owner completing SDK enable while the old disable is suspended.
                ownership.didEnable(heartRate)
            },
            waitBeforeRetry: { _ in true },
            onFailure: { _, _ in }
        )
        #expect(disabled)
        #expect(ownership.didDisable(heartRate) == .supersededByOwner)

        var restorations = 0
        let restored = await HKHealthStore.retryBackgroundDeliveryOperation(
            shouldContinue: { ownership.hasActiveOwner(heartRate) },
            operation: { restorations += 1 },
            waitBeforeRetry: { _ in true },
            onFailure: { _, _ in }
        )
        #expect(restored)
        #expect(restorations == 1)
        #expect(ownership.active[heartRate] == 1)
        #expect(ownership.pendingDisables.isEmpty)
    }


    @Test("Query anchors codable", arguments: [
        QueryAnchor(HKQueryAnchor(fromValue: 5734987678924)),
        QueryAnchor()
    ])
    func equalQueryAnchorCoding2(_ anchor: QueryAnchor) throws {
        let encoded = try JSONEncoder().encode(anchor)
        let decoded = try JSONDecoder().decode(QueryAnchor.self, from: encoded)
        #expect(anchor == decoded)
    }
    
    @Test
    func sourceFilter() throws {
        typealias Filter = HealthKit.SourceFilter
        
        let healthAppSource = try #require(HKSource.make(name: "Health", bundleId: "com.apple.health"))
        let appleWatchSource = try #require(HKSource.make(
            name: "Lukas' Apple Watch",
            bundleId: "com.apple.health.94C8E349-0D09-4184-BF6C-AF11692FA465"
        ))
        let autoSleepSource = try #require(HKSource.make(name: "AutoSleep", bundleId: "com.tantsissa.AutoSleep"))
        
        #expect(Filter.any.matches(healthAppSource))
        #expect(Filter.any.matches(appleWatchSource))
        #expect(Filter.any.matches(autoSleepSource))
        
        #expect(Filter.healthApp.matches(healthAppSource))
        #expect(!Filter.healthApp.matches(appleWatchSource))
        #expect(!Filter.healthApp.matches(autoSleepSource))
        
        let appleHealthSystemFilter = Filter.bundleId(beginsWith: "com.apple.health")
        #expect(appleHealthSystemFilter.matches(healthAppSource))
        #expect(appleHealthSystemFilter.matches(appleWatchSource))
        #expect(!appleHealthSystemFilter.matches(autoSleepSource))
    }

    @Test("Observer completion is exactly once, including rejected delivery")
    func observerCompletionIsExactlyOnce() async {
        let deliveredCount = Mutex(0)
        let delivered = HKHealthStore.ObserverQueryCompletion {
            deliveredCount.withLock { $0 += 1 }
        }
        let activeTracker = HKHealthStore.BackgroundDeliveryTaskTracker()
        activeTracker.scheduleAcknowledging(delivered) {}
        await activeTracker.cancelAndWait()
        delivered.call()
        #expect(deliveredCount.withLock { $0 } == 1)

        let rejectedCount = Mutex(0)
        let rejected = HKHealthStore.ObserverQueryCompletion {
            rejectedCount.withLock { $0 += 1 }
        }
        let invalidatedTracker = HKHealthStore.BackgroundDeliveryTaskTracker()
        await invalidatedTracker.cancelAndWait()
        invalidatedTracker.scheduleAcknowledging(rejected) {}
        rejected.call()
        #expect(rejectedCount.withLock { $0 } == 1)
    }

    @Test("Observer completion waits for the processing attempt")
    func observerCompletionWaitsForProcessing() async {
        let completionCount = Mutex(0)
        let completion = HKHealthStore.ObserverQueryCompletion {
            completionCount.withLock { $0 += 1 }
        }
        let tracker = HKHealthStore.BackgroundDeliveryTaskTracker()
        let processing = ObserverProcessingGate()

        tracker.scheduleAcknowledging(completion) {
            await processing.suspend()
        }
        await processing.waitUntilEntered()
        #expect(completionCount.withLock { $0 } == 0)

        await processing.release()
        await tracker.cancelAndWait()
        #expect(completionCount.withLock { $0 } == 1)
    }
}


extension HKSource {
    static func make(name: String, bundleId: String) -> HKSource? {
        // +(id)_sourceWithBundleIdentifier:(id)arg1 name:(id)arg2 productType:(id)arg3 options:(unsigned long long)arg4
        let sel = Selector(("_sourceWithBundleIdentifier:name:productType:options:"))
        guard let method = class_getClassMethod(self, sel) else {
            return nil
        }
        let imp = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (HKSource.Type, Selector, NSString, NSString, NSString, UInt64) -> HKSource).self
        )
        return imp(self, sel, bundleId as NSString, name as NSString, NSString(), 0)
    }
}

#endif
