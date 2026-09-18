//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

// swiftlint:disable file_types_order

import Algorithms
import Grove
@testable import GroveHealthKit
@testable import GroveHealthKitBulkExport
import GroveLocalStorage
import GroveTesting
import HealthKit
import Synchronization
import Testing


@Suite
struct BulkExporterAPITests {
    @Test(arguments: [
        (99.0, 101.0, true, true), // Crosses the internal boundary.
        (-50.0, 50.0, true, false), // Crosses the export start.
        (150.0, 250.0, false, true), // Crosses the export end.
        (-50.0, 250.0, true, true), // Spans the complete export window.
        (25.0, 75.0, true, false),
        (125.0, 175.0, false, true),
        (-20.0, -1.0, false, false),
        (201.0, 250.0, false, false)
    ])
    func batchQueriesPreserveOverlappingSamples(start: Double, end: Double, first: Bool, second: Bool) {
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 1),
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end)
        )
        let firstRange = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 100)
        let secondRange = firstRange.upperBound..<Date(timeIntervalSince1970: 200)
        #expect(ExportBatch.samplePredicate(for: firstRange).evaluate(with: sample) == first)
        #expect(ExportBatch.samplePredicate(for: secondRange).evaluate(with: sample) == second)
    }

    @Test func batchingPreservesUnsplitQueryAfterDeduplication() {
        // Exact endpoints and instantaneous samples must follow HealthKit's own overlap semantics.
        let samples = [
            (-50.0, 50.0), (99.0, 101.0), (150.0, 250.0), (-50.0, 250.0),
            (0.0, 0.0), (100.0, 100.0), (200.0, 200.0),
            (-10.0, 0.0), (200.0, 210.0), (-20.0, -1.0), (201.0, 250.0)
        ].map { start, end in
            HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: 1),
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end)
            )
        }
        let first = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 100)
        let second = first.upperBound..<Date(timeIntervalSince1970: 200)
        let whole = HKQuery.predicateForSamples(withStart: first.lowerBound, end: second.upperBound, options: [])
        let expected = Set(samples.filter { whole.evaluate(with: $0) }.map(\.uuid))
        let occurrences = [first, second].flatMap { range in
            samples.filter { ExportBatch.samplePredicate(for: range).evaluate(with: $0) }
        }
        // A single synthetic participant/store: UUID is sufficient within this scope only.
        #expect(Set(occurrences.map(\.uuid)) == expected)
        #expect(occurrences.count > expected.count)
        #expect(expected.contains(samples[4].uuid)) // Instant at export start.
        #expect(expected.contains(samples[5].uuid)) // Instant at the internal boundary.
    }

    @Test
    func sessionStartDate() async throws {
        // we need to pass in the module, but for the input we're specifying it won't be accessed.
        let module = HealthKit()
        let cal = Calendar.current
        
        let endDate = try #require(cal.date(from: .init(year: 2025, month: 2, day: 11)))
        
        func startDate(for startDateDef: ExportSessionStartDate) async throws -> Date {
            try #require(await startDateDef.startDate(for: .heartRate, in: module, relativeTo: endDate))
        }
        
        do {
            let startDate = try await startDate(for: .last(numDays: 4))
            let expected = try #require(cal.date(from: .init(year: 2025, month: 2, day: 7)))
            #expect(startDate == expected)
        }
        do {
            let startDate = try await startDate(for: .last(numWeeks: 1))
            let expected = try #require(cal.date(from: .init(year: 2025, month: 2, day: 4)))
            #expect(startDate == expected)
        }
        do {
            let startDate = try await startDate(for: .last(numMonths: 2))
            let expected = try #require(cal.date(from: .init(year: 2024, month: 12, day: 11)))
            #expect(startDate == expected)
        }
        do {
            let startDate = try await startDate(for: .last(numYears: 3))
            let expected = try #require(cal.date(from: .init(year: 2022, month: 2, day: 11)))
            #expect(startDate == expected)
        }
        do {
            let startDate = try await startDate(for: .last(DateComponents(year: 2, month: 4)))
            let expected = try #require(cal.date(from: .init(year: 2022, month: 10, day: 11)))
            #expect(startDate == expected)
        }
    }
    
    
    @Test
    func sessionMgmt() async throws {
        let module = BulkHealthExporter(checkpointStorageSetting: .unencrypted())
        await withDependencyResolution(standard: TestStandard()) {
            module
        }
        #expect(await module.sessions.isEmpty)
        
        let sessionId = BulkExportSessionIdentifier(UUID().uuidString)
        let session = try await module.session(withId: sessionId, for: [], startDate: .oldestSample, using: .identity)
        
        let sessionsInModule: [any BulkExportSession] = await module.sessions
        let ourSession: [any BulkExportSession] = [session]
        #expect(sessionsInModule.elementsEqual(ourSession, by: { $0 == $1 }))
        let results = try await session.start()
        for await _ in results { }
        #expect(await session.state == .completed)
        #expect(await module.sessions.count == 1)
        #expect(await module.sessions.contains(where: { $0 == session }))
        try await module.deleteSessionRestorationInfo(for: sessionId)
        #expect(await session.state == .terminated)
        #expect(await module.sessions.isEmpty)
    }
    
    
    @Test(arguments: [false, true]) @MainActor
    func checkpointFailurePausesSessionAndRetryPersistsAgain(requestPause: Bool) async throws {
        let module = BulkHealthExporter(checkpointStorageSetting: .unencrypted())
        let healthKit = HealthKit()
        let storage = LocalStorage()
        await withDependencyResolution(standard: TestStandard()) { healthKit; storage; module }
        let sessionID = BulkExportSessionIdentifier(UUID().uuidString)
        let checkpointKey = LocalStorageKey<ExportSessionDescriptor>(BulkHealthExporter.localStorageKey(forSessionId: sessionID), setting: .unencrypted())
        defer { try? storage.delete(checkpointKey) }
        var descriptor = ExportSessionDescriptor(sessionId: sessionID, startDate: .absolute(.distantPast), endDate: .now)
        let batch = ExportBatch(sampleType: SampleType.stepCount, timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 1))
        descriptor.pendingBatches = [batch]
        descriptor.finishBatch(batch, result: .success(()))
        try storage.store(descriptor, for: checkpointKey)
        let fail = Mutex(true)
        let writes = Mutex(0)
        let persistence = SessionDescriptorPersisting { _ in
            writes.withLock { $0 += 1 }
            if fail.withLock({ $0 }) { throw CocoaError(.fileWriteOutOfSpace) }
        }
        let session = try await BulkExportSessionImpl(
            sessionId: sessionID,
            bulkExporter: module,
            healthKit: healthKit,
            sampleTypes: [],
            startDate: .absolute(.distantPast),
            endDate: .now,
            batchSize: .automatic,
            localStorage: storage,
            batchProcessor: IdentityBatchProcessor(),
            persistence: persistence
        )
        try module.add(session)
        #expect(session.state == .paused(reason: .notStarted))
        let results = try session.start(retryFailedBatches: true, concurrencyLevel: .disabled)
        if requestPause { await session.pause() }
        for await _ in results {
            Issue.record("Completed batches must not be reprocessed")
        }
        #expect(session.state == .paused(reason: .failure(.checkpointWriteFailed(CheckpointWriteFailure(CocoaError(.fileWriteOutOfSpace))))))
        #expect(session.failedBatches.isEmpty)
        #expect(session.pendingBatches.isEmpty)
        #expect(session.completedBatches.count == 1)
        let failedWrites = writes.withLock { $0 }
        fail.withLock { $0 = false }
        for await _ in try session.start(retryFailedBatches: true, concurrencyLevel: .disabled) {
            Issue.record("Checkpoint retry must not replay completed batches")
        }
        #expect(session.state == .completed)
        #expect(writes.withLock { $0 } > failedWrites)
        try await module.deleteSessionRestorationInfo(for: session.sessionId)
    }

    @Test @MainActor
    func pauseDrainsBeforeRestart() async throws {
        let module = BulkHealthExporter(checkpointStorageSetting: .unencrypted())
        await withDependencyResolution(standard: TestStandard()) { module }
        let sessionId = BulkExportSessionIdentifier(UUID().uuidString)
        let session = try await module.session(withId: sessionId, for: [], startDate: .oldestSample, using: .identity)
        let firstRun = try session.start()
        await session.pause()
        for await _ in firstRun { }
        #expect(session.state == .paused(reason: .requested) || session.state == .completed)
        let secondRun = try session.start()
        for await _ in secondRun { }
        #expect(session.state == .completed)
        try await module.deleteSessionRestorationInfo(for: sessionId)
        #expect(session.state == .terminated)
        #expect(module.sessions.isEmpty)
        let replacement = try await module.session(withId: sessionId, for: [], startDate: .oldestSample, using: .identity)
        #expect(replacement !== session)
        try await module.deleteSessionRestorationInfo(for: sessionId)
    }


    @Test
    func exportBatchTimeRanges() async throws { // swiftlint:disable:this function_body_length
        let cal = Calendar.current
        let healthKit = HealthKit()
        let bulkExporter = BulkHealthExporter(checkpointStorageSetting: .unencrypted())
        await withDependencyResolution(standard: TestStandard()) {
            healthKit
            bulkExporter
        }
        #expect(await bulkExporter.sessions.isEmpty)
        
        func makeDate(_ year: Int, _ month: Int, _ day: Int, location: SourceLocation = #_sourceLocation) throws -> Date {
            try #require(cal.date(from: .init(year: year, month: month, day: day)), sourceLocation: location)
        }
        
        // needed to support running the test in both locales that start the week on monday and on sunday.
        // the test case below assumes monday as start of week.
        let dayAdj = -(2 - cal.firstWeekday)
        
        var sessionDescriptor = ExportSessionDescriptor(
            sessionId: .init(UUID().uuidString),
            startDate: .last(.init(month: 6)),
            endDate: try makeDate(2025, 7, 24)
        )
        #expect(sessionDescriptor.pendingBatches.isEmpty)
        #expect(sessionDescriptor.completedBatches.isEmpty)
        #expect(try await sessionDescriptor.startDate.startDate(
            for: SampleType.heartRate,
            in: healthKit,
            relativeTo: sessionDescriptor.endDate
        ) == makeDate(2025, 1, 24))
        #expect(try cal.startOfWeek(for: makeDate(2025, 1, 24)) == makeDate(2025, 1, 20 + dayAdj))
        #expect(try cal.start(of: .week, for: makeDate(2025, 1, 24)) == makeDate(2025, 1, 20 + dayAdj))
        
        func batches(for sampleType: SampleType<some Any>) -> [ExportBatch] {
            sessionDescriptor.pendingBatches.filter { $0.sampleType == sampleType }
        }
        // add some export batches
        await sessionDescriptor.add(sampleType: SampleType.heartRate, batchSize: .byMonth, healthKit: healthKit)
        let heartRateExportBatches = batches(for: .heartRate)
        #expect(heartRateExportBatches.count == 7)
        // adding the same input again shouldn't affect anything
        await sessionDescriptor.add(sampleType: SampleType.heartRate, batchSize: .byMonth, healthKit: healthKit)
        #expect(batches(for: .heartRate) == heartRateExportBatches)
        #expect(heartRateExportBatches == [
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 1, 24)..<makeDate(2025, 2, 1)),
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 2, 1)..<makeDate(2025, 3, 1)),
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 3, 1)..<makeDate(2025, 4, 1)),
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 4, 1)..<makeDate(2025, 5, 1)),
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 5, 1)..<makeDate(2025, 6, 1)),
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 6, 1)..<makeDate(2025, 7, 1)),
            .init(sampleType: SampleType.heartRate, timeRange: try makeDate(2025, 7, 1)..<makeDate(2025, 7, 24))
        ])
        
        await sessionDescriptor.add(sampleType: .activeEnergyBurned, batchSize: .calendarComponent(.week, multiplier: 2), healthKit: healthKit)
        #expect(batches(for: .activeEnergyBurned).count == 14)
        #expect(batches(for: .activeEnergyBurned).starts(with: [
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 1, 24)..<makeDate(2025, 2, 3 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 2, 3 + dayAdj)..<makeDate(2025, 2, 17 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 2, 17 + dayAdj)..<makeDate(2025, 3, 3 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 3, 3 + dayAdj)..<makeDate(2025, 3, 17 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 3, 17 + dayAdj)..<makeDate(2025, 3, 31 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 3, 31 + dayAdj)..<makeDate(2025, 4, 14 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 4, 14 + dayAdj)..<makeDate(2025, 4, 28 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 4, 28 + dayAdj)..<makeDate(2025, 5, 12 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 5, 12 + dayAdj)..<makeDate(2025, 5, 26 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 5, 26 + dayAdj)..<makeDate(2025, 6, 9 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 6, 9 + dayAdj)..<makeDate(2025, 6, 23 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 6, 23 + dayAdj)..<makeDate(2025, 7, 7 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 7, 7 + dayAdj)..<makeDate(2025, 7, 21 + dayAdj)),
            .init(sampleType: SampleType.activeEnergyBurned, timeRange: try makeDate(2025, 7, 21 + dayAdj)..<makeDate(2025, 7, 24))
        ]))
    }
}


private actor TestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) {
        // ...
    }
    
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) {
        // ...
    }
}

#endif
