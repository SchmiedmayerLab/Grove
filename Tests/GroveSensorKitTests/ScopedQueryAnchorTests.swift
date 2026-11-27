//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

import Foundation
@testable import GroveSensorKit
import Testing


@Suite
struct ScopedQueryAnchorTests {
    @Test
    func switchingSourcesPreservesEachPendingCoordinate() throws {
        let first = key(source: UUID())
        let second = key(source: UUID())
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_000)
        let firstPending = QueryAnchor().preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1))
        let secondPending = QueryAnchor().preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 2))
        var storage = [
            first.storageIdentifier: try JSONEncoder().encode(firstPending),
            second.storageIdentifier: try JSONEncoder().encode(secondPending)
        ]
        let restoredFirst = try JSONDecoder().decode(QueryAnchor.self, from: #require(storage[first.storageIdentifier]))
        #expect(restoredFirst.acquisitionBatchCoordinate == firstPending.acquisitionBatchCoordinate)
        storage[first.storageIdentifier] = try JSONEncoder().encode(restoredFirst.committingPendingBatch())
        let restoredSecond = try JSONDecoder().decode(QueryAnchor.self, from: #require(storage[second.storageIdentifier]))
        #expect(restoredSecond == secondPending)
        #expect(restoredSecond.acquisitionBatchCoordinate != firstPending.acquisitionBatchCoordinate)
    }

    @Test
    func sameSourceRestoresItsPartitionAndFreshInstallationRemainsDistinct() throws {
        let source = UUID()
        let restoredSource = try JSONDecoder().decode(UUID.self, from: JSONEncoder().encode(source))
        #expect(key(source: source).storageIdentifier == key(source: restoredSource).storageIdentifier)
        #expect(key(source: source).storageIdentifier != key(source: source, device: "Watch2,1").storageIdentifier)
        let pending = QueryAnchor().preparing(.sampleCount(deliveryTimestamp: Date(timeIntervalSinceReferenceDate: 7_000), sampleCount: 1))
        let restored = try JSONDecoder().decode(QueryAnchor.self, from: JSONEncoder().encode(pending))
        let reinstalled = QueryAnchor().preparing(.sampleCount(deliveryTimestamp: pending.timestamp, sampleCount: 1))
        #expect(restored.acquisitionBatchCoordinate == pending.acquisitionBatchCoordinate)
        #expect(reinstalled.acquisitionBatchCoordinate.streamPartition != pending.streamPartition)
    }

    private func key(source: UUID, device: String = "Watch1,1") -> GroveSensorKit.SensorKit.StoredQueryAnchorKey {
        .init(namespace: source, query: .init(sensor: Sensor.onWrist, deviceProductType: device))
    }
}

#endif
