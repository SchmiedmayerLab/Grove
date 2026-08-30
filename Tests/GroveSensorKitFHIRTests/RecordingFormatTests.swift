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
    func float64IsBigEndian() throws {
        var writer = RecordingBinaryWriter()
        try writer.writeFloat64(1.0)
        #expect(Array(writer.data()) == [0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    @Test
    func stringsCarryAVarintByteCount() {
        var writer = RecordingBinaryWriter()
        writer.writeString("hi")
        #expect(Array(writer.data()) == [0x02, 0x68, 0x69])
    }

    @Test
    func optionalsCarryAPresenceByte() throws {
        var present = RecordingBinaryWriter()
        try present.writeOptionalFloat64(1.0)
        let presentBytes = Array(present.data())
        #expect(presentBytes.first == 0x01)
        #expect(presentBytes.count == 9)

        var absent = RecordingBinaryWriter()
        try absent.writeOptionalFloat64(nil)
        #expect(Array(absent.data()) == [0x00])
    }

    @Test
    func nonFiniteFloatsAreRejectedAndNegativeZeroIsCanonicalized() throws {
        var nonFinite = RecordingBinaryWriter()
        #expect(throws: RecordingBinaryWriter.WriterError.nonFiniteFloat) {
            try nonFinite.writeFloat64(.nan)
        }

        var zero = RecordingBinaryWriter()
        try zero.writeFloat64(-0.0)
        #expect(Array(zero.data()) == Array(repeating: 0, count: 8))
    }
}


@Suite
struct RecordingBinaryReaderTests {
    @Test
    func overlongAndOverflowingVarintsAreRejected() {
        var overlong = RecordingBinaryReader(Data([0x80, 0x00]))
        #expect(throws: RecordingBinaryReader.ReaderError.nonCanonicalVarint) {
            _ = try overlong.readVarint()
        }

        var overflow = RecordingBinaryReader(Data(Array(repeating: 0x80, count: 9) + [0x02]))
        #expect(throws: RecordingBinaryReader.ReaderError.varintOverflow) {
            _ = try overflow.readVarint()
        }
    }

    @Test
    func malformedStringsAndFloatsAreRejected() {
        var malformedUTF8 = RecordingBinaryReader(Data([0x01, 0xFF]))
        #expect(throws: RecordingBinaryReader.ReaderError.invalidUTF8) {
            _ = try malformedUTF8.readString()
        }

        var negativeZero = RecordingBinaryReader(Data([0x80, 0, 0, 0, 0, 0, 0, 0]))
        #expect(throws: RecordingBinaryReader.ReaderError.nonCanonicalNegativeZero) {
            _ = try negativeZero.readFloat64()
        }

        var infinity = RecordingBinaryReader(Data([0x7F, 0xF0, 0, 0, 0, 0, 0, 0]))
        #expect(throws: RecordingBinaryReader.ReaderError.nonFiniteFloat) {
            _ = try infinity.readFloat64()
        }
    }

    @Test
    func duplicateOrDescendingSetValuesAreRejected() {
        var duplicate = RecordingBinaryReader(Data([0x02, 0x01, 0x01]))
        #expect(throws: RecordingBinaryReader.ReaderError.nonAscendingSet) {
            _ = try duplicate.readCanonicalSet { try $0.readVarint() }
        }

        var descending = RecordingBinaryReader(Data([0x02, 0x02, 0x01]))
        #expect(throws: RecordingBinaryReader.ReaderError.nonAscendingSet) {
            _ = try descending.readCanonicalSet { try $0.readVarint() }
        }
    }
}


@Suite
struct RegisteredRecordingPayloadTests {
    private static let validCollection = Data(#"""
        {
          "resourceType": "Bundle",
          "type": "collection",
          "timestamp": "2026-08-20T19:00:00Z",
          "entry": [{
            "fullUrl": "urn:uuid:3314ab4c-4ab3-536f-a556-e3b6ff97762d",
            "resource": { "resourceType": "Patient" }
          }]
        }
        """#.utf8)

    @Test("The replacement FHIR collection format accepts one closed R4 collection Bundle")
    func collectionBundleIsAccepted() throws {
        try RegisteredRecordingFormat.fhirCollectionBundle.validatePayload(Self.validCollection)
    }

    @Test("A bare resource array is not a registered FHIR payload")
    func resourceArrayIsRejected() {
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirCollectionBundle.validatePayload(
                Data(#"[{"resourceType":"Patient"}]"#.utf8)
            )
        }
    }

    @Test("Transaction semantics cannot hide inside a source-preservation collection")
    func transactionFieldsAreRejected() {
        let transaction = Data(#"""
            {
              "resourceType": "Bundle",
              "type": "collection",
              "timestamp": "2026-08-20T19:00:00Z",
              "entry": [{
                "fullUrl": "urn:uuid:3314ab4c-4ab3-536f-a556-e3b6ff97762d",
                "resource": { "resourceType": "Patient" },
                "request": { "method": "POST", "url": "Patient" }
              }]
            }
            """#.utf8)
        #expect(throws: RegisteredRecordingPayloadError.forbiddenEntryRequest(index: 0)) {
            try RegisteredRecordingFormat.fhirCollectionBundle.validatePayload(transaction)
        }
    }

    @Test("The release-neutral FHIR format accepts one resource object, never an array")
    func fhirResourceShapeIsClosed() throws {
        try RegisteredRecordingFormat.fhirResource.validatePayload(
            Data(#"{"resourceType":"Patient"}"#.utf8)
        )
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirResource.validatePayload(
                Data(#"[{"resourceType":"Patient"}]"#.utf8)
            )
        }
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirResource.validatePayload(
                Data(#"{"resourceType":""}"#.utf8)
            )
        }
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirResource.validatePayload(
                Data(#"{"resourceType":"observation"}"#.utf8)
            )
        }
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirResource.validatePayload(
                Data(#"{"resourceType":"Patient","resourceType":"Observation"}"#.utf8)
            )
        }
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirResource.validatePayload(
                Data([0xEF, 0xBB, 0xBF]) + Data(#"{"resourceType":"Patient"}"#.utf8)
            )
        }
        let utf16Payload = try #require(
            #"{"resourceType":"Patient"}"#.data(using: .utf16LittleEndian)
        )
        #expect(throws: RegisteredRecordingPayloadError.invalidFHIRJSON) {
            try RegisteredRecordingFormat.fhirResource.validatePayload(
                utf16Payload
            )
        }
    }

    @Test("A multi-representation format requires one exact registered media type")
    func fhirResourceMediaTypeIsExplicit() throws {
        let payload = Data(#"{"resourceType":"Patient"}"#.utf8)

        #expect(throws: SensorKitRecordError.invalidContentType) {
            try SensorKitNativeRecording(
                title: "Provider-issued FHIR resource",
                format: .fhirResource,
                payload: .inline(payload),
                admission: .callerAuthorizedOpaquePayload
            )
        }
        #expect(throws: SensorKitRecordError.invalidContentType) {
            try SensorKitNativeRecording(
                title: "Provider-issued FHIR resource",
                format: .fhirResource,
                contentType: "application/fhir+json",
                payload: .inline(payload),
                admission: .callerAuthorizedOpaquePayload
            )
        }

        let recording = try SensorKitNativeRecording(
            title: "Provider-issued FHIR resource",
            format: .fhirResource,
            contentType: "application/fhir+json; fhirVersion=1.0",
            payload: .inline(payload),
            admission: .callerAuthorizedOpaquePayload
        )
        #expect(recording.contentType == "application/fhir+json; fhirVersion=1.0")
    }

    @Test("Native JSON accepts objects and arrays but rejects lossy envelopes")
    func nativeJSONEnvelopeIsStrict() throws {
        try RegisteredRecordingFormat.nativeRecording.validatePayload(Data(#"{"a":1}"#.utf8))
        try RegisteredRecordingFormat.nativeRecording.validatePayload(Data(#"[1,true,null]"#.utf8))

        #expect(throws: RegisteredRecordingPayloadError.expectedJSONObjectOrArray) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(Data(#"42"#.utf8))
        }
        #expect(throws: RegisteredRecordingPayloadError.duplicateJSONMember("a")) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(Data(#"{"a":1,"\u0061":2}"#.utf8))
        }
        #expect(throws: RegisteredRecordingPayloadError.JSONByteOrderMark) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(Data([0xEF, 0xBB, 0xBF]) + Data(#"{}"#.utf8))
        }
        #expect(throws: RegisteredRecordingPayloadError.nonFiniteJSONNumber) {
            try RegisteredRecordingFormat.nativeRecording.validatePayload(Data(#"{"a":1e9999}"#.utf8))
        }
    }
}

// swiftlint:enable file_types_order
