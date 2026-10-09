//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// CPU-time benchmark of the SensorKit -> FHIR path, one core. It never runs in a normal test run: the suite is
// enabled only when GROVE_SENSORKIT_BENCH_RUN=1 reaches the test process.
//
// Each scenario is one batch shape MyHeartCounts exports, taken through the steps an app runs: writing the recording
// ("write": the CSV writer and the registry check `SensorKitTabularRecording` runs, or `SensorKitPPGRecording.prepared()`),
// building the exporter input ("record": what `sensorKitRecord(...)` does) and one export call on one core ("export").
// The tabular recording type is iOS-only, so its two steps are reproduced from the same calls it makes.
//
// Run it in RELEASE mode, the only configuration whose numbers mean anything (`xcodebuild` forwards only
// TEST_RUNNER_-prefixed variables into the test process; Release needs testability for @testable):
//
//   cd <checkout> && GROVE_LOWERED_DEPLOYMENT_TARGETS=0 GROVE_ENABLE_DEFAULT_PACKAGE_TRAITS=1 GROVE_EXCLUDE_DOCC_CATALOGS=1 \
//     TEST_RUNNER_GROVE_SENSORKIT_BENCH_RUN=1 \
//     xcodebuild test -scheme Grove-Tests -testPlan GroveSensorKitFHIR \
//       -only-testing:GroveSensorKitFHIRTests/SensorKitThroughputBenchmark \
//       -configuration Release ENABLE_TESTABILITY=YES ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=26.0 \
//       -destination 'platform=macOS' -skipMacroValidation -skipPackagePluginValidation 2>&1 | grep '^BENCH\|error:'
//
// Environment (TEST_RUNNER_-prefixed under xcodebuild):
//   GROVE_SENSORKIT_BENCH_RUN=1                 enable
//   GROVE_SENSORKIT_BENCH_RUNS=3                timed repetitions per scenario; the fastest is reported
//   GROVE_SENSORKIT_BENCH_ONLY=name             run only this scenario
//   GROVE_SENSORKIT_BENCH_PROFILE=name          loop that scenario for an external profiler instead
//   GROVE_SENSORKIT_BENCH_PROFILE_SECONDS=25    how long that loop runs
//
// The scenario names (accelerometer, heartRate, ambientLight, wristTemperature, ppg) and the result-line format are
// fixed so runs stay comparable.

import Foundation
@testable import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


private enum SensorKitBenchEnvironment {
    static let environment = ProcessInfo.processInfo.environment
    static let isEnabled = environment["GROVE_SENSORKIT_BENCH_RUN"] == "1"
    static let runs = environment["GROVE_SENSORKIT_BENCH_RUNS"].flatMap(Int.init) ?? 3
    static let only = environment["GROVE_SENSORKIT_BENCH_ONLY"]
    static let profile = environment["GROVE_SENSORKIT_BENCH_PROFILE"]
    static let profileSeconds = environment["GROVE_SENSORKIT_BENCH_PROFILE_SECONDS"].flatMap(Double.init) ?? 25
}


@Suite(.enabled(if: SensorKitBenchEnvironment.isEnabled))
struct SensorKitThroughputBenchmark {
    /// One batch shape: `records` recordings of `rows` rows each, exported in one call.
    private struct Scenario {
        let name: String
        let records: Int
        let rows: Int
        /// Writes recording `index` as an app does before it hands it to Grove.
        let write: (_ index: Int) throws -> Written
        /// Builds the exporter input from a written recording.
        let record: (_ index: Int, _ written: Written) throws -> SensorKitRecord
    }

    private enum Written {
        case tabular(Data, DateInterval)
        case ppg(SensorKitPreparedPPGRecording)

        var byteCount: Int {
            switch self {
            case let .tabular(data, _): data.count
            case let .ppg(prepared): prepared.data.count
            }
        }
    }

    private struct Timing {
        let write: UInt64
        let record: UInt64
        let export: UInt64
        let payloadBytes: Int
        let graphBytes: Int
        let refusals: Int

        var total: UInt64 {
            write + record + export
        }
    }

    private static let start = Date(timeIntervalSince1970: 1_787_009_400)
    private static let watch = "Watch7,1"

    private static func report(_ scenario: Scenario, _ timing: Timing) {
        let rows = Double(scenario.records * scenario.rows)
        func perRow(_ nanoseconds: UInt64) -> String {
            String(format: "%.3f", Double(nanoseconds) / 1_000 / rows)
        }
        func perRecord(_ nanoseconds: UInt64) -> String {
            String(format: "%.1f", Double(nanoseconds) / 1_000 / Double(scenario.records))
        }
        print(
            "BENCH sensorkit scenario=\(scenario.name) records=\(scenario.records) rows=\(scenario.rows)"
                + " us_per_row total=\(perRow(timing.total)) write=\(perRow(timing.write)) record=\(perRow(timing.record))"
                + " export=\(perRow(timing.export)) | us_per_record total=\(perRecord(timing.total)) export=\(perRecord(timing.export))"
                + " | payload_bytes_per_row=\(timing.payloadBytes / (scenario.records * scenario.rows))"
                + " graph_bytes_per_record=\(timing.graphBytes / scenario.records) refusals=\(timing.refusals)"
        )
    }

    /// One batch through all three steps, timed in process CPU time.
    private static func pass(_ scenario: Scenario) async throws -> Timing {
        let writeStart = cpuTime()
        let written = try (0..<scenario.records).map(scenario.write)
        let recordStart = cpuTime()
        let records = try written.enumerated().map { try scenario.record($0.offset, $0.element) }
        let exporter = try exporter()
        let exportStart = cpuTime()
        var graphBytes = 0
        var refusals = 0
        _ = try await exporter.export(
            records,
            sourceTimeZone: SensorKitExporterFixtures.timeZone,
            at: SensorKitExporterFixtures.instant
        ) { export in
            switch export.outcome {
            case .graph(let graph):
                graphBytes += graph.json.count
            case .refused:
                refusals += 1
            }
        }
        let exportEnd = cpuTime()
        return Timing(
            write: recordStart - writeStart,
            record: exportStart - recordStart,
            export: exportEnd - exportStart,
            payloadBytes: written.reduce(0) { $0 + $1.byteCount },
            graphBytes: graphBytes,
            refusals: refusals
        )
    }

    private static func cpuTime() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
    }

    /// MyHeartCounts' exporter shape, held to one core.
    private static func exporter() throws -> SensorKitFHIRExporter {
        var options = SensorKitFHIRExporter.Options()
        options.nativeIdentifier = .authorized(system: SensorKitExporterFixtures.nativeSystem)
        options.maximumConcurrency = 1
        return try SensorKitFHIRExporter(
            producer: SensorKitExporterFixtures.producer(),
            repositoryScope: SensorFHIRIdentityTestSupport.repositoryScope,
            visitLocationIdentifierSystem: SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem,
            options: options
        )
    }

    @Test
    func sensorKitBatches() async throws {
        let scenarios = Self.scenarios().filter { SensorKitBenchEnvironment.only == nil || SensorKitBenchEnvironment.only == $0.name }
        if let profiled = SensorKitBenchEnvironment.profile {
            let scenario = try #require(scenarios.first { $0.name == profiled })
            _ = try await Self.pass(scenario)
            print("BENCH sensorkit profile scenario=\(profiled) pid=\(ProcessInfo.processInfo.processIdentifier)")
            let deadline = Date().addingTimeInterval(SensorKitBenchEnvironment.profileSeconds)
            while Date() < deadline {
                _ = try await Self.pass(scenario)
            }
            return
        }
        for scenario in scenarios {
            _ = try await Self.pass(scenario)
            var best = try await Self.pass(scenario)
            for _ in 1..<max(SensorKitBenchEnvironment.runs, 1) {
                let timing = try await Self.pass(scenario)
                if timing.total < best.total {
                    best = timing
                }
            }
            #expect(best.refusals == 0)
            Self.report(scenario, best)
        }
    }
}


// MARK: - Scenarios

extension SensorKitThroughputBenchmark {
    private static func scenarios() -> [Scenario] {
        let values = pseudorandom(count: 90_000)
        return [
            tabular("accelerometer", records: 4, rows: 30_000, format: .triaxialAccelerationSamples, interval: 0.02) { row, timestamp in
                [
                    .timestamp(timestamp), .text(String(row + 1)), .number(values[row * 3]), .number(values[row * 3 + 1]),
                    .number(values[row * 3 + 2]), .text(watch)
                ]
            } record: { sourceRecordID, nativeRecording, _ in
                .accelerometer(try SensorKitAccelerometerRecord(sourceRecordID: sourceRecordID, nativeRecording: nativeRecording))
            },
            tabular("heartRate", records: 4, rows: 3_600, format: .heartRateSamples, interval: 1) { row, timestamp in
                [.timestamp(timestamp), .number(60 + 40 * abs(values[row])), .integer(row % 4), .text(watch)]
            } record: { sourceRecordID, nativeRecording, period in
                .raw(try SensorKitRawRecord(
                    sourceRecordID: sourceRecordID,
                    sourceToken: "SRSensor.heartRate",
                    effectivePeriod: period,
                    nativeRecording: nativeRecording
                ))
            },
            tabular("ambientLight", records: 4, rows: 720, format: .ambientLightSamples, interval: 120) { row, timestamp in
                [
                    .timestamp(timestamp), .number(500 * abs(values[row * 2])), .text("frontTop"), .number(abs(values[row * 2])),
                    .number(abs(values[row * 2 + 1])), .text("iPhone17,2")
                ]
            } record: { sourceRecordID, nativeRecording, period in
                .raw(try SensorKitRawRecord(
                    sourceRecordID: sourceRecordID,
                    sourceToken: "SRSensor.ambientLightSensor",
                    effectivePeriod: period,
                    nativeRecording: nativeRecording
                ))
            },
            tabular("wristTemperature", records: 4, rows: 100, format: .wristTemperatureSamples, interval: 300) { row, timestamp in
                [
                    .timestamp(timestamp), .number(33 + values[row]), .number(0.1 + abs(values[row + 1]) / 10),
                    .text(row.isMultiple(of: 7) ? "inMotion" : "")
                ]
            } record: { sourceRecordID, nativeRecording, _ in
                .wristTemperature(try SensorKitWristTemperatureRecord(
                    sourceRecordID: sourceRecordID,
                    algorithmVersion: "1.0",
                    nativeRecording: nativeRecording
                ))
            },
            ppg(records: 4, rows: 3_000, values: values)
        ]
    }

    /// A tabular batch as `SensorKitTabularRecording` writes it and `sensorKitRecord(...)` hands it on.
    private static func tabular( // swiftlint:disable:this function_parameter_count
        _ name: String,
        records: Int,
        rows: Int,
        format: RegisteredRecordingFormat,
        interval: TimeInterval,
        row: @escaping (Int, Date) -> [RecordingCSVWriter.Field],
        record: @escaping (SensorKitSourceRecordID, SensorKitNativeRecording, DateInterval) throws -> SensorKitRecord
    ) -> Scenario {
        Scenario(name: name, records: records, rows: rows) { index in
            let first = start.addingTimeInterval(Double(index * rows) * interval)
            var writer = try RecordingCSVWriter(format: format)
            for offset in 0..<rows {
                try writer.append(row(offset, first.addingTimeInterval(Double(offset) * interval)))
            }
            let data = writer.data()
            try format.validatePayload(data)
            return .tabular(data, DateInterval(start: first, duration: Double(rows - 1) * interval))
        } record: { index, written in
            guard case let .tabular(data, period) = written else {
                throw CocoaError(.featureUnsupported)
            }
            // The tabular recording validated these bytes when it was written, so it hands them on unchecked.
            let nativeRecording = try SensorKitNativeRecording(
                title: "\(name) batch \(index)",
                format: format,
                payload: .sidecar(path: "sensorkit/\(name)-\(index).\(format.fileExtension)", bytes: data),
                admission: .callerAuthorizedOpaquePayload
            ) { _ in }
            return try record(sourceRecordID(index), nativeRecording, period)
        }
    }

    /// A PPG batch of `rows` SensorKit samples, each with four optical and two accelerometer samples.
    private static func ppg(records: Int, rows: Int, values: [Double]) -> Scenario {
        Scenario(name: "ppg", records: records, rows: rows) { index in
            let first = start.addingTimeInterval(Double(index) * 600)
            let samples = (0..<rows).map { ppgSample(first: first, row: $0, values: values) }
            return .ppg(try SensorKitPPGRecording(records: samples).prepared())
        } record: { index, written in
            guard case let .ppg(prepared) = written else {
                throw CocoaError(.featureUnsupported)
            }
            return try prepared.sensorKitRecord(
                sourceRecordID: sourceRecordID(index),
                title: "ppg batch \(index)",
                location: .sidecar(path: "sensorkit/ppg-\(index).bin"),
                admission: .callerAuthorizedOpaquePayload
            )
        }
    }

    private static func ppgSample(first: Date, row: Int, values: [Double]) -> SensorKitPPGRecording.Record {
        let offset = Int64(row) * 200_000_000
        return SensorKitPPGRecording.Record(
            startDate: first,
            nanosecondsSinceStart: offset,
            temperature: 31.5 + values[row] / 10,
            usage: ["foreground"],
            opticalSamples: (0..<4).map { channel in
                SensorKitPPGRecording.OpticalSample(
                    emitter: Int64(channel % 2 + 1),
                    activePhotodiodeIndexes: [1, 3],
                    signalIdentifier: Int64(channel),
                    nominalWavelength: 525,
                    effectiveWavelength: 524.5,
                    samplingFrequency: 128,
                    nanosecondsSinceStart: offset + Int64(channel) * 1_000_000,
                    conditions: [],
                    noiseTerms: .init(whiteNoise: abs(values[row + channel]), pinkNoise: 0.2, backgroundNoise: 0.3, backgroundNoiseOffset: 0.4),
                    normalizedReflectance: abs(values[row * 2 + channel])
                )
            },
            accelerometerSamples: (0..<2).map { sample in
                SensorKitPPGRecording.AccelerometerSample(
                    nanosecondsSinceStart: offset + Int64(sample) * 7_812_500,
                    samplingFrequency: 64,
                    x: values[row * 3],
                    y: values[row * 3 + 1],
                    z: values[row * 3 + 2]
                )
            }
        )
    }

    private static func sourceRecordID(_ index: Int) throws -> SensorKitSourceRecordID {
        SensorKitSourceRecordID(try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", index))))
    }

    /// Values in [-1, 1) from a fixed linear congruential sequence, so every run writes the same bytes.
    private static func pseudorandom(count: Int) -> [Double] {
        var state: UInt64 = 1
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
    }
}
