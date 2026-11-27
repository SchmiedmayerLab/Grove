//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import Testing


@Suite
struct FileRecordingConversionTests {
    @Test
    func fileAndDataSidecarsProduceIdenticalExchangeBytes() async throws {
        let bytes = Data("timestamp,value,confidence,device\n1787009400,72,3,Watch\n".utf8)
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
        let sourceID = SensorKitSourceRecordID(UUID())
        func record(_ payload: SensorKitNativeRecording.Payload) throws -> SensorKitRecord {
            .raw(try SensorKitRawRecord(
                sourceRecordID: sourceID,
                sourceToken: "SRSensor.heartRate",
                effectivePeriod: DateInterval(start: SensorKitExporterFixtures.start, duration: 1),
                nativeRecording: SensorKitNativeRecording(
                    title: "Heart rate recording", format: .heartRateSamples, payload: payload, admission: .verifiedSanitizedInput
                )
            ))
        }
        let path = "recordings/heart-rate.csv"
        let dataRecord = try await SensorKitExporterFixtures.record(record(.sidecar(path: path, bytes: bytes)))
        let fileRecord = try await SensorKitExporterFixtures.record(record(.file(path: path, contents: file)))
        #expect(fileRecord.json == dataRecord.json)
        let graph = try fileRecord.graph
        let attachment = try #require(graph.recordingDocument?.content.first?.attachment)
        #expect(attachment.data == nil && attachment.url?.value?.url.absoluteString == path)
        #expect(!String(decoding: fileRecord.json, as: UTF8.self).contains(fixture.directory.path))
        #expect(try Data(contentsOf: fixture.source) == bytes)
    }

    @Test
    func fileSummaryCountsCanonicalDevicesAndEmbeddedNullsExactly() throws {
        var writer = try RecordingCSVWriter(format: .triaxialAccelerationSamples)
        let devices = ["caf\u{00E9}", "cafe\u{0301}", "Watch\0one", "Watch\0two", "Watch\0one"]
        for (index, device) in devices.enumerated() {
            try writer.append([.number(Double(index)), .integer(1), .number(0.1), .number(0.2), .number(0.3), .text(device)])
        }
        let bytes = writer.data()
        let fixture = try RecordingFileFixture(bytes)
        defer { withExtendedLifetime(fixture) {} }
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
        let input = try SensorKitNativeRecording(
            title: "Acceleration",
            format: .triaxialAccelerationSamples,
            payload: .file(path: "recordings/acceleration.csv", contents: file),
            admission: .verifiedSanitizedInput
        )
        let summary = try SensorKitAccelerometerRecord(sourceRecordID: .init(UUID()), nativeRecording: input)
        #expect(summary.sampleCount == 5 && summary.batchCount == 3)
        #expect(summary.coverage.start == Date(timeIntervalSince1970: 0))
        #expect(summary.coverage.end == Date(timeIntervalSince1970: 4))
    }

    @Test
    func malformedFileAndDataPayloadsHaveTheSameRefusal() throws {
        for bytes in [
            Data("wrong,header\n".utf8), Data("timestamp,value,confidence,device\n1,60,2,Watch".utf8),
            Data("timestamp,value,confidence,device\n1,60,2,".utf8) + Data([0xFF, 0x0A]),
            Data("\"timestamp\",\"value\",\"confidence\",\"device\"\n\"1\",\"60\",\"2\",\"Watch\"\n".utf8)
        ] {
            let refusal: RecordingCSVReader.ReaderError
            do {
                _ = try RecordingCSVReader(bytes, format: .heartRateSamples)
                Issue.record("the reader read a malformed payload")
                continue
            } catch {
                refusal = error
            }
            let fixture = try RecordingFileFixture(bytes)
            defer { withExtendedLifetime(fixture) {} }
            let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: bytes.count)
            for payload in [
                SensorKitNativeRecording.Payload.sidecar(path: "recordings/heart.csv", bytes: bytes),
                .file(path: "recordings/heart.csv", contents: file)
            ] {
                #expect(throws: SensorKitRecordError.invalidRegisteredPayload(format: .heartRateSamples, reason: .invalidTabularPayload(refusal))) {
                    try SensorKitNativeRecording(title: "Heart rate", format: .heartRateSamples, payload: payload, admission: .verifiedSanitizedInput)
                }
            }
            #expect(try Data(contentsOf: fixture.source) == bytes)
        }
    }

    @Test("A sidecar that quotes every field is refused with the canonical quoting error")
    func quoteEveryFieldSidecarNamesTheCanonicalQuoting() throws {
        let bytes = Data("\"timestamp\",\"value\",\"confidence\",\"device\"\n\"1\",\"60\",\"2\",\"Watch\"\n".utf8)
        let reason = RegisteredRecordingPayloadError.invalidTabularPayload(.unnecessaryQuotes(row: 0, column: 0))
        #expect(throws: SensorKitRecordError.invalidRegisteredPayload(format: .heartRateSamples, reason: reason)) {
            try SensorKitNativeRecording(
                title: "Heart rate",
                format: .heartRateSamples,
                payload: .sidecar(path: "recordings/heart.csv", bytes: bytes),
                admission: .verifiedSanitizedInput
            )
        }
    }

    @Test
    func largeWholeDecodeFormatsAreRefusedBeforeParsing() throws {
        let fixture = try RecordingFileFixture(Data())
        defer { withExtendedLifetime(fixture) {} }
        let size = RegisteredRecordingFormat.maximumDecodedPayloadByteCount + 1
        let writer = try FileHandle(forWritingTo: fixture.source)
        try writer.truncate(atOffset: UInt64(size))
        try writer.close()
        let file = try RecordingFile.stage(copying: fixture.source, maximumByteCount: size)
        let formats: [RegisteredRecordingFormat] = [
            .nativeRecording, .providerRecording, .photoplethysmogramSamples, .fhirResource, .fhirCollectionBundle
        ]
        for format in formats {
            #expect(throws: SensorKitRecordError.invalidRegisteredPayload(format: format, reason: .payloadLimitExceeded)) {
                try SensorKitNativeRecording(
                    title: "Oversized recording",
                    format: format,
                    payload: .file(path: "recordings/oversized", contents: file),
                    admission: .callerAuthorizedOpaquePayload
                )
            }
        }
    }
}
