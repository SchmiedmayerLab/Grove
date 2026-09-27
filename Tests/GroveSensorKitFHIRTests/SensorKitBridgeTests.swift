//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
import GroveSensorKit
import GroveSensorKitFHIR
import SensorKit
import Testing


@Suite
struct GroveSensorKitBridgeTests {
    private static var sourceID: SensorKitSourceRecordID {
        get throws {
            SensorKitSourceRecordID(try #require(
                UUID(uuidString: "879d9ea2-21cb-4527-b59b-2831dc4c84ab")
            ))
        }
    }

    @Test
    @available(iOS 18, *)
    func alreadyFetchedOnWristValueMapsWithoutAQuery() throws {
        let timestamp = Date(timeIntervalSince1970: 1_787_009_400)
        let sample = SensorKitOnWristEventSample(
            timestamp: timestamp,
            onWrist: true,
            wristLocation: .left,
            crownOrientation: .right,
            onWristDate: timestamp.addingTimeInterval(-60),
            offWristDate: nil
        )
        let record = try SensorKitOnWristRecord(
            sourceRecordID: Self.sourceID,
            sample: sample
        )

        #expect(record.timestamp == timestamp)
        #expect(record.currentStateStart == timestamp.addingTimeInterval(-60))
        #expect(record.onWrist)
        #expect(record.wristLocation == .left)
        #expect(record.crownOrientation == .right)
    }

    @Test
    @available(iOS 18, *)
    func alreadyFetchedDeviceUsageSummaryRequiresCallerSuppliedNativeEvidence() throws {
        let timestamp = Date(timeIntervalSince1970: 1_787_009_400)
        let report = SRDeviceUsageReport.SafeRepresentation(
            timestamp: timestamp,
            duration: 300,
            totalScreenWakes: 3,
            totalUnlocks: 2,
            totalUnlockDuration: 42.5,
            version: "1"
        )
        let native = try SensorKitNativeRecording(
            title: "Exact native report",
            format: .nativeRecording,
            payload: .inline(Data(#"{"version":"1"}"#.utf8)),
            admission: .callerAuthorizedOpaquePayload
        )
        let record = SensorKitDeviceUsageRecord(
            sourceRecordID: try Self.sourceID,
            report: report,
            nativeRecording: native
        )

        #expect(record.timestamp == timestamp)
        #expect(record.durationSeconds == 300)
        #expect(record.totalScreenWakes == 3)
        #expect(record.totalUnlocks == 2)
        #expect(record.totalUnlockDurationSeconds == 42.5)
    }

    @Test("Prepared evidence preserves sub-millisecond source differences")
    @available(iOS 18, *)
    func retryEvidencePreservesExactDates() throws {
        let timestamp = Date(timeIntervalSince1970: 1_787_009_400)
        let baseline = SensorKitOnWristEventSample(
            timestamp: timestamp,
            onWrist: true,
            wristLocation: .left,
            crownOrientation: .right,
            onWristDate: timestamp,
            offWristDate: nil
        )
        let shifted = SensorKitOnWristEventSample(
            timestamp: timestamp.addingTimeInterval(0.000_1),
            onWrist: true,
            wristLocation: .left,
            crownOrientation: .right,
            onWristDate: timestamp,
            offWristDate: nil
        )

        let first = try SensorKitPreparedStructuredRecord(onWrist: baseline)
        let second = try SensorKitPreparedStructuredRecord(onWrist: shifted)
        #expect(first.retryEvidence != second.retryEvidence)
        #expect(first.nativePayload == nil)
        let record = try first.sensorKitRecord(sourceRecordID: Self.sourceID)
        guard case .onWrist(let onWrist) = record else {
            Issue.record("Expected an on-wrist record")
            return
        }
        let expectedSourceID = try Self.sourceID
        #expect(onWrist.sourceRecordID == expectedSourceID)
    }

    @Test("Device usage preparation produces strict native JSON and the matching record")
    @available(iOS 18, *)
    func preparedDeviceUsageOwnsItsNativeEncoding() throws {
        let report = SRDeviceUsageReport.SafeRepresentation(
            timestamp: Date(timeIntervalSince1970: 1_787_009_400.125),
            duration: 300,
            totalScreenWakes: 3,
            totalUnlocks: 2,
            totalUnlockDuration: 42.5,
            version: "1"
        )
        let prepared = try SensorKitPreparedStructuredRecord(deviceUsage: report)
        let payload = try #require(prepared.nativePayload)
        let native = try SensorKitNativeRecording(
            title: "Device usage",
            format: .nativeRecording,
            payload: .inline(payload),
            admission: .callerAuthorizedOpaquePayload
        )

        let record = try prepared.sensorKitRecord(
            sourceRecordID: Self.sourceID,
            nativeRecording: native
        )
        guard case .deviceUsage(let deviceUsage) = record else {
            Issue.record("Expected a device-usage record")
            return
        }
        #expect(deviceUsage.totalScreenWakes == 3)
        #expect(prepared.retryEvidence == payload)
    }
}
#endif
