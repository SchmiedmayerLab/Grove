//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
@testable import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


/// One SensorKit golden: a fixed record exported alone through `SensorKitFHIRExporter`, under the name its graph is
/// checked in as. The cases cover each output shape once: a structured Observation, a hybrid Observation with its
/// native recording, a visit's location focus, and a raw-only recording whose payload ships as a sidecar.
struct SensorKitGoldenCase: Sendable, CustomTestStringConvertible {
    private static let start = SensorKitExporterFixtures.start

    static let all: [SensorKitGoldenCase] = [
        SensorKitGoldenCase(name: "rotation-rate") {
            .rotationRate(SensorKitRotationRateRecord(sourceRecordID: SensorKitGoldenCase.sourceID(1), samples: [
                .init(timestamp: SensorKitGoldenCase.start, x: 0.01, y: -0.02, z: 0.03),
                .init(timestamp: SensorKitGoldenCase.start.addingTimeInterval(0.01), x: 0.02, y: -0.01, z: 0.04),
                .init(timestamp: SensorKitGoldenCase.start.addingTimeInterval(0.02), x: 0.01, y: -0.01, z: 0.02)
            ]))
        },
        SensorKitGoldenCase(name: "electrocardiogram") {
            .electrocardiogram(SensorKitECGRecord(
                sourceRecordID: SensorKitGoldenCase.sourceID(2),
                startDate: SensorKitGoldenCase.start,
                durationSeconds: 0.006,
                frequencyHertz: 500,
                lead: .leftArmMinusRightArm,
                guidance: .guided,
                batches: [.init(offsetSeconds: 0, millivolts: [0.011, 0.023]), .init(offsetSeconds: 0.004, millivolts: [-0.005, 0.014])],
                nativeRecording: try SensorKitNativeRecording(
                    title: "Exact SensorKit ECG session",
                    format: .nativeRecording,
                    payload: .inline(Data(#"{"flags":[0,2,1,0]}"#.utf8)),
                    admission: .verifiedSanitizedInput
                )
            ))
        },
        SensorKitGoldenCase(name: "visit") {
            .visit(SensorKitVisitRecord(
                sourceRecordID: SensorKitGoldenCase.sourceID(3),
                locationCategory: .work,
                distanceFromHomeMeters: 1_250,
                arrivalWindow: DateInterval(start: SensorKitGoldenCase.start, duration: 60),
                departureWindow: DateInterval(start: SensorKitGoldenCase.start.addingTimeInterval(3_600), duration: 60),
                locationID: UUID(uuid: (0x6f, 0x26, 0x92, 0xc2, 0x7a, 0x8e, 0x45, 0xdb, 0x8f, 0x2f, 0x33, 0x00, 0x15, 0x7f, 0xc0, 0xb4))
            ))
        },
        SensorKitGoldenCase(name: "raw-heart-rate-sidecar") {
            .raw(try SensorKitRawRecord(
                sourceRecordID: SensorKitGoldenCase.sourceID(4),
                sourceToken: "SRSensor.heartRate",
                effectivePeriod: DateInterval(start: SensorKitGoldenCase.start, duration: 1),
                nativeRecording: try SensorKitNativeRecording(
                    title: "Exact SensorKit heart rate batch",
                    format: .heartRateSamples,
                    payload: .sidecar(
                        path: "sensorkit/heart-rate.csv",
                        bytes: Data("timestamp,value,confidence,device\n1787009400,72,3,Watch\n".utf8)
                    ),
                    admission: .verifiedSanitizedInput
                )
            ))
        }
    ]

    let name: String
    let record: @Sendable () throws -> SensorKitRecord

    var testDescription: String { name }

    private static func sourceID(_ ordinal: UInt8) -> SensorKitSourceRecordID {
        SensorKitSourceRecordID(UUID(uuid: (0x5e, 0x9b, 0x0c, 0x41, 0x6a, 0x2d, 0x4f, 0x83, 0x9a, 0x17, 0x40, 0x8e, 0x21, 0xd3, 0x6c, ordinal)))
    }

    /// The case's graph as checked in: its Bundle with sorted members, pretty-printed and without escaped slashes,
    /// the same tokens as the wire bytes `ExchangeGraph.json` encodes, so a change diffs by line.
    func checkedInBytes() async throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(await SensorKitExporterFixtures.graph(record()).bundle)
    }
}


/// One checked-in SensorKit golden, its SHA-256 (base64url without padding), and the output revisions it last changed
/// under.
struct SensorKitGoldenRevision: Sendable, CustomTestStringConvertible {
    let name: String
    let digest: String
    let assembler: UInt
    let sensorKit: UInt

    var testDescription: String { name }
}


/// Pins the SensorKit exporter's wire output, and ties it to the output revisions its context fingerprint states.
///
/// An exact redelivery is byte-identical only while the exporter emits the same bytes for equal inputs, so a change
/// to a golden must bump `ExchangeGraphAssembler.outputRevision` or `SensorKitConverter.outputRevision`, which the
/// updated row records and review checks; a new golden adds a row without a bump. The goldens regenerate OUTSIDE the
/// checkout: `GROVE_SENSORKIT_GOLDEN_OUTPUT_DIR` (under `xcodebuild`, `TEST_RUNNER_GROVE_SENSORKIT_GOLDEN_OUTPUT_DIR`)
/// names a directory the run writes every case into, then copy them into `Resources/Goldens/`. A regeneration run
/// compares nothing, so it fails on purpose.
@Suite
struct SensorKitGoldenTests {
    static let table = [
        SensorKitGoldenRevision(name: "electrocardiogram", digest: "S4eTrrLPzGe2TvmbgbDj0Jdx3p5Q-A4xRiGb7psrBnc", assembler: 1, sensorKit: 1),
        SensorKitGoldenRevision(name: "raw-heart-rate-sidecar", digest: "NZ-279Qdy3gKOkYgnuMhy9N3feCjt-42X-uDmy46SA4", assembler: 1, sensorKit: 1),
        SensorKitGoldenRevision(name: "rotation-rate", digest: "kFulmUsc59LiBPyZl1D063BDF1lssj86fKlr6Nx1f0A", assembler: 1, sensorKit: 1),
        SensorKitGoldenRevision(name: "visit", digest: "Kb4A63TBPIEE2mTO2tTO7k6o4TnMWwkr6936ti48gc0", assembler: 1, sensorKit: 1)
    ]

    private static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["GROVE_SENSORKIT_GOLDEN_OUTPUT_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The directory holding `Package.swift` above this file, which a regeneration must not write into: Xcode
    /// re-resolves the package mid-run when files appear in it.
    private static var checkout: URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.pathComponents.count > 1,
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            directory.deleteLastPathComponent()
        }
        return directory.resolvingSymlinksInPath()
    }

    private static func checkedIn(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Goldens")
                ?? Bundle.module.url(forResource: name, withExtension: "json"),
            "No \(name).json is checked in; regenerate with GROVE_SENSORKIT_GOLDEN_OUTPUT_DIR and copy it into Resources/Goldens"
        )
        return try Data(contentsOf: url)
    }

    @Test("A SensorKit graph matches its checked-in golden", arguments: SensorKitGoldenCase.all)
    func matchesItsGolden(_ goldenCase: SensorKitGoldenCase) async throws {
        let bytes = try await goldenCase.checkedInBytes()
        if let directory = Self.outputDirectory {
            let resolved = directory.resolvingSymlinksInPath()
            try #require(!resolved.path.hasPrefix(Self.checkout.path + "/"), "\(resolved.path) lies inside the checkout")
            try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
            try bytes.write(to: resolved.appendingPathComponent("\(goldenCase.name).json"))
            Issue.record("Regenerated \(goldenCase.name); this run compared nothing")
            return
        }
        #expect(bytes == (try Self.checkedIn(goldenCase.name)), "\(goldenCase.name) drifted from its golden")
    }

    @Test("Every case has a row, every row a case, and each golden's bytes match its row's revisions", arguments: SensorKitGoldenTests.table)
    func goldenMatchesItsRevision(_ row: SensorKitGoldenRevision) throws {
        #expect(Set(Self.table.map(\.name)) == Set(SensorKitGoldenCase.all.map(\.name)))
        #expect(Set(Self.table.map(\.name)).count == Self.table.count, "a golden is named twice")
        let digest = Data(SHA256.hash(data: try Self.checkedIn(row.name))).base64URLEncodedStringWithoutPadding
        #expect(digest == row.digest, "\(row.name) changed to \(digest): update its row, with the bumped output revision if an output changed")
        #expect(row.assembler <= ExchangeGraphAssembler.outputRevision)
        #expect(row.sensorKit <= SensorKitConverter.outputRevision)
    }
}
