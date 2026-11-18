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
struct RecordingRoundTripTests {
    @Test("The complete PPG grammar round-trips and derives its summary")
    func ppgRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_787_009_400)
        let recording = SensorKitPPGTestSupport.recording(start: start)
        let data = try recording.encoded()
        let decoded = try SensorKitPPGRecording(data: data)

        #expect(decoded == recording)
        var expectedStart = start.timeIntervalSince1970.bitPattern.bigEndian
        let expectedStartBytes = withUnsafeBytes(of: &expectedStart) { Array($0) }
        #expect(data.first == SensorKitPPGRecording.version)
        // The version byte, then the one-byte record count, then the first record's start.
        #expect(Array(data.dropFirst(2).prefix(8)) == expectedStartBytes)
        #expect(decoded.summary?.recordCount == 2)
        #expect(decoded.summary?.opticalSampleCount == 2)
        #expect(decoded.summary?.accelerometerSampleCount == 2)
        #expect(decoded.summary?.coverage.start == start)
        #expect(decoded.summary?.coverage.end == start.addingTimeInterval(1.5))
    }

    @Test("A PPG payload of another version, or with no version byte, is refused")
    func ppgVersionIsChecked() throws {
        var payload = try SensorKitPPGTestSupport.recording(start: Date(timeIntervalSince1970: 1_787_009_400)).encoded()
        payload[payload.startIndex] = 2
        #expect(throws: SensorKitPPGRecording.DecodingError.unsupportedVersion(2)) {
            _ = try SensorKitPPGRecording(data: payload)
        }
        #expect(throws: RegisteredRecordingPayloadError.invalidPhotoplethysmogramPayload) {
            try RegisteredRecordingFormat.photoplethysmogramSamples.validatePayload(payload)
        }
        #expect(throws: RecordingBinaryReader.ReaderError.unexpectedEnd) {
            _ = try SensorKitPPGRecording(data: Data())
        }
    }

    @Test("Prepared PPG evidence reuses one canonical byte buffer")
    func preparedPPGReusesCanonicalBytes() throws {
        let recording = SensorKitPPGTestSupport.recording(
            start: Date(timeIntervalSince1970: 1_787_009_400)
        )
        let prepared = try recording.prepared()
        let record = try prepared.sensorKitRecord(
            sourceRecordID: SensorKitSourceRecordID(try #require(
                UUID(uuidString: "879d9ea2-21cb-4527-b59b-2831dc4c84ab")
            )),
            title: "Exact SensorKit PPG batch",
            location: .inline,
            admission: .callerAuthorizedOpaquePayload
        )
        guard case .ppg(let ppg) = record else {
            Issue.record("Expected a PPG record")
            return
        }

        #expect(prepared.format == .photoplethysmogramSamples)
        #expect(prepared.retryEvidence == prepared.data)
        #expect(try ppg.nativeRecording.decodedPayload() == prepared.data)
    }

    @Test("Malformed complete PPG payloads fail closed")
    func malformedPPGFailsClosed() throws {
        let recording = SensorKitPPGTestSupport.recording(
            start: Date(timeIntervalSince1970: 1_787_009_400),
            recordCount: 1
        )
        var payload = try recording.encoded()
        payload.append(0)
        #expect(throws: RecordingBinaryReader.ReaderError.trailingBytes(1)) {
            _ = try SensorKitPPGRecording(data: payload)
        }
        #expect(throws: RegisteredRecordingPayloadError.invalidPhotoplethysmogramPayload) {
            try RegisteredRecordingFormat.photoplethysmogramSamples.validatePayload(payload)
        }
    }

    @Test("Binary primitives round-trip through the writer and reader")
    func binaryPrimitivesRoundTrip() throws {
        var writer = RecordingBinaryWriter()
        writer.writeVarint(UInt64(0))
        writer.writeVarint(UInt64.max)
        writer.writeVarint(Int64(-1))
        try writer.writeFloat64(-0.0)
        try writer.writeFloat64(1e-5)
        writer.writeBoolean(true)
        writer.writeString("wrist ✓")
        try writer.writeOptionalFloat64(nil)
        try writer.writeOptionalFloat64(36.6)
        try writer.writeArray([1.5, 2.5]) { target, value in try target.writeFloat64(value) }

        var reader = RecordingBinaryReader(writer.data())
        #expect(try reader.readVarint() == 0)
        #expect(try reader.readVarint() == UInt64.max)
        #expect(try reader.readSignedVarint() == -1)
        #expect(try reader.readFloat64().bitPattern == 0.0.bitPattern)
        #expect(try reader.readFloat64() == 1e-5)
        #expect(try reader.readBoolean())
        #expect(try reader.readString() == "wrist ✓")
        #expect(try reader.readOptionalFloat64() == nil)
        #expect(try reader.readOptionalFloat64() == 36.6)
        #expect(try reader.readArray { try $0.readFloat64() } == [1.5, 2.5])
        try reader.finish()
    }

    @Test("A truncated binary payload fails closed rather than inventing a value")
    func truncatedBinaryFailsClosed() throws {
        var writer = RecordingBinaryWriter()
        try writer.writeFloat64(36.6)
        var truncated = writer.data()
        truncated.removeLast(3)
        var reader = RecordingBinaryReader(truncated)
        #expect(throws: RecordingBinaryReader.ReaderError.unexpectedEnd) {
            _ = try reader.readFloat64()
        }
    }

    @Test("Binary sets are unique and ascending on the wire")
    func canonicalSetRoundTrip() throws {
        var writer = RecordingBinaryWriter()
        try writer.writeCanonicalSet([3, 1, 2]) { target, value in
            target.writeVarint(UInt64(value))
        }
        var reader = RecordingBinaryReader(writer.data())
        #expect(try reader.readCanonicalSet { Int(try $0.readVarint()) } == [1, 2, 3])
        try reader.finish()
    }

    @Test("Duplicate logical set values are rejected")
    func duplicateSetValueIsRejected() {
        var writer = RecordingBinaryWriter()
        #expect(throws: RecordingBinaryWriter.WriterError.duplicateSetValue) {
            try writer.writeCanonicalSet([1, 1]) { target, value in
                target.writeVarint(UInt64(value))
            }
        }
    }
}
