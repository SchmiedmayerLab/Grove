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
    @Test("Every tabular format round-trips through the writer and reader")
    func everyTabularFormatRoundTrips() throws {
        for format in RegisteredRecordingFormat.tabularFormats {
            let columns = try #require(format.csvColumns)
            var writer = RecordingCSVWriter(columns: columns)
            // One row exercising every field kind the writer admits, and one all-absent row.
            try writer.append(columns.indices.map { index in
                index.isMultiple(of: 2) ? .number(Double(index) + 0.5) : .text("v\(index)")
            })
            try writer.append(columns.map { _ in .absent })
            let data = writer.data()

            let reader = try RecordingCSVReader(data, format: format)
            #expect(reader.columns == columns, "\(format.rawValue)")
            #expect(reader.rows.count == 2, "\(format.rawValue)")
            for (index, column) in columns.enumerated() where index.isMultiple(of: 2) {
                #expect(try reader.rows[0].number(column) == Double(index) + 0.5, "\(format.rawValue).\(column)")
            }
            for column in columns {
                #expect(reader.rows[1].isAbsent(column), "\(format.rawValue).\(column)")
            }
        }
    }

    @Test("Absent fields remain optional while malformed fields fail closed")
    func optionalFieldsDoNotConflateAbsenceAndCorruption() throws {
        let format = RegisteredRecordingFormat.heartRateSamples
        let columns = try #require(format.csvColumns)
        let absent = Data("\(columns.joined(separator: ","))\n1,60,,Watch\n".utf8)
        let absentRow = try #require(RecordingCSVReader(absent, format: format).rows.first)
        #expect(try absentRow.integer("confidence") == nil)
        #expect(throws: RecordingCSVReader.RowValueError.absent("confidence")) {
            _ = try absentRow.requiredInteger("confidence")
        }

        let malformed = Data("\(columns.joined(separator: ","))\n1,not-a-number,2,Watch\n".utf8)
        let malformedRow = try #require(RecordingCSVReader(malformed, format: format).rows.first)
        #expect(throws: RecordingCSVReader.RowValueError.malformedNumber(column: "value", value: "not-a-number")) {
            _ = try malformedRow.number("value")
        }
        #expect(throws: RecordingCSVReader.RowValueError.unknownColumn("unknown")) {
            _ = try malformedRow.timestamp("unknown")
        }
    }

    @Test("A payload whose header disagrees with the format is rejected")
    func headerMismatchIsRejected() throws {
        let format = RegisteredRecordingFormat.heartRateSamples
        var writer = RecordingCSVWriter(columns: ["timestamp", "value"])
        try writer.append([.timestamp(Date(timeIntervalSince1970: 1)), .number(60)])
        // data() consumes the writer, so it cannot be called from inside the expectation closure.
        let mismatched = writer.data()
        #expect(throws: RecordingCSVReader.ReaderError.self) {
            try RecordingCSVReader(mismatched, format: format)
        }
    }

    @Test("A payload missing its final row terminator is rejected")
    func truncatedPayloadIsRejected() throws {
        let format = RegisteredRecordingFormat.heartRateSamples
        var writer = RecordingCSVWriter(columns: try #require(format.csvColumns))
        try writer.append([.timestamp(Date(timeIntervalSince1970: 1)), .number(60), .integer(2), .text("Watch")])
        var truncated = writer.data()
        truncated.removeLast()
        #expect(throws: RecordingCSVReader.ReaderError.missingFinalRowTerminator) {
            try RecordingCSVReader(truncated, format: format)
        }
    }

    @Test("Quoted fields carrying separators and LF survive the round trip")
    func quotedFieldsSurvive() throws {
        let format = RegisteredRecordingFormat.wristTemperatureSamples
        let columns = try #require(format.csvColumns)
        let awkward = "offWrist,onCharger\nstill \"quoted\""
        var writer = RecordingCSVWriter(columns: columns)
        try writer.append(columns.indices.map { index in
            index == columns.count - 1 ? .text(awkward) : .number(Double(index))
        })
        let reader = try RecordingCSVReader(writer.data(), format: format)
        #expect(reader.rows.count == 1)
        #expect(reader.rows[0][columns[columns.count - 1]] == awkward)
    }

    @Test("A carriage return inside a quoted field is rejected")
    func quotedCarriageReturnIsRejected() throws {
        let columns = try #require(RegisteredRecordingFormat.wristTemperatureSamples.csvColumns)
        let payload = Data("\(columns.joined(separator: ","))\n1,36.5,0.1,\"offWrist\rhidden\"\n".utf8)
        #expect(throws: RecordingCSVReader.ReaderError.self) {
            _ = try RecordingCSVReader(payload, format: .wristTemperatureSamples)
        }
    }

    @Test("The complete PPG grammar round-trips and derives its summary")
    func ppgRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_787_009_400)
        let recording = SensorKitPPGTestSupport.recording(start: start)
        let data = try recording.encoded()
        let decoded = try SensorKitPPGRecording(data: data)

        #expect(decoded == recording)
        var expectedStart = start.timeIntervalSince1970.bitPattern.bigEndian
        let expectedStartBytes = withUnsafeBytes(of: &expectedStart) { Array($0) }
        #expect(Array(data.dropFirst().prefix(8)) == expectedStartBytes)
        #expect(decoded.summary?.recordCount == 2)
        #expect(decoded.summary?.opticalSampleCount == 2)
        #expect(decoded.summary?.accelerometerSampleCount == 2)
        #expect(decoded.summary?.coverage.start == start)
        #expect(decoded.summary?.coverage.end == start.addingTimeInterval(1.5))
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
        #expect(ppg.nativeRecording.bytes == prepared.data)
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
