//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


struct TabularFilePreparationTests {
    private struct Sample: SensorKitTabularSample {
        static let groveSourceToken = "SRSensor.accelerometer"
        static let groveRecordingFormat = RegisteredRecordingFormat.triaxialAccelerationSamples
        let timestamp: Date
        let batch: UInt64
        var value: Double = 0.1
        var timeRange: Range<Date> { timestamp..<timestamp }

        func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
            [.timestamp(timestamp), .text(String(batch)), .number(value), .number(0.2), .number(0.3), .text(deviceProductType)]
        }
    }

    /// Iteration consumes shared state; any second traversal sees no samples.
    private final class OnePassSamples: Sequence, IteratorProtocol {
        private var samples: Array<Sample>.Iterator
        init(_ samples: [Sample]) { self.samples = samples.makeIterator() }
        func makeIterator() -> OnePassSamples { self }
        func next() -> Sample? { samples.next() }
    }

    @Test
    func filePreparationPreservesBytesEvidencePeriodAndFHIR() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000.1234)
        let samples = [
            Sample(timestamp: start.addingTimeInterval(2), batch: 7),
            Sample(timestamp: start, batch: 8), Sample(timestamp: start.addingTimeInterval(1), batch: 7)
        ]
        let memory = try SensorKitTabularRecording(samples: samples, deviceProductType: "Watch,é")
        let disk = try SensorKitTabularRecording.File(samples: OnePassSamples(samples), deviceProductType: "Watch,é", maximumByteCount: 4096)
        var bytes = Data()
        try disk.file.readChunks { bytes.append($0) }
        var evidence = Data()
        try disk.readRetryEvidenceChunks { evidence.append($0) }
        #expect(bytes == memory.data && evidence == memory.retryEvidence)
        #expect(disk.sourceToken == memory.sourceToken && disk.format == memory.format)
        #expect(disk.effectivePeriod == memory.effectivePeriod)
        let sourceID = SensorKitSourceRecordID(UUID())
        let dataRecord = try memory.sensorKitRecord(
            sourceRecordID: sourceID, title: "Acceleration", location: .sidecar(path: "recordings/a.csv"), admission: .verifiedSanitizedInput
        )
        let fileRecord = try disk.sensorKitRecord(
            sourceRecordID: sourceID, title: "Acceleration", sidecarPath: "recordings/a.csv", admission: .verifiedSanitizedInput
        )
        let expected = try await SensorKitExporterFixtures.record(dataRecord)
        let actual = try await SensorKitExporterFixtures.record(fileRecord)
        #expect(actual.json == expected.json)
        guard case .accelerometer(let summary) = fileRecord else {
            Issue.record("Expected accelerometer summary")
            return
        }
        #expect(summary.sampleCount == 3 && summary.batchCount == 2)
    }

    @Test
    func emptyNonfiniteAndOversizedSequencesFail() throws {
        #expect(throws: SensorKitRecordError.emptySamples) {
            _ = try SensorKitTabularRecording.File(samples: [Sample](), deviceProductType: "Watch", maximumByteCount: 1024)
        }
        let sample = Sample(timestamp: Date(timeIntervalSince1970: 1), batch: 1)
        #expect(throws: RecordingCSVFileWriter.FileWriterError.payloadLimitExceeded) {
            _ = try SensorKitTabularRecording.File(samples: [sample], deviceProductType: "Watch", maximumByteCount: 32)
        }
        var invalid = sample
        invalid.value = .nan
        #expect(throws: RecordingCSVWriter.WriterError.nonFiniteNumber(column: "x")) {
            _ = try SensorKitTabularRecording.File(samples: [invalid], deviceProductType: "Watch", maximumByteCount: 1024)
        }
    }

    @Test
    func cancellationDoesNotReturnPreparedRecording() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SensorKitTabularRecording.File(
                samples: [Sample(timestamp: Date(timeIntervalSince1970: 1), batch: 1)], deviceProductType: "Watch", maximumByteCount: 1024
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func wristEvidencePrefixKeepsLengthFramingAndUTF8() {
        let prefix = SensorKitTabularRecording.wristTemperatureEvidencePrefix(version: "é1")
        #expect(prefix == Data([0, 0, 0, 0, 0, 0, 0, 3, 0xC3, 0xA9, 0x31]))
    }
}
#endif
