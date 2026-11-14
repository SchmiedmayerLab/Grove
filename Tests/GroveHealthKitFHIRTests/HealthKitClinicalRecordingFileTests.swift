//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


struct HealthKitClinicalRecordingFileTests {
    private static var authorizedInputs: ExportInputs {
        var inputs = ExportInputs()
        inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        return inputs
    }

    private static func record(_ bytes: Data?, version: String = "4.0.1") throws -> HKClinicalRecord {
        try StoredSampleFixtures.clinicalRecord(
            HKClinicalType(.labResultRecord),
            fhirVersion: HKFHIRVersion(fromVersionString: version),
            resource: bytes,
            facts: GoldenCase.seriesFacts(uuid: 0xF3, duration: 0)
        )
    }

    private static func emit(_ record: ExchangeRecord, attachment: Data, path: String, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["GROVE_CLINICAL_FIXTURE_DIRECTORY"] else {
            return
        }
        let root = URL(filePath: directory, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
        let original = root.appending(path: path)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try attachment.write(to: original, options: .withoutOverwriting)
        try record.json.write(to: root.appending(path: "bundle.json"), options: .withoutOverwriting)
    }

    @Test(arguments: ["1.0.2", "4.0.1"])
    func clinicalFileKeepsOriginalBytesReleaseIdentityAndDoesNotInventServiceDates(version: String) async throws {
        let bytes = Data("{\n  \"resourceType\": \"Observation\", \"status\": \"final\", \"effectiveDateTime\": \"2000-01-01T00:00:00Z\"\n}".utf8)
        let sample = try Self.record(bytes, version: version)
        let prepared = try await HealthKitRecordingFile.clinicalRecord(sample, relativePath: "documents/lab.json", maximumByteCount: bytes.count)
        var actual = Data()
        try prepared.file.readChunks { actual.append($0) }
        #expect(actual == bytes)
        let inline = try await ExporterFixtures.export(sample, Self.authorizedInputs)
        let external = try await ExporterFixtures.export(.fileRecording(prepared), Self.authorizedInputs)
        let original = try #require(inline.document.content.first?.attachment)
        let attachment = try #require(external.document.content.first?.attachment)
        #expect(attachment.data == nil && attachment.url?.value?.url.absoluteString == "documents/lab.json")
        #expect(attachment.contentType == original.contentType && attachment.title == original.title)
        #expect(attachment.hash == original.hash && attachment.size == original.size)
        #expect(external.document.identifier == inline.document.identifier)
        #expect(external.document.identifier?.contains {
            $0.system?.value?.url.absoluteString == GoldenFixtures.nativeIdentifierSystem.rawValue
                && $0.value?.value?.string == sample.uuid.uuidString.lowercased()
        } == true)
        #expect(external.document.extension?.contains { $0.url == Canonicals.healthKitSourceMetadata } != true)
        #expect(external.document.context?.period == nil && inline.document.context?.period == nil)
        try Self.emit(external.record, attachment: actual, path: prepared.relativePath, name: "clinical-record-\(version)")
    }

    @MainActor
    @Test
    func cdaFileKeepsTheOriginalDocumentAndSourceTitle() async throws {
        let bytes = Data(GoldenCase.clinicalDocumentXML.utf8)
        let sample = try HKCDADocumentSample(
            data: bytes, start: Date(timeIntervalSince1970: 1_700_000_000), end: Date(timeIntervalSince1970: 1_700_000_100), metadata: nil
        )
        let prepared = try await HealthKitRecordingFile.cdaDocument(sample, relativePath: "documents/summary.xml", maximumByteCount: bytes.count)
        var actual = Data()
        try prepared.file.readChunks { actual.append($0) }
        #expect(actual == bytes)
        let inline = try await ExporterFixtures.export(sample, Self.authorizedInputs)
        let external = try await ExporterFixtures.export(.fileRecording(prepared), Self.authorizedInputs)
        let original = try #require(inline.document.content.first?.attachment)
        let attachment = try #require(external.document.content.first?.attachment)
        #expect(attachment.data == nil && attachment.contentType == original.contentType)
        #expect(attachment.title == original.title && attachment.hash == original.hash && attachment.size == original.size)
        #expect(external.document.context?.period == nil)
        #expect(external.document.identifier?.contains {
            $0.system?.value?.url.absoluteString == GoldenFixtures.nativeIdentifierSystem.rawValue
                && $0.value?.value?.string == sample.uuid.uuidString.lowercased()
        } == true)
        #expect(external.document.extension?.contains { $0.url == Canonicals.healthKitSourceMetadata } != true)
        try Self.emit(external.record, attachment: actual, path: prepared.relativePath, name: "cda-document")
    }

    @Test
    func byteLimitPrecedesJSONValidationAndNeverReturnsAPartialFile() async throws {
        let invalid = try Self.record(Data("invalid JSON".utf8))
        await #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try await HealthKitRecordingFile.clinicalRecord(invalid, relativePath: "document.json", maximumByteCount: 1)
        }
        await #expect(throws: HealthKitConversionError.clinicalRecord(.undecodable)) {
            try await HealthKitRecordingFile.clinicalRecord(invalid, relativePath: "document.json", maximumByteCount: 4096)
        }
        let valid = try Self.record(Data("{\"resourceType\":\"Observation\"}".utf8))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HealthKitRecordingFile.clinicalRecord(valid, relativePath: "document.json", maximumByteCount: 4096)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func absentPayloadAndUnadmittedReleaseRemainExplicitFailures() async throws {
        let absent = try Self.record(nil)
        await #expect(throws: HealthKitConversionError.clinicalRecord(.empty)) {
            try await HealthKitRecordingFile.clinicalRecord(absent, relativePath: "document.json", maximumByteCount: 4096)
        }
        let unsupported = try Self.record(Data("{\"resourceType\":\"Observation\"}".utf8), version: "3.0.1")
        await #expect(throws: HealthKitConversionError.clinicalRecord(.unsupportedRelease)) {
            try await HealthKitRecordingFile.clinicalRecord(unsupported, relativePath: "document.json", maximumByteCount: 4096)
        }
        await #expect(throws: HealthKitRecordingFile.RecordingError.invalidRelativePath) {
            try await HealthKitRecordingFile.clinicalRecord(unsupported, relativePath: "../document.json", maximumByteCount: 4096)
        }
    }
}

#endif
