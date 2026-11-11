//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSensorKit
import Testing


@Suite("Query anchor stream partitions")
struct QueryAnchorStreamPartitionTests {
    @Test("A fresh cursor mints its stream partition with its first pending batch, and every later state keeps it")
    @available(iOS 18, *)
    func freshCursorMintsItsStreamPartition() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_000)
        let anchor = ManagedQueryAnchor.ephemeral()
        let fresh = try anchor.value
        #expect(fresh == QueryAnchor())
        #expect(fresh.streamPartition == 0)

        let pending = fresh.preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1))
        #expect(pending.streamPartition != 0)
        #expect(pending.acquisitionBatchCoordinate.streamPartition == pending.streamPartition)
        #expect(try anchor.update(from: fresh, to: pending))
        #expect(try anchor.value == pending)

        let partition = pending.streamPartition
        let committed = try pending.committingPendingBatch()
        #expect(committed.streamPartition == partition)
        #expect(committed.preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1)).streamPartition == partition)
        #expect(committed.advancedPastEmptyRange(to: timestamp.addingTimeInterval(1)).streamPartition == partition)
        #expect(committed.reset().streamPartition == partition)
        #expect(pending.discardingPendingBatch().streamPartition == partition)
    }

    @Test("A fresh cursor that first advances past an empty range or resets mints its stream partition there")
    @available(iOS 18, *)
    func freshCursorMintsWhereverItFirstPersists() {
        let advanced = QueryAnchor().advancedPastEmptyRange(to: Date(timeIntervalSinceReferenceDate: 7_100))
        #expect(advanced.streamPartition != 0)
        let pending = advanced.preparing(.sampleCount(deliveryTimestamp: advanced.timestamp, sampleCount: 1))
        #expect(pending.streamPartition == advanced.streamPartition)
        #expect(QueryAnchor().reset().streamPartition != 0)
    }

    @Test("Two fresh cursors state the same coordinate under different partitions")
    @available(iOS 18, *)
    func freshCursorsAreDisjoint() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_200)
        func firstBatch() -> SensorKit.AcquisitionBatchCoordinate {
            QueryAnchor().preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1)).acquisitionBatchCoordinate
        }
        let (first, second) = (firstBatch(), firstBatch())
        #expect(first.cursorTimestamp == second.cursorTimestamp)
        #expect(first.resetGeneration == second.resetGeneration)
        #expect(first.sequence == second.sequence)
        #expect(first != second)
        #expect(first.stableValue != second.stableValue)
    }

    @Test("A cursor decoded without a stream partition keeps 0 through every later state")
    @available(iOS 18, *)
    func decodedCursorKeepsPartitionZero() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_300)
        let legacyDate = try JSONEncoder().encode(timestamp)
        let keyed = Data(#"{"timestamp":7300,"resetGeneration":2,"batchSequence":3}"#.utf8)
        for encoded in [legacyDate, keyed] {
            let decoded = try JSONDecoder().decode(QueryAnchor.self, from: encoded)
            #expect(decoded.timestamp == timestamp)
            #expect(decoded.streamPartition == 0)
            let pending = decoded.preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1))
            #expect(pending.streamPartition == 0)
            #expect(pending.acquisitionBatchCoordinate.streamPartition == 0)
            #expect(try pending.committingPendingBatch().streamPartition == 0)
            #expect(decoded.advancedPastEmptyRange(to: timestamp.addingTimeInterval(1)).streamPartition == 0)
            #expect(decoded.reset().streamPartition == 0)
        }
    }

    @Test("A persisted stream partition survives encoding")
    @available(iOS 18, *)
    func streamPartitionRoundTrips() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_400)
        let pending = QueryAnchor().preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1))
        #expect(try JSONDecoder().decode(QueryAnchor.self, from: JSONEncoder().encode(pending)) == pending)
    }

    @Test("A coordinate's stable value states its partition")
    @available(iOS 18, *)
    func stableValueStatesThePartition() {
        let coordinate = SensorKit.AcquisitionBatchCoordinate(
            streamPartition: 42,
            cursorTimestamp: Date(timeIntervalSinceReferenceDate: 1),
            resetGeneration: 2,
            sequence: 3
        )
        #expect(coordinate.stableValue == "sensorkit-batch-v1:42:\(Double(1).bitPattern):2:3")
    }
}
