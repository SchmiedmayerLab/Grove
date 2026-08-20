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

    private static func sourceID(_ value: String) throws -> GroveSensorKitSourceRecordID {
        GroveSensorKitSourceRecordID(try #require(UUID(uuidString: value)))
    }

    private static func nativeRecording(title: String) throws -> GroveSensorKitNativeRecording {
        try GroveSensorKitNativeRecording(
            title: title,
            contentType: "application/json",
            payload: .inline(Data(#"{"source":"SensorKit","complete":true}"#.utf8)),
            admission: .verifiedSanitizedInput
        )
    }

    @Test
    func writeSharedSensorFixtures() throws {
        let timestamp = Date(timeIntervalSince1970: 1_787_009_400)
        let converter = GroveSensorKitFHIRConverter()
        let context = GroveSensorKitFHIRConversionContext(
            subject: Reference(reference: "Patient/example"),
            converter: GroveSensorFHIRApplication(
                identifier: try GroveFHIRBusinessIdentifier(
                    system: "https://study.example.org/fhir/identifiers/application",
                    value: "sensor-conformance|0.2.0"
                ),
                name: "Sensor Conformance Fixture",
                version: "0.2.0"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/sensor-graph",
            recordingDevice: GroveSensorFHIRRecordingDevice(
                identifier: try GroveFHIRBusinessIdentifier(
                    system: "https://study.example.org/fhir/identifiers/recording-device",
                    value: "sensor-fixture-device"
                ),
                name: "Sensor Fixture Device"
            ),
            converterWasGateway: true,
            sourceTimeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
            issuedAt: timestamp.addingTimeInterval(10),
            recordedAt: timestamp.addingTimeInterval(20)
        )
        let rotation = GroveSensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID("754cdecc-6733-4610-935b-f19425cff68e"),
            samples: [
                .init(timestamp: timestamp, x: 0.1, y: 0.2, z: 0.3),
                .init(timestamp: timestamp.addingTimeInterval(0.01), x: 0.4, y: 0.5, z: 0.6),
                .init(timestamp: timestamp.addingTimeInterval(0.02), x: 0.7, y: 0.8, z: 0.9)
            ]
        )
        let ecg = GroveSensorKitECGRecord(
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
        let onWrist = GroveSensorKitOnWristRecord(
            sourceRecordID: try Self.sourceID("539bfe8c-ce3c-4410-a9a7-d133bc6d5230"),
            timestamp: timestamp,
            onWrist: true,
            currentStateStart: timestamp.addingTimeInterval(-120),
            wristLocation: .left,
            crownOrientation: .right
        )
        let deviceUsage = GroveSensorKitDeviceUsageRecord(
            sourceRecordID: try Self.sourceID("c014060e-284c-47e3-a0f8-e6ba029ae950"),
            timestamp: timestamp,
            durationSeconds: 300,
            totalScreenWakes: 3,
            totalUnlocks: 2,
            totalUnlockDurationSeconds: 42.5,
            nativeRecording: try Self.nativeRecording(title: "Exact SensorKit device usage report")
        )
        let visit = GroveSensorKitVisitRecord(
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
        let raw = GroveSensorKitRawRecord(
            sourceRecordID: try Self.sourceID("248b854a-8d64-4308-9ee0-d220e7d747d3"),
            sourceToken: "SRSensor.photoplethysmogram",
            nativeRecording: try Self.nativeRecording(title: "Exact SensorKit PPG record")
        )
        let fixtures = [
            "rotation-rate": try converter.convert(.rotationRate(rotation), context: context).bundle,
            "ecg-hybrid": try converter.convert(.electrocardiogram(ecg), context: context).bundle,
            "on-wrist": try converter.convert(.onWrist(onWrist), context: context).bundle,
            "device-usage-hybrid": try converter.convert(.deviceUsage(deviceUsage), context: context).bundle,
            "visit": try converter.convert(.visit(visit), context: context).bundle,
            "raw-recording": try converter.convert(.raw(raw), context: context).bundle
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]

        try FileManager.default.createDirectory(at: Self.fixtureDirectory, withIntermediateDirectories: true)
        for (name, bundle) in fixtures {
            try encoder.encode(bundle).write(to: Self.fixtureDirectory.appendingPathComponent("\(name).json"))
        }
        #expect(fixtures.count == 6)
    }
}
