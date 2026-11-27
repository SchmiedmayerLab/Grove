//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveSensorKitFHIR
import Testing


@Suite
struct RegisteredRecordingFileValidationTests {
    @Test
    func callerBudgetIsCheckedBeforeGrammarAndAllowsItsExactBoundary() throws {
        let file = try staged(Data("{\"value\":1}".utf8))
        try RegisteredRecordingFormat.nativeRecording.validatePayload(file, maximumByteCount: file.byteCount)
        for limit in [-1, 0, file.byteCount - 1, Int(Int32.max) + 1] {
            #expect(throws: RegisteredRecordingPayloadError.payloadLimitExceeded) {
                try RegisteredRecordingFormat.nativeRecording.validatePayload(file, maximumByteCount: limit)
            }
        }
    }

    @Test
    func memoryEntryPointAppliesTheSameCallerBudget() throws {
        let bytes = Data("{\"value\":1}".utf8)
        try RegisteredRecordingFormat.nativeRecording.validatePayload(bytes, maximumByteCount: bytes.count)
        for limit in [-1, 0, bytes.count - 1, Int(Int32.max) + 1] {
            #expect(throws: RegisteredRecordingPayloadError.payloadLimitExceeded) {
                try RegisteredRecordingFormat.nativeRecording.validatePayload(bytes, maximumByteCount: limit)
            }
        }
    }

    @Test
    func fileEntryPointUsesStrictJSONAndTypedCSVValidation() throws {
        let duplicate = try staged(Data("{\"value\":1,\"value\":2}".utf8))
        #expect(throws: RegisteredRecordingPayloadError.duplicateJSONMember("value")) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(duplicate, maximumByteCount: 1_024)
        }
        let format = RegisteredRecordingFormat.heartRateSamples
        let header = try #require(format.csvColumns).joined(separator: ",")
        let invalidRow = try staged(Data("\(header)\nnot-a-timestamp,60,2,Watch\n".utf8))
        #expect(throws: RegisteredRecordingPayloadError.invalidTabularPayload(.invalidColumnValue(row: 1, column: "timestamp"))) {
            try format.validatePayload(invalidRow, maximumByteCount: 16_384)
        }
    }

    @Test
    func nonStreamingGrammarRetainsItsHardLimitEvenWhenCallerAllowsMore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("oversized.json")
        try Data().write(to: url, options: .withoutOverwriting)
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        let chunk = Data(repeating: 32, count: 65_536)
        for _ in 0..<(RegisteredRecordingFormat.maximumDecodedPayloadByteCount / chunk.count) { try writer.write(contentsOf: chunk) }
        try writer.write(contentsOf: Data([0]))
        try writer.synchronize()
        let file = try RecordingFile.stage(copying: url, maximumByteCount: RegisteredRecordingFormat.maximumDecodedPayloadByteCount + 1)
        for format in [RegisteredRecordingFormat.nativeRecording, .providerRecording, .photoplethysmogramSamples, .fhirCollectionBundle] {
            #expect(throws: RegisteredRecordingPayloadError.payloadLimitExceeded) {
                try format.validatePayload(file, maximumByteCount: file.byteCount)
            }
        }
    }

    @Test
    func retainedBytesUseTheSameGrammarAndInclusiveCallerBudget() throws {
        let bytes = Data("{\"value\":1}".utf8)
        try RegisteredRecordingFormat.nativeRecording.validatePayload(bytes, maximumByteCount: bytes.count)
        for limit in [-1, 0, bytes.count - 1] {
            #expect(throws: RegisteredRecordingPayloadError.payloadLimitExceeded) {
                try RegisteredRecordingFormat.nativeRecording.validatePayload(bytes, maximumByteCount: limit)
            }
        }
        let duplicate = Data("{\"value\":1,\"value\":2}".utf8)
        #expect(throws: RegisteredRecordingPayloadError.duplicateJSONMember("value")) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(duplicate, maximumByteCount: duplicate.count)
        }
        let csv = Data("timestamp,value,confidence,device\n1,not-a-number,3,Watch\n".utf8)
        #expect(throws: RegisteredRecordingPayloadError.invalidTabularPayload(.invalidColumnValue(row: 1, column: "value"))) {
            try RegisteredRecordingFormat.heartRateSamples.validatePayload(csv, maximumByteCount: csv.count)
        }
        let oversized = Data(repeating: 32, count: RegisteredRecordingFormat.maximumDecodedPayloadByteCount + 1)
        #expect(throws: RegisteredRecordingPayloadError.payloadLimitExceeded) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(oversized, maximumByteCount: oversized.count)
        }
    }

    private func staged(_ bytes: Data) throws -> RecordingFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("source")
        try bytes.write(to: url, options: .withoutOverwriting)
        return try RecordingFile.stage(copying: url, maximumByteCount: bytes.count)
    }
}
