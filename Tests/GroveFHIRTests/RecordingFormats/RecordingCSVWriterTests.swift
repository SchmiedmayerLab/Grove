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
        var writer = RecordingCSVWriter(columns: ["timestamp", "value"])
        try writer.append([.timestamp(Date(timeIntervalSince1970: 0)), .number(1.5)])
        let text = String(decoding: writer.data(), as: UTF8.self)
        // The registry requires LF after every row, the last one included, and no byte-order mark.
        #expect(text == "timestamp,value\n0,1.5\n")
    }

    @Test
    func carriageReturnIsRejectedEvenInsideAQuotedField() throws {
        var writer = RecordingCSVWriter(columns: ["note"])
        #expect(throws: RecordingCSVWriter.WriterError.carriageReturn(column: "note")) {
            try writer.append([.text("line1\r\nline2")])
        }
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
