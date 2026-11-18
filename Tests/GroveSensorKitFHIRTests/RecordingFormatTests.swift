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

    @Test("A sidecar path is a relative reference with no empty, dot-dot or rooted segment and no query")
    func sidecarPathIsRelative() throws {
        func recording(at path: String) throws -> SensorKitNativeRecording {
            try SensorKitNativeRecording(
                title: "Native recording",
                format: .nativeRecording,
                payload: .sidecar(path: path, bytes: Data("{}".utf8)),
                admission: .callerAuthorizedOpaquePayload
            )
        }
        for path in [
            "../outside.json", "/absolute.json", "payloads//session-1.json", "session-1.json?version=2",
            "payloads%2Fsession-1.json", "%2e%2e/outside.json"
        ] {
            #expect(throws: SensorKitRecordError.invalidSidecarPath(path)) {
                try recording(at: path)
            }
        }
        #expect(try recording(at: "payloads/ambient-light/session-1.json").decodedPayload() == Data("{}".utf8))
    }
}

// swiftlint:enable file_types_order
