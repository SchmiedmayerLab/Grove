//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import Testing


@Suite
struct RecordingCSVRoundTripTests {
    @Test("Every tabular format round-trips through the writer and reader")
    func everyTabularFormatRoundTrips() throws {
        for format in RegisteredRecordingFormat.tabularFormats {
            let columns = try #require(format.csvColumns)
            var writer = try RecordingCSVWriter(format: format)
            try writer.append(RecordingCSVSchemaFixtures.row(format: format, variant: 1))
            try writer.append(RecordingCSVSchemaFixtures.row(format: format, variant: 2))
            let data = writer.data()
            let reader = try RecordingCSVReader(data, format: format)
            #expect(reader.columns == columns, "\(format.rawValue)")
            #expect(reader.rows.count == 2, "\(format.rawValue)")
            var reencoded = try RecordingCSVWriter(format: format)
            for row in reader.rows {
                try reencoded.append(columns.map { column in row[column].map(RecordingCSVWriter.Field.text) ?? .absent })
            }
            #expect(reencoded.data() == data, "\(format.rawValue)")
        }
    }

    @Test("Absent fields remain optional while malformed fields fail closed")
    func optionalFieldsDoNotConflateAbsenceAndCorruption() throws {
        let format = RegisteredRecordingFormat.wristTemperatureSamples
        let columns = try #require(format.csvColumns)
        let absent = Data("\(columns.joined(separator: ","))\n1,36.5,0.1,\n".utf8)
        let absentRow = try #require(RecordingCSVReader(absent, format: format).rows.first)
        #expect(absentRow.isAbsent("condition"))
        #expect(try absentRow.integer("condition") == nil)
        #expect(throws: RecordingCSVReader.RowValueError.absent("condition")) {
            _ = try absentRow.requiredInteger("condition")
        }
        let malformed = Data("\(columns.joined(separator: ","))\n1,not-a-number,0.1,\n".utf8)
        #expect(throws: RecordingCSVReader.ReaderError.invalidColumnValue(row: 1, column: "value")) {
            _ = try RecordingCSVReader(malformed, format: format)
        }
        #expect(throws: RecordingCSVReader.RowValueError.unknownColumn("unknown")) {
            _ = try absentRow.timestamp("unknown")
        }
    }

    @Test("A payload whose header disagrees with the format is rejected")
    func headerMismatchIsRejected() throws {
        let format = RegisteredRecordingFormat.heartRateSamples
        let mismatched = Data("timestamp,value\n1,60\n".utf8)
        #expect(throws: RecordingCSVReader.ReaderError.unexpectedHeader(expected: try #require(format.csvColumns), actual: ["timestamp", "value"])) {
            try RecordingCSVReader(mismatched, format: format)
        }
    }

    @Test("A payload missing its final row terminator is rejected")
    func truncatedPayloadIsRejected() throws {
        let format = RegisteredRecordingFormat.heartRateSamples
        var writer = try RecordingCSVWriter(format: format)
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
        var writer = try RecordingCSVWriter(format: format)
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
}
