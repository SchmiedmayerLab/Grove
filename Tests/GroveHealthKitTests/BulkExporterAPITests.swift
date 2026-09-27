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
    @MainActor
    @Test
    func batchTransitionsPersistOnlyCompleteSnapshots() throws {
        let endDate = Date.now
        let batch = ExportBatch(
            sampleType: SampleType.stepCount,
            timeRange: endDate.addingTimeInterval(-60)..<endDate
        )
        let recorder = DescriptorMutationRecorder(
            descriptor: ExportSessionDescriptor(
                sessionId: .init("snapshot-test"),
                startDate: .oldestSample,
                endDate: endDate
            )
        )
        recorder.descriptor.pendingBatches = [batch]
        recorder.snapshots.removeAll()

        recorder.descriptor.finishBatch(batch, result: .success(()), cancellationWasRequested: false)

        try #require(recorder.snapshots.count == 1)
        let snapshot = recorder.snapshots[0]
        #expect(snapshot.pendingBatches.isEmpty)
        #expect(snapshot.completedBatches.count == 1)
        #expect(snapshot.completedBatches[0].result == .success)
    }


    @Test
    func descriptorPersistenceFlushPreservesMutationOrder() async throws {
        let persistedSessionIds = Mutex<[String]>([])
        let persister = SessionDescriptorPersisting { descriptor in
            persistedSessionIds.withLock {
                $0.append(descriptor.sessionId.rawValue)
            }
        }
        for index in 0..<20 {
            let descriptor = ExportSessionDescriptor(
                sessionId: .init(String(index)),
                startDate: .oldestSample,
                endDate: .now
            )
            persister(descriptor)
        }

        try await persister.flush()

        #expect(persistedSessionIds.withLock { $0 } == (0..<20).map(String.init))
    }


    @Test
    func descriptorPersistenceRecoversAfterFailedWrite() async throws {
        let attempts = Mutex(0)
        let persistedDescriptors = Mutex<[ExportSessionDescriptor]>([])
        let persister = SessionDescriptorPersisting { descriptor in
            let attempt = attempts.withLock { attempts in
                attempts += 1
                return attempts
            }
            if attempt == 1 {
                throw PersistenceTestError.injected
            }
            persistedDescriptors.withLock {
                $0.append(descriptor)
            }
        }
        let failedDescriptor = ExportSessionDescriptor(
            sessionId: .init("failed-write"),
            startDate: .oldestSample,
            endDate: .now
        )
        let recoveredDescriptor = ExportSessionDescriptor(
            sessionId: .init("recovered-write"),
            startDate: .oldestSample,
            endDate: .now
        )

        let failedWrite = persister(failedDescriptor)
        let recoveredWrite = persister(recoveredDescriptor)

        do {
            try await failedWrite.value
            Issue.record("Expected the first descriptor write to fail")
        } catch {
            #expect(error is PersistenceTestError)
        }
        try await recoveredWrite.value

        let persisted = persistedDescriptors.withLock { $0 }
        try #require(persisted.count == 1)
        let persistedDescriptor = persisted[0]
        #expect(persistedDescriptor.sessionId == recoveredDescriptor.sessionId)
    }


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
        descriptor.finishBatch(batch, result: .success(()), cancellationWasRequested: false)
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

    @Test(.timeLimit(.minutes(1))) @MainActor
    func checkpointRetryPublishesRetainedOutputsWithoutReprocessing() async throws {
        let outputs = [UUID(), UUID()]
        let processed = Mutex<[ExportBatch]>([])
        let acknowledged = Mutex<[UUID]>([])
        let durable = Mutex<Set<UUID>>([])
        let failCompletedWrites = Mutex(true)
        let persistence = SessionDescriptorPersisting { descriptor in
            if !descriptor.completedBatches.isEmpty && failCompletedWrites.withLock({ $0 }) {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            durable.withLock { values in
                values.formUnion(descriptor.completedBatches.map { output(for: $0, from: outputs) })
            }
        }
        let fixture = try await makeProcessingSession(
            batchCount: 2,
            persistence: persistence,
            processBatch: { batch in
                processed.withLock { $0.append(batch) }
                return output(for: batch, from: outputs)
            },
            didPersist: { value in
                #expect(durable.withLock { $0.contains(value) })
                acknowledged.withLock { $0.append(value) }
            }
        )

        let firstRun = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled))
        #expect(firstRun.isEmpty)
        #expect(fixture.session.state == checkpointFailureState)
        #expect(processed.withLock { $0 } == [fixture.batches[0]])
        #expect(fixture.session.completedBatches.count == 1)
        #expect(fixture.session.pendingBatches == [fixture.batches[1]])
        #expect(fixture.session.failedBatches.isEmpty)
        #expect(acknowledged.withLock { $0.isEmpty })

        // A failed resume cannot publish the held output or start the next batch.
        let failedResume = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled))
        #expect(failedResume.isEmpty)
        #expect(fixture.session.state == checkpointFailureState)
        #expect(processed.withLock { $0.count } == 1)
        #expect(acknowledged.withLock { $0.isEmpty })

        failCompletedWrites.withLock { $0 = false }
        let resumed = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled))
        #expect(resumed == outputs)
        #expect(processed.withLock { $0 } == fixture.batches)
        #expect(acknowledged.withLock { $0 } == outputs)
        #expect(fixture.session.state == .completed)

        let completedRestart = await collect(try fixture.session.start(retryFailedBatches: true, concurrencyLevel: .disabled))
        #expect(completedRestart.isEmpty)
        #expect(processed.withLock { $0.count } == 2)
        #expect(acknowledged.withLock { $0.count } == 2)
        try await fixture.module.deleteSessionRestorationInfo(for: fixture.session.sessionId)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func initialCheckpointFailurePreventsProcessing() async throws {
        let processed = Mutex(0)
        let acknowledged = Mutex(0)
        let fixture = try await makeProcessingSession(
            batchCount: 1,
            persistence: SessionDescriptorPersisting { _ in throw CocoaError(.fileWriteOutOfSpace) },
            processBatch: { _ in
                processed.withLock { $0 += 1 }
                return UUID()
            },
            didPersist: { _ in acknowledged.withLock { $0 += 1 } }
        )
        let results = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled))
        #expect(results.isEmpty)
        #expect(processed.withLock { $0 } == 0)
        #expect(acknowledged.withLock { $0 } == 0)
        #expect(fixture.session.pendingBatches == fixture.batches)
        #expect(fixture.session.state == checkpointFailureState)
        try await fixture.module.deleteSessionRestorationInfo(for: fixture.session.sessionId)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func laterSuccessfulCheckpointDoesNotClearFailureOrPublishHeldOutput() async throws {
        let outputs = [UUID(), UUID()]
        let processed = Mutex<[ExportBatch]>([])
        let acknowledged = Mutex<[UUID]>([])
        let durable = Mutex<Set<UUID>>([])
        let secondStarted = AsyncStream<Void>.makeStream()
        let firstWriteFailed = AsyncStream<Void>.makeStream()
        let persistence = SessionDescriptorPersisting { descriptor in
            if descriptor.completedBatches.count == 1 {
                firstWriteFailed.continuation.yield(())
                throw CocoaError(.fileWriteOutOfSpace)
            }
            durable.withLock { values in
                values.formUnion(descriptor.completedBatches.map { output(for: $0, from: outputs) })
            }
        }
        let fixture = try await makeProcessingSession(
            batchCount: 2,
            persistence: persistence,
            processBatch: { batch in
                processed.withLock { $0.append(batch) }
                if batch.timeRange.lowerBound == Date(timeIntervalSince1970: 0) {
                    // Both workers must be running before the first checkpoint can fail.
                    for await _ in secondStarted.stream { break }
                } else if batch.timeRange.lowerBound == Date(timeIntervalSince1970: 100) {
                    secondStarted.continuation.yield(())
                    for await _ in firstWriteFailed.stream { break }
                }
                return output(for: batch, from: outputs)
            },
            didPersist: { value in
                #expect(durable.withLock { $0.contains(value) })
                acknowledged.withLock { $0.append(value) }
            }
        )

        let firstRun = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .limit(2)))
        #expect(firstRun == [outputs[1]])
        #expect(acknowledged.withLock { $0 } == [outputs[1]])
        #expect(Set(processed.withLock { $0 }) == Set(fixture.batches))
        #expect(fixture.session.completedBatches.count == 2)
        #expect(fixture.session.pendingBatches.isEmpty)
        #expect(fixture.session.state == checkpointFailureState)

        let resumed = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled))
        #expect(resumed == [outputs[0]])
        #expect(processed.withLock { $0.count } == 2)
        #expect(acknowledged.withLock { $0 } == [outputs[1], outputs[0]])
        #expect(fixture.session.state == .completed)
        try await fixture.module.deleteSessionRestorationInfo(for: fixture.session.sessionId)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func terminationDiscardsUnpersistedOutputWithoutAcknowledging() async throws {
        let processed = Mutex(0)
        let acknowledged = Mutex(0)
        let fixture = try await makeProcessingSession(
            batchCount: 1,
            persistence: SessionDescriptorPersisting { descriptor in
                if !descriptor.completedBatches.isEmpty { throw CocoaError(.fileWriteOutOfSpace) }
            },
            processBatch: { _ in
                processed.withLock { $0 += 1 }
                return UUID()
            },
            didPersist: { _ in acknowledged.withLock { $0 += 1 } }
        )
        let results = await collect(try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled))
        #expect(results.isEmpty)
        #expect(processed.withLock { $0 } == 1)
        #expect(acknowledged.withLock { $0 } == 0)
        try await fixture.module.deleteSessionRestorationInfo(for: fixture.session.sessionId)
        #expect(fixture.session.state == .terminated)
        #expect(acknowledged.withLock { $0 } == 0)
        #expect(throws: StartSessionError.self) {
            try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled)
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func pauseCannotDowngradeInFlightTermination() async throws {
        let gate = ProcessingGate()
        let fixture = try await makeProcessingSession(
            batchCount: 1,
            persistence: SessionDescriptorPersisting { _ in },
            processBatch: { _ in
                await gate.suspend()
                throw CancellationError()
            },
            didPersist: { _ in Issue.record("Cancelled work must not be acknowledged") }
        )
        let results = try fixture.session.start(retryFailedBatches: false, concurrencyLevel: .disabled)
        await gate.waitUntilEntered()

        let terminationEntered = AsyncStream<Void>.makeStream()
        let termination = Task { @MainActor in
            terminationEntered.continuation.yield(())
            await fixture.session._terminate()
        }
        // The terminating task holds MainActor until _terminate suspends waiting for the worker.
        for await _ in terminationEntered.stream { break }
        let pauseEntered = AsyncStream<Void>.makeStream()
        let pause = Task { @MainActor in
            pauseEntered.continuation.yield(())
            await fixture.session.pause()
        }
        for await _ in pauseEntered.stream { break }
        await gate.release()
        await termination.value
        await pause.value

        let emitted = await collect(results)
        #expect(emitted.isEmpty)
        #expect(fixture.session.state == .terminated)
        #expect(fixture.module.sessions.isEmpty)
        #expect(fixture.session.pendingBatches == fixture.batches)
        #expect(fixture.session.failedBatches.isEmpty)
        try fixture.storage.delete(fixture.storageKey)
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


private var checkpointFailureState: BulkExportSessionState {
    .paused(reason: .failure(.checkpointWriteFailed(CheckpointWriteFailure(CocoaError(.fileWriteOutOfSpace)))))
}


private func output(for batch: ExportBatch, from outputs: [UUID]) -> UUID {
    outputs[Int(batch.timeRange.lowerBound.timeIntervalSince1970 / 100)]
}


private func collect(_ stream: AsyncStream<UUID>) async -> [UUID] {
    var values: [UUID] = []
    for await value in stream {
        values.append(value)
    }
    return values
}


private struct AcknowledgingBatchProcessor: BatchProcessor {
    let acknowledge: @Sendable (UUID) -> Void

    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) throws -> UUID {
        // These tests provide processBatch so HealthKit queries are never required.
        throw PersistenceTestError.injected
    }

    func didPersist(_ output: UUID) async {
        acknowledge(output)
    }
}


@MainActor
private final class ProcessingSessionFixture {
    let module: BulkHealthExporter
    let healthKit: HealthKit
    let storage: LocalStorage
    let storageKey: LocalStorageKey<ExportSessionDescriptor>
    let session: BulkExportSessionImpl<AcknowledgingBatchProcessor>
    let batches: [ExportBatch]

    init(
        module: BulkHealthExporter,
        healthKit: HealthKit,
        storage: LocalStorage,
        storageKey: LocalStorageKey<ExportSessionDescriptor>,
        session: BulkExportSessionImpl<AcknowledgingBatchProcessor>,
        batches: [ExportBatch]
    ) {
        self.module = module
        self.healthKit = healthKit
        self.storage = storage
        self.storageKey = storageKey
        self.session = session
        self.batches = batches
    }
}


@MainActor
private func makeProcessingSession(
    batchCount: Int,
    persistence: SessionDescriptorPersisting,
    processBatch: @escaping @Sendable (ExportBatch) async throws -> UUID,
    didPersist: @escaping @Sendable (UUID) -> Void
) async throws -> ProcessingSessionFixture {
    let module = BulkHealthExporter(checkpointStorageSetting: .unencrypted())
    let healthKit = HealthKit()
    let storage = LocalStorage()
    await withDependencyResolution(standard: TestStandard()) { healthKit; storage; module }
    let sessionID = BulkExportSessionIdentifier(UUID().uuidString)
    let storageKey = LocalStorageKey<ExportSessionDescriptor>(
        BulkHealthExporter.localStorageKey(forSessionId: sessionID), setting: .unencrypted()
    )
    let batches = (0..<batchCount).map { index in
        ExportBatch(
            sampleType: SampleType.stepCount,
            timeRange: Date(timeIntervalSince1970: Double(index * 100))..<Date(timeIntervalSince1970: Double((index + 1) * 100))
        )
    }
    var descriptor = ExportSessionDescriptor(
        sessionId: sessionID, startDate: .absolute(.distantPast), endDate: Date(timeIntervalSince1970: Double(batchCount * 100))
    )
    descriptor.pendingBatches = batches
    try storage.store(descriptor, for: storageKey)
    let session = try await BulkExportSessionImpl(
        sessionId: sessionID,
        bulkExporter: module,
        healthKit: healthKit,
        sampleTypes: [],
        startDate: descriptor.startDate,
        endDate: descriptor.endDate,
        batchSize: .automatic,
        localStorage: storage,
        batchProcessor: AcknowledgingBatchProcessor(acknowledge: didPersist),
        persistence: persistence,
        processBatch: processBatch
    )
    try module.add(session)
    return ProcessingSessionFixture(
        module: module, healthKit: healthKit, storage: storage, storageKey: storageKey, session: session, batches: batches
    )
}


private actor ProcessingGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}


@MainActor
private final class DescriptorMutationRecorder {
    var descriptor: ExportSessionDescriptor {
        didSet {
            snapshots.append(descriptor)
        }
    }
    var snapshots: [ExportSessionDescriptor] = []

    init(descriptor: ExportSessionDescriptor) {
        self.descriptor = descriptor
    }
}


private enum PersistenceTestError: Error {
    case injected
}


private actor TestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample>,
        ofType sampleType: SampleType<Sample>
    ) -> HealthKitAnchorCommitAction? {
        nil
    }
    
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject>,
        ofType sampleType: SampleType<Sample>,
        deletedAfter: Date?
    ) -> HealthKitAnchorCommitAction? {
        nil
    }
}

#endif
