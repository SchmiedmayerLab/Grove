//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SensorKit)

import Foundation
@testable import GroveSensorKit
@testable import GroveSensorKitFHIR
import ModelsR4
import SensorKit
import Testing


@Suite
struct SensorKitObservationTests {
    /// A fixed key, so the identifiers below stay comparable within a run. Two deployments
    /// with different keys deliberately produce different identifiers for the same sample.
    private static let key = SensorKitIdentifierKey(secret: "test-deployment")
    private static let subject = Reference(reference: "Patient/test-participant")

    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/conformance-fixtures")
    }

    /// The IG publishes the sensor codes as literals; SensorKit owns the actual raw
    /// values. This pins them together — if Apple renames a sensor, the vocabulary and
    /// the emitted observations move as one and this test says so.
    @Test
    func sensorIdentifiersMatchThePublishedVocabulary() {
        // These are the exact codes the sensorkit-sample-type code system publishes.
        // SensorKit's raw values are not derivable from the Swift case names — `onWrist`
        // is `onWristState`, `ambientLight` is `als` — so they are pinned here rather
        // than guessed by the IG author.
        let published: [(SRSensor, String)] = [
            (Sensor.onWrist.srSensor, "com.apple.SensorKit.onWristState"),
            (Sensor.visits.srSensor, "com.apple.SensorKit.visits"),
            (Sensor.deviceUsage.srSensor, "com.apple.SensorKit.deviceUsageReport"),
            (Sensor.ecg.srSensor, "com.apple.SensorKit.ECG"),
            (Sensor.ppg.srSensor, "com.apple.SensorKit.PPG"),
            (Sensor.heartRate.srSensor, "com.apple.SensorKit.heart.rate"),
            (Sensor.wristTemperature.srSensor, "com.apple.SensorKit.wristTemperature"),
            (Sensor.pedometer.srSensor, "com.apple.SensorKit.pedometer.data"),
            (Sensor.accelerometer.srSensor, "com.apple.SensorKit.motion.accelerometer"),
            (Sensor.ambientLight.srSensor, "com.apple.SensorKit.als"),
            (Sensor.ambientPressure.srSensor, "com.apple.SensorKit.ambientPressure")
        ]
        for (sensor, code) in published {
            #expect(sensor.rawValue == code, "the published code must match the sensor's raw value")
        }
    }

    @Test
    func sampleIdentifiersAreDeterministicAndContentAddressed() {
        func hash(_ steps: Int) -> String {
            var hasher = SensorKitSampleIDHasher(key: Self.key)
            hasher.combine("stream")
            hasher.combine(steps)
            return hasher.finalize().uuidString
        }
        let expected = hash(42)
        #expect(hash(42) == expected, "the same content must always yield the same identifier")
        #expect(hash(42) != hash(43), "different content must not collide")
        // The separator prevents ("ab","c") and ("a","bc") from hashing alike.
        func hash(_ first: String, _ second: String) -> String {
            var hasher = SensorKitSampleIDHasher(key: Self.key)
            hasher.combine(first)
            hasher.combine(second)
            return hasher.finalize().uuidString
        }
        #expect(hash("ab", "c") != hash("a", "bc"))
    }

    @Test
    func identifierKeysRejectKeyMaterialTooShortToUnlink() throws {
        #expect(throws: SensorKitIdentifierKey.KeyError.self) {
            try SensorKitIdentifierKey(keyMaterial: Data(repeating: 0xA5, count: 31))
        }
        let key = try SensorKitIdentifierKey(keyMaterial: Data(repeating: 0xA5, count: 32))
        var hasher = SensorKitSampleIDHasher(key: key)
        hasher.combine("stream")
        var other = SensorKitSampleIDHasher(key: Self.key)
        other.combine("stream")
        #expect(hasher.finalize() != other.finalize(), "two deployments must not share identifiers")
    }

    @Test
    func wearStateObservationCarriesCodedValueAndPlacement() throws {
        let now = Date()
        let sample = SensorKitOnWristEventSample(
            timestamp: now,
            onWrist: true,
            wristLocation: .left,
            crownOrientation: .right,
            onWristDate: now,
            offWristDate: nil
        )
        let observation = try sample.observation(identifierKey: Self.key, subject: Self.subject)
        #expect(observation.code.coding?.first?.system?.value?.url.absoluteString
            == "https://grovealliance.org/fhir/platforms/CodeSystem/sensorkit-sample-type")
        #expect(observation.identifier?.first?.system?.value?.url.absoluteString
            == "https://grovealliance.org/fhir/sid/sensorkit-sample-id")
        // The profile pins subject 1..1, so an observation can never leave without one.
        #expect(observation.subject?.reference?.value?.string == "Patient/test-participant")
        guard case let .codeableConcept(value) = observation.value else {
            Issue.record("Expected a coded wear state")
            return
        }
        #expect(value.coding?.first?.code?.value?.string == "on-wrist")
        let componentCodes = (observation.component ?? []).compactMap { $0.code.coding?.first?.code?.value?.string }
        #expect(componentCodes == ["wrist-location", "crown-orientation"])
        // Placement is coded, never a bare string.
        for component in observation.component ?? [] {
            guard case .codeableConcept = component.value else {
                Issue.record("Placement components must carry coded values")
                return
            }
        }
    }

    @Test
    func deviceUsageObservationSummarizesWithCodedComponents() throws {
        let start = Date()
        let sample = SRDeviceUsageReport.SafeRepresentation(
            timestamp: start,
            duration: 900,
            totalScreenWakes: 6,
            totalUnlocks: 4,
            totalUnlockDuration: 372,
            version: "1",
            appUsageByCategory: [:],
            notificationUsageByCategory: [:],
            webUsageByCategory: [:]
        )
        let observation = try sample.observation(identifierKey: Self.key, subject: Self.subject)
        guard case let .quantity(value) = observation.value else {
            Issue.record("Expected the unlock duration as the value")
            return
        }
        #expect(value.code?.value?.string == "s")
        #expect(value.value?.value?.decimal == 372)
        let components = try #require(observation.component)
        #expect(components.count == 2)
        for component in components {
            guard case let .quantity(quantity) = component.value else {
                Issue.record("Usage counters must be quantities")
                return
            }
            #expect(quantity.code?.value?.string == "{count}")
        }
        guard case .period = observation.effective else {
            Issue.record("A reporting period must be a period")
            return
        }
    }

    @Test
    func writeConformanceFixtures() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = SensorKitOnWristEventSample(
            timestamp: timestamp,
            onWrist: true,
            wristLocation: .left,
            crownOrientation: .right,
            onWristDate: timestamp,
            offWristDate: nil
        )
        let resource = ResourceProxy(with: try sample.observation(identifierKey: Self.key, subject: Self.subject))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try FileManager.default.createDirectory(at: Self.fixtureDirectory, withIntermediateDirectories: true)
        try encoder.encode(resource).write(to: Self.fixtureDirectory.appendingPathComponent("sensorkit-on-wrist.json"))
    }
}

#endif
