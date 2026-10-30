//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import Grove
@testable import GroveHealthKit
import GroveTesting
import HealthKit
import Testing

private actor TestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample>,
        ofType sampleType: SampleType<Sample>
    ) async -> HealthKitAnchorCommitAction? {
        nil
    }
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject>,
        ofType sampleType: SampleType<Sample>,
        deletedAfter: Date?
    ) async -> HealthKitAnchorCommitAction? {
        nil
    }
}

private actor DeletionBoundRecorder: Standard, HealthKitConstraint {
    private(set) var bounds: [Date?] = []

    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample>,
        ofType sampleType: SampleType<Sample>
    ) async -> HealthKitAnchorCommitAction? {
        nil
    }

    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject>,
        ofType sampleType: SampleType<Sample>,
        deletedAfter: Date?
    ) async -> HealthKitAnchorCommitAction? {
        bounds.append(deletedAfter)
        return nil
    }
}

extension GroveHealthKitTests {
    private enum StartDateStorageError: Error {
        case unavailable
    }

    @Test("A failed initial collection-boundary write aborts resolution")
    func failedCollectionStartWriteIsNotIgnored() throws {
        let now = Date(timeIntervalSinceReferenceDate: 123_456)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(throws: StartDateStorageError.unavailable) {
            _ = try CollectSamples<HKQuantitySample>.resolveTimeRange(
                .newSamples,
                now: now,
                calendar: calendar,
                load: { nil },
                store: { _ in throw StartDateStorageError.unavailable }
            )
        }
    }

    @MainActor
    @Test("Each deletion batch follows the query that produced its starting anchor")
    func deletionLowerBound() async throws {
        let standard = DeletionBoundRecorder()
        let healthKit = HealthKit()
        await withDependencyResolution(standard: standard) {
            healthKit
        }
        let collector = HealthKitSampleCollector(
            source: .collectSamples,
            healthKit: healthKit,
            standard: standard,
            sampleType: .heartRate,
            timeRange: .ever,
            predicate: nil,
            deliverySetting: HealthDataCollectorDeliverySetting(startSetting: .manual, continueInBackground: false)
        )
        let added: [HKQuantitySample] = []
        let deleted = [try #require(HKDeletedObject.make())]
        try healthKit.queryAnchors.store(nil, for: .heartRate)
        defer { try? healthKit.queryAnchors.store(nil, for: .heartRate) }

        // Single-object queries start from the persisted anchor.
        let firstQuery = Date.now
        try await collector.commit(added: added, deleted: deleted, from: nil, to: HKQueryAnchor(fromValue: 1), queriedAt: firstQuery)
        let persisted = try healthKit.queryAnchors.load(for: .heartRate)
        #expect(persisted?.queriedAt == firstQuery)
        try await collector.commit(
            added: added,
            deleted: deleted,
            from: persisted,
            to: HKQueryAnchor(fromValue: 2),
            queriedAt: firstQuery.addingTimeInterval(60)
        )

        // A reset clears the bound; each continuous update then starts from the one before it.
        try healthKit.queryAnchors.store(nil, for: .heartRate)
        let streamStart = Date.now
        var expected: QueryAnchor?
        for value in 3...5 {
            expected = try await collector.commit(
                added: added,
                deleted: deleted,
                from: expected,
                to: HKQueryAnchor(fromValue: value),
                queriedAt: streamStart
            )
        }
        #expect(try healthKit.queryAnchors.load(for: .heartRate) == expected)
        #expect(await standard.bounds == [nil, firstQuery, nil, streamStart, streamStart])

        await #expect(throws: (any Error).self) {
            try await collector.commit(added: added, deleted: deleted, from: persisted, to: nil, queriedAt: .now)
        }
        #expect(try healthKit.queryAnchors.load(for: .heartRate) == expected)
    }

    @Test("Collect Samples Registration Deduplication")
    func collectSamplesRegistrationDeduplication() async throws {
        let healthKit = HealthKit {
            CollectSamples(.stepCount, continueInBackground: false)
            CollectSamples(.heartRate)
            CollectSamples(.heartRate)
            CollectSamples(.stepCount, continueInBackground: false)
            CollectSamples(.stepCount, continueInBackground: true)
            CollectSamples(.bloodGlucose, continueInBackground: false)
            CollectSamples(.bloodGlucose, continueInBackground: true)
            CollectSamples(.dietaryPotassium, continueInBackground: true)
            CollectSamples(.dietaryPotassium, continueInBackground: false)
            CollectSamples(.pushCount)
            CollectSamples(.pushCount)
        }
        await withDependencyResolution(standard: TestStandard()) {
            healthKit
        }

        while healthKit.configurationState != .completed {
            try await Task.sleep(for: .seconds(1))
        }

        var erasedCollectors: [AnyObject] = healthKit.registeredDataCollectors

        #expect(healthKit.registeredDataCollectors.count == 5)
        #expect(
            Set(healthKit.registeredDataCollectors.map { $0.typeErasedSampleType.displayTitle }) ==
            [SampleType.heartRate, .stepCount, .bloodGlucose, .dietaryPotassium, .pushCount].mapIntoSet(\.displayTitle)
        )

        await healthKit.addHealthDataCollector(CollectSamples(.bloodOxygen))
        #expect(healthKit.registeredDataCollectors.count == 6)

        erasedCollectors = healthKit.registeredDataCollectors
        await healthKit.addHealthDataCollector(CollectSamples(.bloodOxygen))
        #expect(erasedCollectors.elementsEqual(healthKit.registeredDataCollectors, by: ===))
        #expect(healthKit.registeredDataCollectors.count == 6)

        await healthKit.addHealthDataCollector(CollectSamples(.walkingStepLength, continueInBackground: true))
        #expect(healthKit.registeredDataCollectors.count == 7)
        erasedCollectors = healthKit.registeredDataCollectors
        await healthKit.addHealthDataCollector(CollectSamples(.walkingStepLength, continueInBackground: true))
        // nothing should change, since the new collector is equal to an existing one.
        #expect(healthKit.registeredDataCollectors.count == 7)
        #expect(erasedCollectors.elementsEqual(healthKit.registeredDataCollectors, by: ===))
        await healthKit.addHealthDataCollector(CollectSamples(.walkingStepLength, continueInBackground: false))
        // nothing should change, since the new (non-bg) collector will get subsumed into the existing (bg) one.
        #expect(healthKit.registeredDataCollectors.count == 7)
        #expect(erasedCollectors.elementsEqual(healthKit.registeredDataCollectors, by: ===))

        await healthKit.addHealthDataCollector(CollectSamples(.height, continueInBackground: false))
        #expect(healthKit.registeredDataCollectors.count == 8)
        erasedCollectors = healthKit.registeredDataCollectors
        await healthKit.addHealthDataCollector(CollectSamples(.height, continueInBackground: true))
        // we expect the second height collector to replace the first (background vs non-background),
        // so the #collectors will remain the same, but they won't compare equal anymore
        #expect(healthKit.registeredDataCollectors.count == 8)
        #expect(erasedCollectors.elementsEqual(healthKit.registeredDataCollectors, by: ===) == false)
    }
}

#endif
