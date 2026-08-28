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
                #expect(reader.rows[0].number(column) == Double(index) + 0.5, "\(format.rawValue).\(column)")
            }
            for column in columns {
                #expect(reader.rows[1].isAbsent(column), "\(format.rawValue).\(column)")
            }
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

    @Test("Quoted fields carrying separators and terminators survive the round trip")
    func quotedFieldsSurvive() throws {
        let format = RegisteredRecordingFormat.wristTemperatureSamples
        let columns = try #require(format.csvColumns)
        let awkward = "offWrist,onCharger\r\nstill \"quoted\""
        var writer = RecordingCSVWriter(columns: columns)
        try writer.append(columns.indices.map { index in
            index == columns.count - 1 ? .text(awkward) : .number(Double(index))
        })
        let reader = try RecordingCSVReader(writer.data(), format: format)
        #expect(reader.rows.count == 1)
        #expect(reader.rows[0][columns[columns.count - 1]] == awkward)
    }

    @Test("Binary primitives round-trip through the writer and reader")
    func binaryPrimitivesRoundTrip() throws {
        var writer = RecordingBinaryWriter()
        writer.writeVarint(UInt64(0))
        writer.writeVarint(UInt64.max)
        writer.writeVarint(Int64(-1))
        writer.writeFloat64(-0.0)
        writer.writeFloat64(1e-5)
        writer.writeBoolean(true)
        writer.writeString("wrist ✓")
        writer.writeOptionalFloat64(nil)
        writer.writeOptionalFloat64(36.6)
        writer.writeArray([1.5, 2.5]) { target, value in target.writeFloat64(value) }

        var reader = RecordingBinaryReader(writer.data())
        #expect(try reader.readVarint() == 0)
        #expect(try reader.readVarint() == UInt64.max)
        #expect(try reader.readSignedVarint() == -1)
        #expect(try reader.readFloat64().sign == .minus)
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
        writer.writeFloat64(36.6)
        var truncated = writer.data()
        truncated.removeLast(3)
        var reader = RecordingBinaryReader(truncated)
        #expect(throws: RecordingBinaryReader.ReaderError.unexpectedEnd) {
            _ = try reader.readFloat64()
        }
    }
}
