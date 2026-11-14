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
import SensorKit
import Testing


struct SensorKitBatchReplayTokenTests {
    @Test(arguments: [false, true])
    func durableReplayPreservesCoordinateAndNeverMutatesLiveCursor(interval: Bool) throws {
        let start = Date(timeIntervalSinceReferenceDate: 7_000)
        let end = start.addingTimeInterval(30)
        let boundary: QueryAnchor.PendingBatch = interval ? .timeRange(start..<end, sampleCount: 3)
            : .sampleCount(deliveryTimestamp: end, sampleCount: 3)
        let original = QueryAnchor(timestamp: start, resetGeneration: 4, batchSequence: 8, pendingBatch: boundary, streamPartition: 19)
        let token = try GroveSensorKit.SensorKit.BatchReplayToken(
            sensorIdentifier: Sensor.onWrist.id, deviceProductType: "Watch1,1", anchor: original
        )
        let decoded = try GroveSensorKit.SensorKit.BatchReplayToken(encoded: token.encoded())
        #expect(decoded == token)
        #expect(decoded.acquisitionBatch.stableValue == original.acquisitionBatchCoordinate.stableValue)
        let live = ManagedQueryAnchor.ephemeral(anchor: try original.committingPendingBatch())
        let replay = ManagedQueryAnchor.ephemeral(anchor: decoded.anchor)
        #expect(try replay.update(from: original, to: original.committingPendingBatch()))
        #expect(try live.value == original.committingPendingBatch())
        #expect(try replay.value.acquisitionBatchCoordinate.sequence == 9)
        #expect(decoded.acquisitionBatch.sequence == 8)
    }

    @Test(arguments: [false, true])
    func initialHistoricalBoundaryDoesNotResetEstablishedCursor(established: Bool) async throws {
        enum Stop: Error { case requested }
        let cutoff = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let sixMonthsAgo = cutoff.addingTimeInterval(-180 * 24 * 60 * 60)
        let previous = cutoff.addingTimeInterval(-60)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: established ? previous : nil)
        var fetcher = AnchoredFetcher<SRAmbientLightSample>.TimeIntervalBasedFetcher(
            sensor: .ambientLight,
            anchor: anchor,
            quarantineCutoff: cutoff,
            batchSize: 60,
            device: .current,
            initialStartDate: sixMonthsAgo,
            fetchOperation: { _, _, range in
                #expect(range.lowerBound == (established ? previous : sixMonthsAgo))
                throw Stop.requested
            }
        )
        await #expect(throws: Stop.self) {
            _ = try await fetcher.next(isolation: nil)
        }
        #expect(try anchor.value.timestamp == (established ? previous : sixMonthsAgo))
        #expect(try anchor.value.batchSequence == 0)
        #expect(try anchor.value.resetGeneration == 0)
    }

    @Test(arguments: [0, 16_385])
    func invalidTokenSizeIsRejected(bytes: Int) {
        #expect(throws: GroveSensorKit.SensorKit.BatchReplayError.invalidToken) {
            try GroveSensorKit.SensorKit.BatchReplayToken(encoded: Data(repeating: 0, count: bytes))
        }
    }

    @Test
    func unsupportedVersionAndMissingPendingBoundaryAreRejected() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 7_000)
        #expect(throws: GroveSensorKit.SensorKit.BatchReplayError.invalidToken) {
            try GroveSensorKit.SensorKit.BatchReplayToken(
                sensorIdentifier: Sensor.onWrist.id, deviceProductType: "Watch1,1", anchor: QueryAnchor(timestamp: timestamp)
            )
        }
        let anchor = QueryAnchor(timestamp: timestamp).preparing(.sampleCount(deliveryTimestamp: timestamp, sampleCount: 1))
        let token = try GroveSensorKit.SensorKit.BatchReplayToken(sensorIdentifier: Sensor.onWrist.id, deviceProductType: "Watch1,1", anchor: anchor)
        var object = try #require(JSONSerialization.jsonObject(with: token.encoded()) as? [String: Any])
        object["version"] = 2
        let changed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: GroveSensorKit.SensorKit.BatchReplayError.invalidToken) {
            try GroveSensorKit.SensorKit.BatchReplayToken(encoded: changed)
        }
    }
}

#endif
