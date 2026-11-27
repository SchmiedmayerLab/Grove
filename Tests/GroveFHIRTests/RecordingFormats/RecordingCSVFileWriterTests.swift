//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Testing


@Suite
struct RecordingCSVFileWriterTests {
    @Test(arguments: RegisteredRecordingFormat.allCases.filter { $0.csvColumns != nil })
    func sameBytesAsDataWriter(format: RegisteredRecordingFormat) throws {
        var memory = try RecordingCSVWriter(format: format)
        var disk = try RecordingCSVFileWriter(format: format, maximumByteCount: 1_000_000)
        for variant in 0..<5 {
            let row = RecordingCSVSchemaFixtures.row(format: format, variant: variant)
            try memory.append(row)
            try disk.append(row)
        }
        let expected = memory.data()
        let file = try disk.finish()
        #expect(file.byteCount == expected.count)
        #expect(file.attachmentSHA1 == expected.attachmentSHA1)
        #expect(try contents(file) == expected)
        #expect(try RecordingCSVReader(expected, format: format).rows.count == 5)
    }

    @Test
    func emptyRecordingAndInclusiveTotalLimit() throws {
        let memory = try RecordingCSVWriter(format: .beatIntervalSeries)
        let header = memory.data()
        let empty = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: header.count).finish()
        #expect(try contents(empty) == header)
        var writer = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: header.count + 4)
        try writer.append([.integer(1), .integer(0)])
        let completed = try writer.finish()
        #expect(try contents(completed) == header + Data("1,0\n".utf8))
        #expect(throws: RecordingCSVWriter.WriterError.payloadLimitExceeded) {
            _ = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: header.count - 1)
        }
        var short = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: header.count + 3)
        #expect(throws: RecordingCSVWriter.WriterError.payloadLimitExceeded) { try short.append([.integer(1), .integer(0)]) }
        #expect(throws: RecordingCSVWriter.WriterError.closed) { try short.append([.integer(1), .integer(0)]) }
    }

    @Test
    func failedAppendCannotProduceSuccessfulPrefix() throws {
        var writer = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: 1024)
        try writer.append([.integer(1), .integer(0)])
        #expect(throws: RecordingCSVWriter.WriterError.nonFiniteNumber(column: "timestamp")) {
            try writer.append([.number(.infinity), .integer(0)])
        }
        #expect(throws: RecordingCSVWriter.WriterError.closed) { try writer.append([.integer(2), .integer(0)]) }
        do {
            _ = try writer.finish()
            Issue.record("A failed writer must not return a partial recording")
        } catch { #expect(error as? RecordingCSVWriter.WriterError == .closed) }
    }

    @Test
    func fieldLimitMatchesTheDefaultReaderLimit() throws {
        let limits = RecordingCSVReader.Limits.default
        // Each doubled quote adds one byte to the encoded row but none to the decoded field.
        let field = String(repeating: "\"", count: limits.maximumFieldByteCount)
        var writer = try RecordingCSVFileWriter(format: .heartRateSamples, maximumByteCount: 8 * 1024 * 1024)
        try writer.append([.integer(1), .integer(1), .integer(1), .text(field)])
        let file = try writer.finish()
        #expect(try RecordingCSVReader(contents(file), format: .heartRateSamples).rows.first?.fields.last == field)

        var fieldWriter = try RecordingCSVFileWriter(format: .heartRateSamples, maximumByteCount: 8 * 1024 * 1024)
        #expect(throws: RecordingCSVWriter.WriterError.fieldLimitExceeded) {
            try fieldWriter.append([.integer(1), .integer(1), .integer(1), .text(field + "é")])
        }
    }

    @Test
    func numericTextIsBudgetedBeforeColumnValidation() throws {
        let field = String(repeating: ".", count: RecordingCSVReader.Limits.default.maximumFieldByteCount)
        for (text, error) in [(field, RecordingCSVWriter.WriterError.invalidValue(column: "value")), (field + ".", .fieldLimitExceeded)] {
            var writer = try RecordingCSVFileWriter(format: .heartRateSamples, maximumByteCount: 2 * 1024 * 1024)
            #expect(throws: error) { try writer.append([.integer(1), .text(text), .integer(2), .text("watch")]) }
            #expect(throws: RecordingCSVWriter.WriterError.closed) { try writer.append([]) }
        }
    }

    @Test
    func escapedFileRowAtTheRecordLimitStreamsSuccessfully() throws {
        let limits = RecordingCSVReader.Limits.default
        let numeric = Array(repeating: RecordingCSVWriter.Field.integer(0), count: 11)
        let first = String(repeating: "\"", count: limits.maximumFieldByteCount)
        // Eleven "0," prefixes, four enclosing quotes, one comma and LF leave the rest for doubled quotes.
        let secondCount = (limits.maximumRecordByteCount - 28) / 2 - first.utf8.count
        let second = String(repeating: "\"", count: secondCount)
        let columns = try #require(RegisteredRecordingFormat.odometerSamples.csvColumns)
        let total = columns.joined(separator: ",").utf8.count + 1 + limits.maximumRecordByteCount
        var exact = try RecordingCSVFileWriter(format: .odometerSamples, maximumByteCount: total)
        try exact.append(numeric + [.text(first), .text(second)])
        let file = try exact.finish()
        #expect(file.byteCount == total)
        var reader = try RecordingCSVReader.Stream(format: .odometerSamples)
        var rows = 0
        try file.readChunks { try reader.read($0) { _ in rows += 1 } }
        try reader.finish()
        #expect(rows == 1)
        var over = try RecordingCSVFileWriter(format: .odometerSamples, maximumByteCount: total + 1)
        #expect(throws: RecordingCSVWriter.WriterError.recordLimitExceeded) {
            try over.append(numeric + [.text(first), .text(second + "x")])
        }
    }

    @Test
    func multipleWriteBuffersKeepRowsAndHashIntact() throws {
        var writer = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: 2_000_000)
        for index in 0..<100_000 { try writer.append([.integer(index), .integer(index % 2)]) }
        let file = try writer.finish()
        var reader = try RecordingCSVReader.Stream(format: .beatIntervalSeries)
        var hasher = AttachmentHasher()
        var count = 0
        try file.readChunks { chunk in
            #expect(chunk.count <= 64 * 1024)
            hasher.update(chunk)
            try reader.read(chunk) { row in
                let timestamp = try row.requiredInteger("timestamp")
                #expect(timestamp == count)
                count += 1
            }
        }
        try reader.finish()
        #expect(count == 100_000)
        #expect(file.attachmentSHA1 == hasher.finalize())
    }

    @Test
    func cancellationCannotFinalizePartialRecording() async throws {
        let task = Task {
            var writer = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: 1024)
            try writer.append([.integer(1), .integer(0)])
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try writer.finish()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func contents(_ file: RecordingFile) throws -> Data {
        var data = Data()
        try file.readChunks { data.append($0) }
        return data
    }
}
