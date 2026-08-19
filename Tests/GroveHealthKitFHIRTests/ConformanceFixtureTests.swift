//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// Writes one resource per shape the converter produces, for the HL7 validator to check
/// against the profiles the guides publish.
///
/// The unit tests check the converter and the IG Publisher checks the guides' hand-written
/// examples; neither crosses the gap between them, which is how a release once shipped
/// observations that declared a profile they violated. `Scripts/validate-fhir-conformance.sh`
/// runs this and then validates what it wrote.
@Suite
struct ConformanceFixtureTests {
    /// Where the fixtures land, derived from this file's own path: `xcodebuild` does not
    /// forward the shell's environment into the test process.
    static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/conformance-fixtures")
    }

    private static let subject = Reference(reference: "Patient/example")

    private static var device: HKDevice {
        HKDevice(
            name: "Apple Watch",
            manufacturer: "Apple Inc.",
            model: "Watch7,12",
            hardwareVersion: "Watch7,12",
            firmwareVersion: "1.0",
            softwareVersion: "26.2.1",
            localIdentifier: "6C4B1D1E-0000-4000-8000-000000000001",
            udiDeviceIdentifier: nil
        )
    }

    @Test
    func writeConformanceFixtures() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let start = try #require(calendar.date(from: .init(year: 2026, month: 8, day: 14, hour: 9)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]

        var fixtures: [String: ResourceProxy] = [:]
        fixtures["heart-rate"] = try HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: start,
            end: start.addingTimeInterval(900),
            device: Self.device,
            metadata: [
                HKMetadataKeyHeartRateMotionContext: NSNumber(value: 1),
                HKMetadataKeyExternalUUID: "ext-1",
                HKMetadataKeyTimeZone: "America/Los_Angeles"
            ]
        ).resource(subject: Self.subject)

        fixtures["step-count"] = try HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 431),
            start: start,
            end: start.addingTimeInterval(3600),
            device: Self.device,
            metadata: [HKMetadataKeyWasUserEntered: true]
        ).resource(subject: Self.subject)

        fixtures["sleep-analysis"] = try HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            start: start,
            end: start.addingTimeInterval(1800),
            device: Self.device,
            metadata: [:]
        ).resource(subject: Self.subject)

        fixtures["state-of-mind"] = try HKStateOfMind(
            date: start,
            kind: .momentaryEmotion,
            valence: 0.6,
            labels: [.content],
            associations: [.work]
        ).resource(subject: Self.subject)

        let directory = Self.fixtureDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, resource) in fixtures {
            try encoder.encode(resource).write(to: directory.appendingPathComponent("\(name).json"))
        }
        #expect(fixtures.count == 4)
    }
}

#endif
