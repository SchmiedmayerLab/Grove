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


struct RecordingCSVFileWriterTests {
    /// Rows covering every field kind, quoting, multibyte scalars and absence in each column position.
    private static func row(columnCount: Int, variant: Int) -> [RecordingCSVWriter.Field] {
        (0..<columnCount).map { index in
            switch (index + variant) % 5 {
            case 0: .absent
            case 1: .text("é,\"quoted\"\nline \(variant)")
            case 2: .integer(variant)
            case 3: .number(Double(variant) + 0.125)
            default: .timestamp(Date(timeIntervalSince1970: 1_800_000_000.125 + Double(variant)))
            }
        }
    }

    @Test(arguments: RegisteredRecordingFormat.allCases.filter { $0.csvColumns != nil })
    func sameBytesAsDataWriter(format: RegisteredRecordingFormat) throws {
        var memory = try RecordingCSVWriter(format: format)
        var disk = try RecordingCSVFileWriter(format: format, maximumByteCount: 1_000_000)
        for variant in 0..<5 {
            let row = Self.row(columnCount: try #require(format.csvColumns).count, variant: variant)
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
        #expect(throws: RecordingCSVFileWriter.FileWriterError.payloadLimitExceeded) {
            _ = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: header.count - 1)
        }
    }

    @Test
    func failedAppendCannotProduceSuccessfulPrefix() throws {
        var writer = try RecordingCSVFileWriter(format: .beatIntervalSeries, maximumByteCount: 1024)
        try writer.append([.integer(1), .integer(0)])
        #expect(throws: RecordingCSVWriter.WriterError.nonFiniteNumber(column: "timestamp")) {
            try writer.append([.number(.infinity), .integer(0)])
        }
        #expect(throws: RecordingCSVFileWriter.FileWriterError.closed) { try writer.append([.integer(2), .integer(0)]) }
        do {
            _ = try writer.finish()
            Issue.record("A failed writer must not return a partial recording")
        } catch { #expect(error as? RecordingCSVFileWriter.FileWriterError == .closed) }
    }

    @Test
    func fieldAndEncodedRowBudgetsIncludeEscapingAndUTF8() throws {
        // This format's header fits both budgets. The data row tests multibyte scalars and doubled quotes.
        let text = String(repeating: "é\"", count: 32)
        let fields: [RecordingCSVWriter.Field] = [.integer(1), .integer(1), .integer(1), .text(text)]
        let rowByteCount = text.utf8.count + 32 + 2 + 7
        let exact = RecordingCSVReader.Limits(maximumByteCount: 1024, maximumRecordByteCount: rowByteCount, maximumFieldByteCount: 96)
        var writer = try RecordingCSVFileWriter(format: .heartRateSamples, limits: exact)
        try writer.append(fields)
        let file = try writer.finish()
        let reader = try RecordingCSVReader(contents(file), format: .heartRateSamples, limits: exact)
        #expect(reader.rows.first?.fields == ["1", "1", "1", text])
        let fieldLimit = RecordingCSVReader.Limits(maximumByteCount: 1024, maximumRecordByteCount: 1024, maximumFieldByteCount: 95)
        var fieldWriter = try RecordingCSVFileWriter(format: .heartRateSamples, limits: fieldLimit)
        #expect(throws: RecordingCSVFileWriter.FileWriterError.fieldLimitExceeded) { try fieldWriter.append(fields) }
        let rowLimit = RecordingCSVReader.Limits(maximumByteCount: 1024, maximumRecordByteCount: rowByteCount - 1, maximumFieldByteCount: 96)
        var rowWriter = try RecordingCSVFileWriter(format: .heartRateSamples, limits: rowLimit)
        #expect(throws: RecordingCSVFileWriter.FileWriterError.recordLimitExceeded) { try rowWriter.append(fields) }
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
