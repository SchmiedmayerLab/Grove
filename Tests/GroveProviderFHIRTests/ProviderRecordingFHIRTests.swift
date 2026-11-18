//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import GroveProviderFHIR
import ModelsR4
import Testing


@Suite
struct ProviderRecordingFHIRTests {
    private static func file(_ bytes: Data) async throws -> RecordingFile {
        let chunks = AsyncStream<Data> { continuation in
            continuation.yield(bytes.prefix(3))
            continuation.yield(bytes.dropFirst(3))
            continuation.finish()
        }
        return try await RecordingFile.stage(chunks: chunks, maximumByteCount: bytes.count)
    }

    @Test("Every native provider stream preserves its exact payload and artifact identity", arguments: ProviderNativeRecording.Source.allCases)
    func bytePreservation(source: ProviderNativeRecording.Source) async throws {
        let bytes = Data(" {\"samples\": [{\"value\": 71.00, \"timestamp\": 1800000000}]}\n".utf8)
        let file = try await Self.file(bytes)
        let input = try ProviderNativeRecording(
            id: "native-one",
            source: source,
            title: "Provider fixture",
            file: file,
            attachmentPath: "recordings/native.json",
            admission: .callerAuthorizedOpaquePayload
        )
        let context = try source == .ouraHeartRate ? OuraFHIRTests.context() : WithingsFHIRTests.context()
        let result = try ProviderFHIRConverter.convert(input, context: context)
        try ProviderFixtures.write([result], provider: "recordings")
        let record = try #require(result.record)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        let document = try #require(bundle.entry?.compactMap { $0.resource?.get() as? DocumentReference }.first)
        let attachment = try #require(document.content.first?.attachment)
        #expect(attachment.data == nil)
        #expect(attachment.url?.value?.url.absoluteString == "recordings/native.json")
        #expect(attachment.size?.value?.integer == Int32(bytes.count))
        #expect(attachment.hash?.value?.data() == file.attachmentSHA1)
        #expect(document.meta?.profile == [Profile.groveSensorRecordingDocument, Profile.providersRecordingDocument])
        #expect(document.identifier?.count == 3)
        #expect(try ProviderFHIRConverter.convert(input, context: context).record?.json == record.json)
        var retained = Data()
        try file.readChunks { retained.append($0) }
        #expect(retained == bytes)
    }

    @Test("Malformed opaque JSON, duplicate members, traversal and capacity overflow refuse before emission")
    func admissionBounds() async throws {
        let valid = try await Self.file(Data("{\"value\": 1}".utf8))
        #expect(throws: ProviderNativeRecording.ValidationError.payloadTooLarge) {
            try ProviderNativeRecording(
                id: "one",
                source: .ouraHeartRate,
                title: "Fixture",
                file: valid,
                attachmentPath: "recording.json",
                maximumByteCount: 2,
                admission: .verifiedSanitizedInput
            )
        }
        #expect(throws: ProviderNativeRecording.ValidationError.invalidPath) {
            try ProviderNativeRecording(
                id: "one",
                source: .ouraHeartRate,
                title: "Fixture",
                file: valid,
                attachmentPath: "../recording.json",
                admission: .verifiedSanitizedInput
            )
        }
        for invalid in ["{\"value\":1,\"value\":2}", "{\"value\":NaN}", "[1,", "123", "\u{FEFF}{}"] {
            let file = try await Self.file(Data(invalid.utf8))
            #expect(throws: ProviderNativeRecording.ValidationError.invalidJSON) {
                try ProviderNativeRecording(
                    id: "one",
                    source: .withingsActivity,
                    title: "Fixture",
                    file: file,
                    attachmentPath: "recording.json",
                    admission: .verifiedSanitizedInput
                )
            }
        }
    }

    @Test("A recording period keeps the source spelling for Oura and Google Health and the source time zone for Withings")
    func recordingPeriod() async throws {
        let file = try await Self.file(Data("{\"value\": 1}".utf8))
        let timestamps = try ProviderNativeRecording.Interval.timestamps(
            ProviderInterval(start: ProviderTimestamp("2026-11-01T08:00:00.120+02:00"), end: ProviderTimestamp("2026-11-01T09:00:00+02:00"))
        )
        let dates = ProviderNativeRecording.Interval.dates(DateInterval(start: WithingsFHIRTests.date, duration: 3_600))
        func recording(_ source: ProviderNativeRecording.Source, _ interval: ProviderNativeRecording.Interval, id: String = "one") throws
            -> ProviderNativeRecording {
            try ProviderNativeRecording(
                id: id,
                source: source,
                title: "Fixture",
                file: file,
                attachmentPath: "recording.json",
                interval: interval,
                admission: .verifiedSanitizedInput
            )
        }
        let oura = try ProviderFHIRConverter.convert(recording(.ouraHeartRate, timestamps), context: OuraFHIRTests.context())
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: try #require(oura.record?.json))
        let document = try #require(bundle.entry?.compactMap { $0.resource?.get() as? DocumentReference }.first)
        #expect(document.context?.period?.start?.value?.description == "2026-11-01T08:00:00.120+02:00")
        #expect(document.context?.period?.end?.value?.description == "2026-11-01T09:00:00+02:00")
        let withings = try ProviderFHIRConverter.convert(recording(.withingsSleep, dates), context: WithingsFHIRTests.context())
        #expect(withings.record != nil)
        for (source, interval) in [(ProviderNativeRecording.Source.withingsActivity, timestamps), (.googleHeartRate, dates), (.ouraHeartRate, dates)] {
            #expect(throws: ProviderNativeRecording.ValidationError.invalidInterval) { try recording(source, interval) }
        }
        #expect(throws: ProviderNativeRecording.ValidationError.invalidInterval) {
            try recording(.withingsSleep, .dates(DateInterval(start: WithingsFHIRTests.date, duration: 0)))
        }
        #expect(throws: ProviderNativeRecording.ValidationError.invalidIdentifier) { try recording(.withingsSleep, dates, id: "") }
    }

    @Test("Every native recording stream is advertised as its provider's native recording token")
    func nativeRecordingTokens() async throws {
        let bytes = Data("{\"value\": 1}".utf8)
        let chunks = AsyncStream<Data> { continuation in
            continuation.yield(bytes)
            continuation.finish()
        }
        let file = try await RecordingFile.stage(chunks: chunks, maximumByteCount: bytes.count)
        for provider in ProviderCapabilities.Provider.allCases {
            let context = try switch provider {
            case .oura: OuraFHIRTests.context()
            case .googleHealthAPI: ProviderUnitConversionTests.googleHealthContext()
            case .withings: WithingsFHIRTests.context()
            }
            let converted = try ProviderNativeRecording.Source.allCases.filter { $0.rawValue.hasPrefix(provider.rawValue + "/") }.map {
                let recording = try ProviderNativeRecording(
                    id: "native-one",
                    source: $0,
                    title: "Fixture",
                    file: file,
                    attachmentPath: "recording.json",
                    admission: .verifiedSanitizedInput
                )
                return try ProviderFHIRConverter.convert(recording, context: context).sourceToken
            }
            let advertised = ProviderCapabilities.sources(for: provider).filter { $0.conversionSupport == .nativeRecording }.map(\.token)
            #expect(Set(converted) == Set(advertised))
            #expect(!converted.isEmpty)
        }
    }

    @Test("File-backed transport compression preserves the FHIR source checksum")
    func compression() async throws {
        let bytes = Data(("{\"padding\":\"" + String(repeating: "x", count: 32_768) + "\"}").utf8)
        let file = try await Self.file(bytes)
        let compressed = try #require(try file.zstandardCompressed())
        #expect(compressed.byteCount < file.byteCount)
        let decoded = try compressed.zstandardDecompressed(decompressedByteCount: file.byteCount)
        #expect(decoded.attachmentSHA1 == file.attachmentSHA1)
        let input = try ProviderNativeRecording(
            id: "one",
            source: .withingsSleep,
            title: "Fixture",
            file: decoded,
            attachmentPath: "recording.json",
            admission: .verifiedSanitizedInput
        )
        #expect(try ProviderFHIRConverter.convert(input, context: WithingsFHIRTests.context()).record != nil)
    }
}
