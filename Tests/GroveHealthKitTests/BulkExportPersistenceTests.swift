//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKit
@testable import GroveHealthKitBulkExport
import Synchronization
import Testing


@Suite
struct BulkExportPersistenceTests {
    enum Outcome: CaseIterable {
        case success, failure, cancellation
    }

    enum TestFailure: Error {
        case processing
    }

    struct CheckpointRecorder {
        var descriptor: ExportSessionDescriptor {
            didSet { checkpoints.append(descriptor) }
        }
        var checkpoints: [ExportSessionDescriptor] = []
    }

    @Test(arguments: Outcome.allCases)
    func completedTransitionPreservesEveryBatch(_ outcome: Outcome) {
        let first = ExportBatch(sampleType: SampleType.stepCount, timeRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 100))
        let second = ExportBatch(sampleType: SampleType.stepCount, timeRange: first.timeRange.upperBound..<Date(timeIntervalSince1970: 200))
        var descriptor = ExportSessionDescriptor(sessionId: .init(UUID().uuidString), startDate: .absolute(first.timeRange.lowerBound), endDate: second.timeRange.upperBound)
        descriptor.pendingBatches = [first, second]
        let result: Result<Void, any Error> = switch outcome {
        case .success: .success(())
        case .failure: .failure(TestFailure.processing)
        case .cancellation: .failure(CancellationError())
        }
        var recorder = CheckpointRecorder(descriptor: descriptor)
        recorder.descriptor.finishBatch(first, result: result)
        #expect(recorder.checkpoints.count == 1)
        #expect(recorder.checkpoints.allSatisfy { $0.pendingBatches.count + $0.completedBatches.count == 2 })
        descriptor = recorder.descriptor
        switch outcome {
        case .success:
            #expect(descriptor.completedBatches.count == 1)
            #expect(descriptor.completedBatches.first?.result == .success)
            #expect(descriptor.pendingBatches == [second])
        case .failure:
            #expect(descriptor.completedBatches.isEmpty)
            #expect(descriptor.pendingBatches.last?.result?.isFailure == true)
            descriptor.unmarkAllFailedBatches()
            #expect(descriptor.pendingBatches == [second, first])
        case .cancellation:
            #expect(descriptor.completedBatches.isEmpty)
            #expect(descriptor.pendingBatches == [first, second])
        }
        #expect(descriptor.pendingBatches.count + descriptor.completedBatches.count == 2)
        #expect(Set((descriptor.pendingBatches + descriptor.completedBatches).map(\.timeRange)) == [first.timeRange, second.timeRange])
    }

    @Test
    func flushReportsFailureAndLaterWriteCanRecover() async throws {
        let fail = Mutex(true)
        let persisting = SessionDescriptorPersisting { _ in
            if fail.withLock({ $0 }) { throw CocoaError(.fileWriteOutOfSpace) }
        }
        let descriptor = ExportSessionDescriptor(sessionId: .init(UUID().uuidString), startDate: .absolute(.distantPast), endDate: .now)
        persisting(descriptor)
        await #expect(throws: CocoaError.self) { try await persisting.flush() }
        fail.withLock { $0 = false }
        persisting(descriptor)
        try await persisting.flush()
    }

    @Test @SessionDescriptorPersisting.PersistSessionStateActor
    func coalescingWritesLatestSnapshotAndFlushWaits() async throws {
        let writes = Mutex<[Date]>([])
        let persisting = SessionDescriptorPersisting { descriptor in
            writes.withLock { $0.append(descriptor.endDate) }
        }
        let sessionID = BulkExportSessionIdentifier(UUID().uuidString)
        // Keep writes queued until all three snapshots are registered.
        for end in [100.0, 200.0, 300.0] {
            persisting(ExportSessionDescriptor(sessionId: sessionID, startDate: .absolute(.distantPast), endDate: Date(timeIntervalSince1970: end)))
        }
        #expect(writes.withLock { $0.isEmpty }) // Disk work was not run inline.
        try await persisting.flush()
        #expect(writes.withLock { $0 } == [Date(timeIntervalSince1970: 300)])
        persisting(ExportSessionDescriptor(sessionId: sessionID, startDate: .absolute(.distantPast), endDate: Date(timeIntervalSince1970: 400)))
        try await persisting.flush()
        #expect(writes.withLock { $0 } == [Date(timeIntervalSince1970: 300), Date(timeIntervalSince1970: 400)])
    }
}

#endif
