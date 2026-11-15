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


struct RecordingCSVStreamTests {
    private enum TestFailure: Error { case unexpectedSuccess }

    @Test
    func everyFormatAndChunkBoundaryPreservesRows() throws {
        for format in RegisteredRecordingFormat.tabularFormats {
            var writer = try RecordingCSVWriter(format: format)
            try writer.append(RecordingCSVSchemaFixtures.row(format: format, variant: 0))
            try writer.append(RecordingCSVSchemaFixtures.row(format: format, variant: 1))
            let data = writer.data()
            let expected = try RecordingCSVReader(data, format: format).rows
            #expect(expected.count == 2)
            // Every possible split covers quotes, escaped quotes, delimiters and multibyte scalars.
            for split in 0...data.count {
                var stream = try RecordingCSVReader.Stream(format: format)
                var actual: [RecordingCSVReader.Row] = []
                try stream.read(data.prefix(split)) { actual.append($0) }
                try stream.read(data.dropFirst(split)) { actual.append($0) }
                try stream.finish()
                #expect(actual == expected)
            }
            #expect(try rows(data, chunkSize: 1, format: format) == expected)
        }
    }

    @Test(arguments: [
        "1,60,2,\"unterminated\n", "1,60,2,un\"quoted\n", "1,60,2,\"closed\"x\n",
        "1,60,2,\"carriage\rreturn\"\n", "1,60,2,Watch", "1,60,2\n", "1,60,2,Watch,extra\n"
    ])
    func malformedRowsFailIdenticallyAtEveryChunkSize(row: String) throws {
        let data = Data((try header() + row).utf8)
        let expected = try rejection(data, chunkSize: data.count)
        for chunkSize in 1...data.count {
            #expect(try rejection(data, chunkSize: chunkSize) == expected)
        }
    }

    @Test
    func malformedUTF8IsNeverReplacedOrAcceptedAtEndOfInput() throws {
        for bytes: [UInt8] in [[0xC0, 0xAF], [0xE2, 0x28, 0xA1], [0xED, 0xA0, 0x80], [0xF0, 0x9F]] {
            for terminated in [false, true] {
                var data = Data((try header() + "1,60,2,").utf8)
                data.append(contentsOf: bytes)
                if terminated { data.append(UInt8(ascii: "\n")) }
                for chunkSize in 1...data.count {
                    #expect(try rejection(data, chunkSize: chunkSize) == .invalidUTF8)
                }
            }
        }
    }

    @Test
    func totalRecordAndFieldLimitsHaveExactInclusiveBoundaries() throws {
        let header = try header()
        let field = String(repeating: "✓", count: 16)
        let record = "1,60,2,\(field)\n"
        let data = Data((header + record).utf8)
        let limits = RecordingCSVReader.Limits(
            maximumByteCount: data.count,
            maximumRecordByteCount: record.utf8.count,
            maximumFieldByteCount: field.utf8.count
        )
        #expect(try rows(data, chunkSize: 1, limits: limits).first?.fields.last == field)
        #expect(try RecordingCSVReader(data, format: .heartRateSamples, limits: limits).rows.count == 1)
        let tooSmall: [(RecordingCSVReader.Limits, RecordingCSVReader.ReaderError)] = [
            (.init(maximumByteCount: data.count - 1, maximumRecordByteCount: record.utf8.count, maximumFieldByteCount: field.utf8.count),
             .payloadLimitExceeded),
            (.init(maximumByteCount: data.count, maximumRecordByteCount: record.utf8.count - 1, maximumFieldByteCount: field.utf8.count),
             .recordLimitExceeded(row: 1)),
            (.init(maximumByteCount: data.count, maximumRecordByteCount: record.utf8.count, maximumFieldByteCount: field.utf8.count - 1),
             .fieldLimitExceeded(row: 1, column: 3))
        ]
        for (limit, error) in tooSmall {
            #expect(try rejection(data, chunkSize: 1, limits: limit) == error)
            #expect(throws: error) { try RecordingCSVReader(data, format: .heartRateSamples, limits: limit) }
        }
    }

    @Test(arguments: [0, -1, Int(Int32.max) + 1])
    func invalidLimitsFailBeforeReading(value: Int) {
        for limits in [
            RecordingCSVReader.Limits(maximumByteCount: value, maximumRecordByteCount: 100, maximumFieldByteCount: 100),
            .init(maximumByteCount: 100, maximumRecordByteCount: value, maximumFieldByteCount: 100),
            .init(maximumByteCount: 100, maximumRecordByteCount: 100, maximumFieldByteCount: value)
        ] {
            #expect(throws: RecordingCSVReader.ReaderError.invalidReadLimits) {
                try RecordingCSVReader.Stream(format: .heartRateSamples, limits: limits)
            }
        }
    }

    @Test
    func consumerFailureAndCompletionCloseTheStream() throws {
        enum ConsumerError: Error { case refused }
        let data = Data((try header() + "1,60,2,Watch\n").utf8)
        var failed = try RecordingCSVReader.Stream(format: .heartRateSamples)
        #expect(throws: ConsumerError.refused) {
            try failed.read(data) { _ in throw ConsumerError.refused }
        }
        #expect(throws: RecordingCSVReader.ReaderError.streamClosed) { try failed.finish() }
        #expect(throws: RecordingCSVReader.ReaderError.streamClosed) { try failed.read(data) { _ in } }
        var finished = try RecordingCSVReader.Stream(format: .heartRateSamples)
        try finished.read(data) { _ in }
        try finished.finish()
        #expect(throws: RecordingCSVReader.ReaderError.streamClosed) { try finished.read(data) { _ in } }
        #expect(throws: RecordingCSVReader.ReaderError.streamClosed) { try finished.finish() }
    }

    @Test
    func emptyWrongHeaderAndUnboundedColumnCountsAreRejected() throws {
        #expect(try rejection(Data(), chunkSize: 1) == .missingHeader)
        let wrong = Data("timestamp,other,confidence,device\n".utf8)
        let expected = try rejection(wrong, chunkSize: wrong.count)
        #expect(try rejection(wrong, chunkSize: 1) == expected)
        let excessiveColumns = Data((try header() + String(repeating: ",", count: 100_000) + "\n").utf8)
        #expect(try rejection(excessiveColumns, chunkSize: 1) == .columnCountMismatch(row: 1, expected: 4, actual: 5))
    }

    private func header() throws -> String {
        try #require(RegisteredRecordingFormat.heartRateSamples.csvColumns).joined(separator: ",") + "\n"
    }

    private func rows(
        _ data: Data,
        chunkSize: Int,
        format: RegisteredRecordingFormat = .heartRateSamples,
        limits: RecordingCSVReader.Limits = .default
    ) throws -> [RecordingCSVReader.Row] {
        var stream = try RecordingCSVReader.Stream(format: format, limits: limits)
        var rows: [RecordingCSVReader.Row] = []
        for start in stride(from: 0, to: data.count, by: chunkSize) {
            try stream.read(data.subdata(in: start..<min(start + chunkSize, data.count))) { rows.append($0) }
        }
        try stream.finish()
        return rows
    }

    private func rejection(
        _ data: Data,
        chunkSize: Int,
        limits: RecordingCSVReader.Limits = .default
    ) throws -> RecordingCSVReader.ReaderError {
        do {
            _ = try rows(data, chunkSize: chunkSize, limits: limits)
            throw TestFailure.unexpectedSuccess
        } catch let error as RecordingCSVReader.ReaderError {
            return error
        }
    }
}
