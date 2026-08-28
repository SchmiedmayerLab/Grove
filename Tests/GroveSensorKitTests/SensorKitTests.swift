//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSensorKit
import Testing


@Suite
struct SensorKitTests {
    @Test
    @available(iOS 18, *)
    func hmmm() {
        let module = SensorKit()
        #expect(module.authorizationStatus(for: .heartRate) == .notDetermined)
    }

    @Test("Anchored batch acknowledgement is single-use and cursor-fenced")
    @available(iOS 18, *)
    func anchoredBatchAcknowledgementIsSingleUseAndCursorFenced() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let firstEnd = start.addingTimeInterval(10)
        let competingEnd = start.addingTimeInterval(20)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)

        func token(advancingTo end: Date) -> SensorKit.QueryAnchorAcknowledgement {
            SensorKit.QueryAnchorAcknowledgement {
                guard try anchor.update(
                    from: QueryAnchor(timestamp: start),
                    to: QueryAnchor(timestamp: end)
                ) else {
                    throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
                }
            }
        }

        let accepted = token(advancingTo: firstEnd)
        let stale = token(advancingTo: competingEnd)
        try accepted.acknowledge()
        #expect(try anchor.value.timestamp == firstEnd)
        #expect(throws: SensorKit.QueryAnchorAcknowledgementError.alreadyAcknowledged) {
            try accepted.acknowledge()
        }
        #expect(throws: SensorKit.QueryAnchorAcknowledgementError.staleCursor) {
            try stale.acknowledge()
        }
        #expect(try anchor.value.timestamp == firstEnd)
    }

    @Test("Unacknowledged cursor survives iterator loss")
    @available(iOS 18, *)
    func unacknowledgedCursorSurvivesIteratorLoss() throws {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let token = SensorKit.QueryAnchorAcknowledgement {
            guard try anchor.update(
                from: QueryAnchor(timestamp: start),
                to: QueryAnchor(timestamp: start.addingTimeInterval(10))
            ) else {
                throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
            }
        }

        _ = token
        #expect(try anchor.value.timestamp == start)
    }

    @Test("Reset invalidates an outstanding acknowledgement")
    @available(iOS 18, *)
    func resetInvalidatesOutstandingAcknowledgement() throws {
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let expected = try anchor.value
        let token = SensorKit.QueryAnchorAcknowledgement {
            guard try anchor.update(
                from: expected,
                to: expected.advancedPastEmptyRange(to: start.addingTimeInterval(10))
            ) else {
                throw SensorKit.QueryAnchorAcknowledgementError.staleCursor
            }
        }

        try anchor.reset()

        #expect(try anchor.value.timestamp == .distantPast)
        #expect(try anchor.value.resetGeneration == 1)
        #expect(throws: SensorKit.QueryAnchorAcknowledgementError.staleCursor) {
            try token.acknowledge()
        }
        #expect(try anchor.value.timestamp == .distantPast)
        #expect(try anchor.value.resetGeneration == 1)
    }

    @Test("Pending acquisition batches survive crashes and fence equal-timestamp deliveries")
    @available(iOS 18, *)
    func pendingAcquisitionBatchIsDurableAndMonotonic() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 4_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: timestamp)
        let initial = try anchor.value
        let firstPending = initial.preparing(.sampleCount(
            deliveryTimestamp: timestamp,
            sampleCount: 2
        ))

        #expect(try anchor.update(from: initial, to: firstPending))
        // A restarted fetcher reads the persisted boundary, so a new configured batch size cannot
        // split the two records that were already exposed under this acquisition coordinate.
        let afterRestart = try anchor.value
        #expect(afterRestart.pendingBatch?.sampleCount == 2)
        #expect(afterRestart.acquisitionBatchCoordinate == initial.acquisitionBatchCoordinate)
        #expect(throws: SensorKit.QueryAnchorAcknowledgementError.unresolvedPendingBatch) {
            try anchor.reset()
        }
        #expect(try anchor.value == afterRestart)

        let firstCommitted = try afterRestart.committingPendingBatch()
        #expect(try anchor.update(from: afterRestart, to: firstCommitted))
        #expect(firstCommitted.timestamp == timestamp)
        #expect(firstCommitted.batchSequence == 1)

        // SensorKit can deliver another distinct batch at the exact same framework timestamp.
        // Sequence, rather than clinical time or payload, keeps that occurrence distinct.
        let secondPending = firstCommitted.preparing(.sampleCount(
            deliveryTimestamp: timestamp,
            sampleCount: 1
        ))
        #expect(try anchor.update(from: firstCommitted, to: secondPending))
        #expect(secondPending.acquisitionBatchCoordinate != firstPending.acquisitionBatchCoordinate)
        let secondCommitted = try secondPending.committingPendingBatch()
        #expect(try anchor.update(from: secondPending, to: secondCommitted))
        #expect(secondCommitted.batchSequence == 2)
        #expect(secondCommitted.timestamp == timestamp)
    }

    @Test("Duplicate device partitions fail closed")
    @available(iOS 18, *)
    func duplicateDevicePartitionsFailClosed() {
        #expect(throws: SensorKit.AnchoredFetchError.ambiguousDevicePartition(productType: "iPhone18,2")) {
            try SensorKit.validateUniqueDevicePartitions(["iPhone18,2", "Watch7,12", "iPhone18,2"])
        }
    }

    @Test("Reset includes temporarily absent persisted and in-flight device partitions")
    @available(iOS 18, *)
    func resetIncludesAbsentDevicePartitions() {
        let sensor = Sensor.heartRate
        let sensorID = sensor.id
        let partitions = SensorKit.devicePartitionsToReset(
            sensorID: sensorID,
            currentDeviceProductTypes: ["currently-present"],
            cachedKeys: [
                SensorKit.QueryAnchorKey(sensor: sensor, deviceProductType: "in-flight-but-absent")
            ],
            persistedRawKeys: [
                "\(SensorKit.queryAnchorKeyPrefix).\(sensorID).previously-seen-but-absent",
                "\(SensorKit.queryAnchorKeyPrefix).different-sensor.ignore-me"
            ]
        )

        #expect(partitions == [
            "currently-present",
            "in-flight-but-absent",
            "previously-seen-but-absent"
        ])
    }
}
