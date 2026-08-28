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

// swiftlint:disable file_types_order


@Suite
struct RecordingCSVWriterTests {
    @Test
    func headerAndEveryRowEndInLineFeed() throws {
        var writer = RecordingCSVWriter(columns: ["timestamp", "value"])
        try writer.append([.timestamp(Date(timeIntervalSince1970: 0)), .number(1.5)])
        let text = String(decoding: writer.data(), as: UTF8.self)
        // The registry requires LF after every row, the last one included, and no byte-order mark.
        #expect(text == "timestamp,value\n0.0,1.5\n")
    }

    @Test
    func aFieldContainingCRLFIsQuoted() throws {
        var writer = RecordingCSVWriter(columns: ["note"])
        try writer.append([.text("line1\r\nline2")])
        let text = String(decoding: writer.data(), as: UTF8.self)
        // Swift treats CRLF as one Character equal to neither "\n" nor "\r", so a character-wise
        // quoting test misses it and the raw break splits the row.
        #expect(text == "note\n\"line1\r\nline2\"\n")
    }

    @Test
    func quotingAppliesExactlyToTheRegistrysThreeTriggers() throws {
        var writer = RecordingCSVWriter(columns: ["a", "b", "c", "d"])
        try writer.append([.text("plain"), .text("has,comma"), .text("has\"quote"), .text("has\nbreak")])
        let text = String(decoding: writer.data(), as: UTF8.self)
        #expect(text.hasSuffix("plain,\"has,comma\",\"has\"\"quote\",\"has\nbreak\"\n"))
    }

    @Test
    func decimalsNeverUseExponentNotation() throws {
        // The registry's decimal form admits no exponent, but Swift's shortest round-trip
        // description switches to one outside a middling range. Odometer slope and wrist-temperature
        // error estimates reach these magnitudes.
        var writer = RecordingCSVWriter(columns: ["v"])
        for value in [1e-5, 1e-7, 1e16, 0.1, -0.25] {
            try writer.append([.number(value)])
        }
        let text = String(decoding: writer.data(), as: UTF8.self)
        #expect(!text.lowercased().contains("e"))
        for line in text.split(separator: "\n").dropFirst() {
            #expect(Double(line) != nil, "\(line) does not parse as a plain decimal")
        }
    }

    @Test
    func everyWrittenNumberRoundTrips() throws {
        for value in [1e-5, 1e-7, 1e16, 0.1, 1.0 / 3.0, -0.25, 1234.5678] {
            var writer = RecordingCSVWriter(columns: ["v"])
            try writer.append([.number(value)])
            let line = String(decoding: writer.data(), as: UTF8.self).split(separator: "\n")[1]
            #expect(Double(line) == value, "\(line) does not round-trip \(value)")
        }
    }

    @Test
    func nonFiniteValuesAreRejectedIncludingTimestamps() {
        #expect(appendError([.number(.nan)]) == .nonFiniteNumber(column: "v"))
        #expect(appendError([.timestamp(Date(timeIntervalSince1970: .infinity))]) == .nonFiniteNumber(column: "v"))
    }

    @Test
    func aRowMustMatchTheDeclaredColumnCount() {
        #expect(appendError([.text("a"), .text("b")]) == .columnCountMismatch(expected: 1, actual: 2))
    }

    /// The error one row produces, or nil when it is accepted.
    private func appendError(_ fields: [RecordingCSVWriter.Field]) -> RecordingCSVWriter.WriterError? {
        var writer = RecordingCSVWriter(columns: ["v"])
        do {
            try writer.append(fields)
            return nil
        } catch let error as RecordingCSVWriter.WriterError {
            return error
        } catch {
            return nil
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
                #expect(format.registeredContentType == "text/csv", "\(format.rawValue)")
            } else {
                #expect(format.registeredContentType != "text/csv", "\(format.rawValue)")
            }
        }
    }
}


@Suite
struct RecordingBinaryWriterTests {
    @Test
    func varintMatchesUnsignedLEB128() {
        var writer = RecordingBinaryWriter()
        writer.writeVarint(UInt64(0))
        #expect(Array(writer.data()) == [0x00])

        var maximum = RecordingBinaryWriter()
        maximum.writeVarint(UInt64.max)
        let bytes = Array(maximum.data())
        #expect(bytes.count == 10)
        #expect(bytes.last == 0x01)
    }

    @Test
    func negativeIntegersOccupyTenBytes() {
        // The registry states signed values are truncated to their 64-bit two's-complement pattern,
        // so a negative value fills all ten groups.
        var writer = RecordingBinaryWriter()
        writer.writeVarint(Int64(-1))
        #expect(Array(writer.data()).count == 10)
    }

    @Test
    func float64IsBigEndian() {
        var writer = RecordingBinaryWriter()
        writer.writeFloat64(1.0)
        #expect(Array(writer.data()) == [0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    @Test
    func stringsCarryAVarintByteCount() {
        var writer = RecordingBinaryWriter()
        writer.writeString("hi")
        #expect(Array(writer.data()) == [0x02, 0x68, 0x69])
    }

    @Test
    func optionalsCarryAPresenceByte() {
        var present = RecordingBinaryWriter()
        present.writeOptionalFloat64(1.0)
        let presentBytes = Array(present.data())
        #expect(presentBytes.first == 0x01)
        #expect(presentBytes.count == 9)

        var absent = RecordingBinaryWriter()
        absent.writeOptionalFloat64(nil)
        #expect(Array(absent.data()) == [0x00])
    }
}

// swiftlint:enable file_types_order
