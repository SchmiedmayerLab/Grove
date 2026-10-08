//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The fixture corpus is intentionally declared together so every admitted SensorKit graph shape is visible.
// swiftlint:disable function_body_length

import Foundation
import GroveFHIRContract
import GroveSensorKitFHIR
import ModelsR4
import Testing


@Suite
struct SensorConformanceFixtureTests {
    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/conformance-fixtures/sensor")
    }

    private static func sourceID(_ value: String) throws -> SensorKitSourceRecordID {
        SensorKitSourceRecordID(try #require(UUID(uuidString: value)))
    }

    private static func nativeRecording(title: String) throws -> SensorKitNativeRecording {
        try SensorKitNativeRecording(
            title: title,
            format: .nativeRecording,
            payload: .inline(Data(#"{"source":"SensorKit","complete":true}"#.utf8)),
            admission: .verifiedSanitizedInput
        )
    }

    @Test
    func writeSharedSensorFixtures() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_787_009_400)
        let rotation = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID("754cdecc-6733-4610-935b-f19425cff68e"),
            samples: [
                .init(timestamp: timestamp, x: 0.1, y: 0.2, z: 0.3),
                .init(timestamp: timestamp.addingTimeInterval(0.01), x: 0.4, y: 0.5, z: 0.6),
                .init(timestamp: timestamp.addingTimeInterval(0.02), x: 0.7, y: 0.8, z: 0.9)
            ]
        )
        let ecg = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID("294651b1-a796-483a-a324-fcac997ae361"),
            startDate: timestamp,
            durationSeconds: 0.006,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [
                .init(offsetSeconds: 0, millivolts: [0.01, 0.02]),
                .init(offsetSeconds: 0.004, millivolts: [0.03, 0.04])
            ],
            nativeRecording: try Self.nativeRecording(title: "Exact SensorKit ECG record")
        )
        let onWrist = SensorKitOnWristRecord(
            sourceRecordID: try Self.sourceID("539bfe8c-ce3c-4410-a9a7-d133bc6d5230"),
            timestamp: timestamp,
            onWrist: true,
            currentStateStart: timestamp.addingTimeInterval(-120),
            wristLocation: .left,
            crownOrientation: .right
        )
        let deviceUsage = SensorKitDeviceUsageRecord(
            sourceRecordID: try Self.sourceID("c014060e-284c-47e3-a0f8-e6ba029ae950"),
            timestamp: timestamp,
            durationSeconds: 300,
            totalScreenWakes: 3,
            totalUnlocks: 2,
            totalUnlockDurationSeconds: 42.5,
            nativeRecording: try Self.nativeRecording(title: "Exact SensorKit device usage report")
        )
        let visit = SensorKitVisitRecord(
            sourceRecordID: try Self.sourceID("406da8b7-9e66-4afa-b13a-f2854674fab5"),
            locationCategory: .work,
            distanceFromHomeMeters: 1_250,
            arrivalWindow: DateInterval(
                start: timestamp.addingTimeInterval(-3_600),
                end: timestamp.addingTimeInterval(-3_300)
            ),
            departureWindow: DateInterval(
                start: timestamp.addingTimeInterval(-300),
                end: timestamp
            )
        )
        let raw = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID("248b854a-8d64-4308-9ee0-d220e7d747d3"),
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: timestamp, duration: 1),
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit heart rate batch",
                format: .heartRateSamples,
                payload: .inline(Data("timestamp,value,confidence,device\n1787009400,72,3,Watch\n".utf8)),
                admission: .verifiedSanitizedInput
            )
        )
        let messagesUsage = SensorKitMessagesUsageRecord(
            sourceRecordID: try Self.sourceID("0dbb1f47-46eb-42ec-b6b7-402e33d3e463"),
            timestamp: timestamp,
            durationSeconds: 3_600,
            totalIncomingMessages: 12,
            totalOutgoingMessages: 8,
            totalUniqueContacts: 3,
            nativeRecording: try Self.nativeRecording(title: "Exact SensorKit messages usage report")
        )
        let phoneUsage = SensorKitPhoneUsageRecord(
            sourceRecordID: try Self.sourceID("d51c855c-9d40-4900-83a2-3547872b0a86"),
            timestamp: timestamp,
            durationSeconds: 3_600,
            totalIncomingCalls: 2,
            totalOutgoingCalls: 5,
            totalPhoneCallDurationSeconds: 42.5,
            totalUniqueContacts: 4
        )
        let keyboardMetrics = SensorKitKeyboardMetricsRecord(
            sourceRecordID: try Self.sourceID("f4a4d31e-40fc-4c9c-a582-ecf077aa8674"),
            timestamp: timestamp,
            durationSeconds: 3_600,
            totalTypingDurationSeconds: 125.5,
            totalWords: 240,
            totalAlteredWords: 12,
            totalTaps: 1_050,
            totalDeletes: 33,
            totalEmojis: 7,
            totalAutocorrections: 19,
            totalPauses: 41,
            totalTypingEpisodes: 6,
            typingSpeed: 3.5,
            nativeRecording: try Self.nativeRecording(title: "Exact SensorKit keyboard metrics report")
        )
        let sleepSession = SensorKitSleepSessionRecord(
            sourceRecordID: try Self.sourceID("cd44465f-cb2a-4e5c-a2e3-1d59ee36ba75"),
            session: DateInterval(start: timestamp.addingTimeInterval(-28_800), end: timestamp)
        )
        let accelerometer = try SensorKitAccelerometerRecord(
            sourceRecordID: try Self.sourceID("41a1d817-6b0b-4b90-a0b7-3e0969395d24"),
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit accelerometer batch",
                format: .triaxialAccelerationSamples,
                payload: .inline(Data("timestamp,identifier,x,y,z,device\n1787009400,1,0.1,0.2,0.3,Watch\n".utf8)),
                admission: .verifiedSanitizedInput
            )
        )
        let ppg = try SensorKitPPGRecord(
            sourceRecordID: try Self.sourceID("74b04bf3-e2ad-421c-8b98-84582f22cd7a"),
            nativeRecording: try SensorKitNativeRecording(
                title: "Exact SensorKit PPG batch",
                format: .photoplethysmogramSamples,
                payload: .inline(try SensorKitPPGTestSupport.recording(start: timestamp).encoded()),
                admission: .callerAuthorizedOpaquePayload
            )
        )
        let records: [(name: String, record: SensorKitRecord)] = [
            ("rotation-rate", .rotationRate(rotation)),
            ("ecg-hybrid", .electrocardiogram(ecg)),
            ("on-wrist", .onWrist(onWrist)),
            ("device-usage-hybrid", .deviceUsage(deviceUsage)),
            ("visit", .visit(visit)),
            ("raw-recording", .raw(raw)),
            ("messages-usage-hybrid", .messagesUsage(messagesUsage)),
            ("phone-usage", .phoneUsage(phoneUsage)),
            ("keyboard-metrics-hybrid", .keyboardMetrics(keyboardMetrics)),
            ("sleep-session", .sleepSession(sleepSession)),
            ("accelerometer-summary-hybrid", .accelerometer(accelerometer)),
            ("ppg-summary-hybrid", .ppg(ppg))
        ]
        // Each record is its own event, numbered 1 through 12 in this order through a fresh ledger.
        var fixtures: [String: ModelsR4.Bundle] = [:]
        for (index, entry) in records.enumerated() {
            let producer = try SensorKitExporterFixtures.producer(
                sequence: UInt64(index + 1),
                application: ApplicationDevice.test(
                    name: "Sensor Conformance Fixture",
                    bundleIdentifier: "org.grovealliance.sensor-conformance",
                    version: "0.5.0"
                )
            )
            let exports = try await SensorKitExporterFixtures.collect(
                SensorKitExporterFixtures.exporter(producer),
                [entry.record],
                timeZone: SensorKitExporterFixtures.timeZone,
                recordingDevice: RecordingDevice.test(stableUnitToken: "sensor-fixture-device", name: "Sensor Fixture Device"),
                at: timestamp.addingTimeInterval(20)
            ).exports
            fixtures[entry.name] = try #require(exports.first?.graph).bundle
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]

        try FileManager.default.createDirectory(at: Self.fixtureDirectory, withIntermediateDirectories: true)
        for (name, bundle) in fixtures {
            try encoder.encode(bundle).write(to: Self.fixtureDirectory.appendingPathComponent("\(name).json"))
        }
        #expect(fixtures.count == 12)
    }
}
