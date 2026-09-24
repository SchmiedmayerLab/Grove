//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSensorKit
#if os(iOS)
import SensorKit
#endif
import Testing


@Suite
struct SensorKitTests {
    #if os(iOS)
    @Test("ECG safe representations retain exact session evidence and coverage")
    @available(iOS 17.4, *)
    func ecgSafeRepresentationRetainsNativeIdentity() {
        let sample = SensorKitECGSession.Batch.VoltageSample(
            flags: [],
            voltage: Measurement(value: 1, unit: .microvolts)
        )
        let finalBatchOffset: TimeInterval = 2
        let finalBatchSampleCount = 3
        let frequencyHertz = 512.0
        let session = SensorKitECGSession(
            startDate: Date(timeIntervalSinceReferenceDate: 1_000),
            sessionIdentifier: "provider-session",
            sessionStates: [.end, .begin, .active],
            frequency: Measurement(value: frequencyHertz, unit: .hertz),
            lead: .rightArmMinusLeftArm,
            guidance: .guided,
            batches: [
                .init(offset: 0, samples: [sample]),
                .init(offset: finalBatchOffset, samples: Array(repeating: sample, count: finalBatchSampleCount))
            ]
        )

        #expect(session.sessionIdentifier == "provider-session")
        #expect(session.sessionStates == [.begin, .active, .end])
        let expectedDuration = finalBatchOffset + Double(finalBatchSampleCount - 1) / frequencyHertz
        #expect(session.duration == expectedDuration)
        #expect(session.timeRange.upperBound == session.startDate.addingTimeInterval(expectedDuration))
    }

    @Test("Device-usage evidence is constructible without private SensorKit initializers")
    @available(iOS 18, *)
    func deviceUsageEvidenceHasSourceNeutralInitializers() throws {
        let textInputSession = SRDeviceUsageReport.SafeRepresentation.AppUsage.TextInputSession(
            duration: 2,
            sessionType: .keyboard,
            identifier: "keyboard-session"
        )
        let supplementalCategory = SRDeviceUsageReport.SafeRepresentation.AppUsage.SupplementalCategory(
            identifier: "communication"
        )
        let appUsage = SRDeviceUsageReport.SafeRepresentation.AppUsage(
            bundleIdentifier: "com.apple.MobileSMS",
            relativeStartTime: 5,
            usageTime: 30,
            reportApplicationIdentifier: "report-app",
            textInputSessions: [textInputSession],
            supplementalCategories: [supplementalCategory]
        )
        let notificationUsage = SRDeviceUsageReport.SafeRepresentation.NotificationUsage(
            bundleIdentifier: "com.apple.MobileSMS",
            event: .received
        )
        let webUsage = SRDeviceUsageReport.SafeRepresentation.WebUsage(totalUsageTime: 10)
        let report = SRDeviceUsageReport.SafeRepresentation(
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            duration: 60,
            totalScreenWakes: 2,
            totalUnlocks: 1,
            totalUnlockDuration: 20,
            version: "1",
            appUsageByCategory: [.socialNetworking: [appUsage]],
            notificationUsageByCategory: [.socialNetworking: [notificationUsage]],
            webUsageByCategory: [.socialNetworking: [webUsage]]
        )

        #expect(try #require(report.appUsageByCategory[.socialNetworking]?.first) == appUsage)
        #expect(try #require(report.notificationUsageByCategory[.socialNetworking]?.first) == notificationUsage)
        #expect(try #require(report.webUsageByCategory[.socialNetworking]?.first) == webUsage)
    }
    #endif

    @Test("A new SensorKit instance has not requested heart-rate authorization")
    @available(iOS 18, *)
    func initialAuthorizationStatusIsNotDetermined() {
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
