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
struct RecordingCSVWriterTests {
    @Test
    func headerAndEveryRowEndInLineFeed() throws {
        var writer = try RecordingCSVWriter(format: .beatIntervalSeries)
        try writer.append([.timestamp(Date(timeIntervalSince1970: 0)), .integer(1)])
        let text = String(decoding: writer.data(), as: UTF8.self)
        // The registry requires LF after every row, the last one included, and no byte-order mark.
        #expect(text == "timestamp,precededByGap\n0,1\n")
    }

    @Test
    func carriageReturnIsRejectedEvenInsideAQuotedField() throws {
        #expect(appendError([.integer(1), .number(60), .integer(2), .text("line1\r\nline2")]) == .carriageReturn(column: "device"))
    }

    @Test
    func quotingAppliesExactlyToTheRegistrysThreeTriggers() throws {
        var writer = try RecordingCSVWriter(format: .heartRateSamples)
        for device in ["plain", "has,comma", "has\"quote", "has\nbreak"] {
            try writer.append([.integer(1), .number(60), .integer(2), .text(device)])
        }
        let text = String(decoding: writer.data(), as: UTF8.self)
        #expect(text.hasSuffix("1,60,2,plain\n1,60,2,\"has,comma\"\n1,60,2,\"has\"\"quote\"\n1,60,2,\"has\nbreak\"\n"))
    }

    @Test
    func decimalsNeverUseExponentNotation() throws {
        // The registry's decimal form admits no exponent, but Swift's shortest round-trip
        // description switches to one outside a middling range. Odometer slope and wrist-temperature
        // error estimates reach these magnitudes.
        for value in [1e-5, 1e-7, 1e16, 0.1, -0.25] {
            let written = try Self.writtenValue(value)
            #expect(!written.lowercased().contains("e"))
            #expect(Double(written) != nil, "\(written) does not parse as a plain decimal")
        }
    }

    @Test
    func everyWrittenNumberRoundTrips() throws {
        for value in [1e-5, 1e-7, 1e16, 0.1, 1.0 / 3.0, -0.25, 1234.5678] {
            let written = try Self.writtenValue(value)
            #expect(Double(written) == value, "\(written) does not round-trip \(value)")
        }
    }

    @Test
    func nonFiniteValuesAreRejectedIncludingTimestamps() {
        #expect(appendError([.integer(1), .number(.nan), .integer(2), .text("Watch")]) == .nonFiniteNumber(column: "value"))
        #expect(
            appendError([.timestamp(Date(timeIntervalSince1970: .infinity)), .number(60), .integer(2), .text("Watch")])
                == .nonFiniteNumber(column: "timestamp")
        )
    }

    @Test
    func aRowMustMatchTheDeclaredColumnCount() {
        #expect(appendError([.text("a")]) == .columnCountMismatch(expected: 4, actual: 1))
    }

    @Test
    func aFormatWithoutColumnsHasNoWriter() {
        #expect(throws: RecordingCSVWriter.WriterError.notTabular(.nativeRecording)) {
            _ = try RecordingCSVWriter(format: .nativeRecording)
        }
    }

    @Test
    func encodedBudgetsIncludeHeaderEscapingAndTerminator() throws {
        let value = String(repeating: "✓\"", count: 12)
        let header = "timestamp,value,confidence,device\n"
        let record = "1,60,2,\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"\n"
        let expected = Data((header + record).utf8)
        let row: [RecordingCSVWriter.Field] = [.integer(1), .number(60), .integer(2), .text(value)]
        let field = value.utf8.count
        let size = record.utf8.count
        let total = expected.count
        let limits = RecordingCSVReader.Limits(maximumByteCount: total, maximumRecordByteCount: size, maximumFieldByteCount: field)
        var writer = try RecordingCSVWriter(format: .heartRateSamples, limits: limits)
        try writer.append(row)
        #expect(throws: RecordingCSVWriter.WriterError.payloadLimitExceeded) { try writer.append(row) }
        let bytes = writer.data()
        #expect(bytes == expected)
        #expect(try RecordingCSVReader(bytes, format: .heartRateSamples, limits: limits).rows.first?.fields.last == value)
        var stream = try RecordingCSVReader.Stream(format: .heartRateSamples, limits: limits)
        var devices: [String?] = []
        for byte in bytes {
            try stream.read(Data([byte])) { devices.append($0["device"]) }
        }
        try stream.finish()
        #expect(devices == [value])
        let refusals: [(RecordingCSVReader.Limits, RecordingCSVWriter.WriterError)] = [
            (.init(maximumByteCount: total - 1), .payloadLimitExceeded),
            (.init(maximumRecordByteCount: size - 1), .recordLimitExceeded),
            (.init(maximumFieldByteCount: field - 1), .fieldLimitExceeded)
        ]
        for (limit, error) in refusals {
            var bounded = try RecordingCSVWriter(format: .heartRateSamples, limits: limit)
            #expect(throws: error) { try bounded.append(row) }
            try bounded.append([.integer(0), .integer(1), .integer(2), .text("ok")])
            let accepted = bounded.data()
            #expect(accepted == Data((header + "0,1,2,ok\n").utf8))
        }
    }

    @Test
    func headerFitsEveryConfiguredBudget() throws {
        let header = Data("timestamp,precededByGap\n".utf8)
        let fieldCount = "precededByGap".utf8.count
        let limits = RecordingCSVReader.Limits(
            maximumByteCount: header.count, maximumRecordByteCount: header.count, maximumFieldByteCount: fieldCount
        )
        let writer = try RecordingCSVWriter(format: .beatIntervalSeries, limits: limits)
        let bytes = writer.data()
        #expect(bytes == header)
        let refusals: [(RecordingCSVReader.Limits, RecordingCSVWriter.WriterError)] = [
            (.init(maximumByteCount: header.count - 1), .payloadLimitExceeded),
            (.init(maximumRecordByteCount: header.count - 1), .recordLimitExceeded),
            (.init(maximumFieldByteCount: fieldCount - 1), .fieldLimitExceeded),
            (.init(maximumByteCount: 0), .invalidWriteLimits)
        ]
        for (limit, error) in refusals {
            #expect(throws: error) { _ = try RecordingCSVWriter(format: .beatIntervalSeries, limits: limit) }
        }
    }

    @Test
    func fieldBudgetPrecedesNumericParsing() throws {
        var writer = try RecordingCSVWriter(format: .heartRateSamples)
        let field = String(repeating: ".", count: RecordingCSVReader.Limits.default.maximumFieldByteCount)
        #expect(throws: RecordingCSVWriter.WriterError.invalidValue(column: "value")) {
            try writer.append([.integer(1), .text(field), .integer(2), .text("watch")])
        }
        #expect(throws: RecordingCSVWriter.WriterError.fieldLimitExceeded) {
            try writer.append([.integer(1), .text(field + "."), .integer(2), .text("watch")])
        }
    }

    /// The error one heart-rate row produces, or nil when it is accepted.
    private func appendError(_ fields: [RecordingCSVWriter.Field]) -> RecordingCSVWriter.WriterError? {
        do {
            var writer = try RecordingCSVWriter(format: .heartRateSamples)
            try writer.append(fields)
            return nil
        } catch {
            return error
        }
    }

    @Test
    func publishedColumnSetsMatchTheRegistry() {
        // The producer emits the registry's declared columns rather than inventing its own,
        // and the columns hang off the format code the document already declares.
        #expect(RegisteredRecordingFormat.heartRateSamples.csvColumns == ["timestamp", "value", "confidence", "device"])
        #expect(
            RegisteredRecordingFormat.wristTemperatureSamples.csvColumns
                == ["timestamp", "value", "errorEstimate", "condition"]
        )
    }

    @Test
    func onlyTabularFormatsPublishColumns() {
        // A format that is not tabular publishes no column set, so a reader cannot be pointed
        // at one by mistake and silently succeed.
        for format in RegisteredRecordingFormat.allCases {
            let isTabular = RegisteredRecordingFormat.tabularFormats.contains(format)
            #expect((format.csvColumns != nil) == isTabular, "\(format.rawValue)")
            if isTabular {
                #expect(format.registeredContentTypes == ["text/csv"], "\(format.rawValue)")
            } else {
                #expect(!format.registeredContentTypes.contains("text/csv"), "\(format.rawValue)")
            }
        }
    }

    @Test
    func fhirResourcePublishesItsVersionedRepresentations() {
        #expect(RegisteredRecordingFormat.fhirResource.registeredContentTypes == [
            "application/fhir+json; fhirVersion=1.0",
            "application/fhir+json; fhirVersion=4.0"
        ])
        #expect(RegisteredRecordingFormat.fhirResource.registeredContentType == nil)
        #expect(RegisteredRecordingFormat.fhirCollectionBundle.registeredContentType == "application/fhir+json")
    }
}


extension RecordingCSVWriterTests {
    /// The `value` field of a wrist-temperature row stating `value`.
    fileprivate static func writtenValue(_ value: Double) throws -> String {
        var writer = try RecordingCSVWriter(format: .wristTemperatureSamples)
        try writer.append([.timestamp(Date(timeIntervalSince1970: 1)), .number(value), .number(0.1), .absent])
        let row = String(decoding: writer.data(), as: UTF8.self).split(separator: "\n")[1]
        return String(row.split(separator: ",")[1])
    }
}
