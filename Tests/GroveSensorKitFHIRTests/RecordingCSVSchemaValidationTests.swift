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


struct RecordingCSVSchemaValidationTests {
    @Test(arguments: ["NaN", "Infinity", "+1", "01", "1e2", "-0", "-0.0", "1.20", "1.", "", "text"])
    func rawNumbersAreRejectedBeforeDelivery(value: String) throws {
        let header = try #require(RegisteredRecordingFormat.triaxialAccelerationSamples.csvColumns).joined(separator: ",")
        let bytes = Data("\(header)\n0,1,\(value),0,0,Watch\n".utf8)
        var stream = try RecordingCSVReader.Stream(format: .triaxialAccelerationSamples)
        #expect(throws: RecordingCSVReader.ReaderError.invalidColumnValue(column: "x")) {
            try stream.read(bytes) { _ in Issue.record("Invalid typed row reached the consumer") }
        }
        #expect(throws: RecordingCSVReader.ReaderError.streamClosed) { try stream.finish() }
    }

    @Test(arguments: ["1.0", "01", "+1", "-0", "", "text"])
    func textCannotBypassIntegerValidation(value: String) throws {
        var writer = try RecordingCSVWriter(format: .triaxialAccelerationSamples)
        #expect(throws: RecordingCSVReader.ReaderError.invalidColumnValue(column: "identifier")) {
            try writer.append([.integer(0), .text(value), .integer(0), .integer(0), .integer(0), .text("Watch")])
        }
    }

    @Test
    func maximumUnsignedBatchIdentifierAndFiniteDecimalsRemainExact() throws {
        var writer = try RecordingCSVWriter(format: .triaxialAccelerationSamples)
        try writer.append([.integer(0), .text(String(UInt64.max)), .text("1.0"), .text("-0.125"), .integer(0), .text("Watch")])
        let row = try #require(RecordingCSVReader(writer.data(), format: .triaxialAccelerationSamples).rows.first)
        #expect(row["identifier"] == "18446744073709551615")
        #expect(try row.requiredNumber("x") == 1)
        #expect(try row.requiredNumber("y") == -0.125)
    }

    @Test
    func requiredTextCannotBeAbsentAndFailedFileWriterCannotPublishPrefix() throws {
        var writer = try RecordingCSVFileWriter(format: .heartRateSamples, maximumByteCount: 1024)
        try writer.append([.integer(0), .integer(60), .integer(2), .text("Watch")])
        #expect(throws: RecordingCSVReader.ReaderError.invalidColumnValue(column: "device")) {
            try writer.append([.integer(1), .integer(60), .integer(2), .absent])
        }
        do {
            _ = try writer.finish()
            Issue.record("Invalid typed recording produced a successful prefix")
        } catch { #expect(error as? RecordingCSVFileWriter.FileWriterError == .closed) }
    }
}
