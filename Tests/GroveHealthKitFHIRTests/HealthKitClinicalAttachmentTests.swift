//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing
import UniformTypeIdentifiers


@Suite
struct HealthKitClinicalAttachmentTests {
    private typealias ClinicalAttachment = HealthKitFHIRExporter.Record.ClinicalAttachment

    /// An attachment claims the shared Clinical Records attachment profile and HealthKit's.
    private static let attachmentProfiles = [Profile.groveClinicalRecordAttachment, HealthKitContract.clinicalAttachmentProfile]
        .compactMap { $0.value?.url.absoluteString }
    /// A clinical-record document claims the shared Clinical Records document profile and HealthKit's.
    private static let clinicalProfiles = [Profile.groveClinicalRecordDocument, HealthKitContract.clinicalRecordProfile]
        .compactMap { $0.value?.url.absoluteString }

    /// The deployment's exporter, which names a study, and its clinical record.
    private static func setUp() async throws -> (HealthKitFHIRExporter, HKClinicalRecord) {
        let exporter = try ExporterGolden.exporter(deployment: true)
        let record = try await ExporterGolden.clinicalRecord(
            uuid: 0xC1,
            version: .primaryR4(),
            payload: #"{"resourceType":"DocumentReference","id":"note","status":"current"}"#
        )
        return (exporter, record)
    }

    /// The one record `exporter` delivers for `record`, which must not be refused.
    private static func export(_ record: HealthKitFHIRExporter.Record, with exporter: HealthKitFHIRExporter) async throws -> ExportedGraph {
        let exports = try await ExporterFixtures.collect(exporter, [record])
        #expect(exports.count == 1)
        return try ExportedGraph(try #require(exports.first))
    }

    /// Every DocumentReference of `graph` by its fullUrl, in entry order.
    private static func documents(of graph: ExportedGraph) -> [(url: String, document: DocumentReference)] {
        (graph.bundle.entry ?? []).compactMap { entry in
            guard let document = entry.resource?.get(if: DocumentReference.self),
                  let url = entry.fullUrl?.value?.url.absoluteString else {
                return nil
            }
            return (url, document)
        }
    }

    private static func profiles(_ document: DocumentReference) -> [String] {
        (document.meta?.profile ?? []).compactMap { $0.value?.url.absoluteString }
    }


    @Test("A clinical record without files exports byte for byte as a bare sample")
    func recordWithoutFilesIsUnchanged() async throws {
        let (exporter, record) = try await Self.setUp()
        let bare = try await Self.export(.sample(record), with: exporter)
        let empty = try await Self.export(.clinicalRecord(record, attachments: []), with: exporter)
        #expect(empty.record.json == bare.record.json)
        #expect(Self.documents(of: empty).count == 1)
    }

    @Test("Each file is an attachment document that appends to the unchanged clinical-record document")
    func attachmentsAppendToTheClinicalDocument() async throws {
        let (exporter, record) = try await Self.setUp()
        let bare = try await Self.export(.sample(record), with: exporter)
        let graph = try await Self.export(.clinicalRecord(record, attachments: ExporterGolden.clinicalAttachments), with: exporter)

        let documents = Self.documents(of: graph)
        let clinical = try #require(documents.first { Self.profiles($0.document) == Self.clinicalProfiles })
        let attachments = documents.filter { Self.profiles($0.document) == Self.attachmentProfiles }
        #expect(attachments.count == 2)
        // The clinical-record document is the record's primary and says nothing of its files.
        #expect(clinical.document == bare.document)
        #expect(clinical.document.relatesTo == nil)
        #expect(graph.provenance.target.map { $0.reference?.value?.string } == [clinical.url] + attachments.map(\.url))

        for (_, attachment) in attachments {
            #expect(attachment.relatesTo?.count == 1)
            #expect(attachment.relatesTo?.first?.code.value == .appends)
            #expect(attachment.relatesTo?.first?.target.reference?.value?.string == clinical.url)
            #expect(attachment.relatesTo?.first?.target.type == nil)
            // The fields the guide holds equal to the clinical-record document.
            #expect(attachment.type == clinical.document.type)
            #expect(attachment.subject == clinical.document.subject)
            #expect(attachment.date == clinical.document.date)
            #expect(attachment.author == clinical.document.author)
            #expect(attachment.context?.related == clinical.document.context?.related)
            #expect(attachment.context?.related?.isEmpty == false)
            #expect(attachment.extension?.first == clinical.document.extension?.first)
            #expect(attachment.status == clinical.document.status)
        }
    }

    @Test("An attachment states its own output and its part, never the primary's writer or native identifiers")
    func attachmentIdentities() async throws {
        let (exporter, record) = try await Self.setUp()
        let graph = try await Self.export(.clinicalRecord(record, attachments: ExporterGolden.clinicalAttachments), with: exporter)
        let sourceRecord = try exporter.assembly.scope.sourceRecord(
            sourceType: HKClinicalTypeIdentifier.labResultRecord.rawValue,
            nativeRecordID: record.uuid.uuidString.lowercased()
        )
        let attachments = Self.documents(of: graph).map(\.document).filter { Self.profiles($0) == Self.attachmentProfiles }
        // The scan was created first, so it is part 0 though the caller listed it second.
        let inPartOrder = ExporterGolden.clinicalAttachments.inPartOrder
        #expect(inPartOrder.map(\.name) == ["scan", "Visit note.pdf"])
        for (attachment, expected) in zip(attachments, inPartOrder.enumerated()) {
            let identifiers = attachment.identifier ?? []
            #expect(identifiers == [
                sourceRecord.identifier.fhirIdentifier,
                try sourceRecord.output(role: "clinical-record-attachment", discriminator: expected.element.identifier.uuidString.lowercased()).fhirIdentifier,
                try sourceRecord.artifact(formatCode: "source-file", partIndex: UInt64(expected.offset)).fhirIdentifier
            ])
            #expect(attachment.extension?.contains { $0.url == Canonicals.writerRecordVersion } != true)
        }
    }

    @Test("An attachment carries its file inline or by location, with its size, hash, name, creation and media type")
    func attachmentContent() async throws {
        let (exporter, record) = try await Self.setUp()
        let graph = try await Self.export(.clinicalRecord(record, attachments: ExporterGolden.clinicalAttachments), with: exporter)
        let contents = Self.documents(of: graph)
            .map(\.document)
            .filter { Self.profiles($0) == Self.attachmentProfiles }
            .map(\.content)
        #expect(contents.allSatisfy { $0.count == 1 })
        let scan = try #require(contents.first?.first)
        let pdf = try #require(contents.last?.first)
        for content in [scan, pdf] {
            #expect(content.format?.code?.value?.string == "source-file")
            #expect(content.format?.system?.value?.url.absoluteString == RegisteredRecordingFormat.codeSystem)
            #expect(content.format?.version == nil)
        }
        // A type without a MIME type falls back to the registry's; its bytes travel inline.
        #expect(scan.attachment.contentType?.value?.string == "application/octet-stream")
        #expect(scan.attachment.data?.value?.dataString == ExporterGolden.attachedScan.base64EncodedString())
        #expect(scan.attachment.url == nil)
        #expect(scan.attachment.size?.value?.integer == Int32(ExporterGolden.attachedScan.count))
        #expect(scan.attachment.hash?.value?.dataString == ExporterGolden.attachedScan.attachmentSHA1.base64EncodedString())
        #expect(scan.attachment.title?.value?.string == "scan")
        #expect(scan.attachment.creation?.value == (try ExchangeInstant.fhirDateTime(GoldenFixtures.sampleStart)))
        // The PDF's bytes stay where the caller put them; the document names the place, their size and their hash.
        #expect(pdf.attachment.contentType?.value?.string == "application/pdf")
        #expect(pdf.attachment.data == nil)
        #expect(pdf.attachment.url?.value?.url.absoluteString == "documents/\(ExporterGolden.sha256Hex(ExporterGolden.attachedPDF)).pdf")
        #expect(pdf.attachment.size?.value?.integer == Int32(ExporterGolden.attachedPDF.count))
        #expect(pdf.attachment.hash?.value?.dataString == ExporterGolden.attachedPDF.attachmentSHA1.base64EncodedString())
        #expect(pdf.attachment.title?.value?.string == "Visit note.pdf")
    }

    @Test("An attachment's metadata travels in the HealthKit source-metadata extension on its own document")
    func attachmentMetadata() async throws {
        let (exporter, record) = try await Self.setUp()
        let graph = try await Self.export(.clinicalRecord(record, attachments: ExporterGolden.clinicalAttachments), with: exporter)
        let attachments = Self.documents(of: graph).map(\.document).filter { Self.profiles($0) == Self.attachmentProfiles }
        func metadataKeys(_ document: DocumentReference) -> [String] {
            (document.extension ?? [])
                .filter { $0.url.value?.url.absoluteString == HealthKitContract.metadataExtensionURL }
                .flatMap { $0.extension ?? [] }
                .compactMap { entry in
                    entry.extension?.first { $0.url.value?.url.absoluteString == "key" }.flatMap { key in
                        guard case .string(let text)? = key.value else {
                            return nil
                        }
                        return text.value?.string
                    }
                }
        }
        #expect(metadataKeys(attachments[0]).isEmpty)
        #expect(metadataKeys(attachments[1]) == ["PageCount", "ProviderDocumentID"])
        #expect(!graph.warnings.contains { $0.location == "HKAttachment.metadata" })
    }

    @Test("An attachment withholds the sync pair its metadata states, under every metadata policy")
    func attachmentSyncMetadataIsWithheld() async throws {
        let policies: [HealthKitFHIRExporter.MetadataPolicy] = [
            .all, .omit, .custom { $0 == HKMetadataKeySyncIdentifier ? .omit : .include }
        ]
        for policy in policies {
            var inputs = ExportInputs()
            inputs.converter = ExporterGolden.deploymentApplication
            inputs.studies = ExporterGolden.deploymentStudies
            inputs.options = ExporterGolden.deploymentOptions
            inputs.options.syncIdentifier = .omit
            inputs.options.metadata = policy
            let exporter = try ExporterFixtures.exporter(inputs)
            let (_, record) = try await Self.setUp()
            let attachment = ClinicalAttachment(
                identifier: GoldenFixtures.uuid(0xC3),
                name: "note.pdf",
                contentType: .pdf,
                creationDate: GoldenFixtures.sampleStart,
                metadata: [HKMetadataKeySyncIdentifier: "writer-record-7", HKMetadataKeySyncVersion: NSNumber(value: 2), "Pages": "3"],
                payload: .inline(Data("%PDF".utf8))
            )
            let graph = try await Self.export(.clinicalRecord(record, attachments: [attachment]), with: exporter)
            let json = String(decoding: graph.record.json, as: UTF8.self)
            #expect(!json.contains("writer-record-7"))
            #expect(!json.contains(HKMetadataKeySyncIdentifier))
            #expect(!json.contains(HKMetadataKeySyncVersion))
            #expect(graph.warnings.contains { $0.location == "HKAttachment.metadata" })
        }
    }

    @Test("Validation refuses the native identifier on an attachment, even when the clinical document carries none")
    func nativeIdentifierOnAttachmentIsRefused() async throws {
        let (exporter, record) = try await Self.setUp()
        let graph = try await Self.export(.clinicalRecord(record, attachments: ExporterGolden.clinicalAttachments), with: exporter)
        var bundle = graph.bundle
        var entries = try #require(bundle.entry)
        func document(at index: Int) -> DocumentReference? {
            entries[index].resource?.get(if: DocumentReference.self)
        }
        let clinicalIndex = try #require(entries.indices.first { document(at: $0).map(Self.profiles) == Self.clinicalProfiles })
        let attachmentIndex = try #require(entries.indices.first { document(at: $0).map(Self.profiles) == Self.attachmentProfiles })
        var clinical = try #require(document(at: clinicalIndex))
        var attachment = try #require(document(at: attachmentIndex))
        // The deployment discloses the HealthKit UUID: the one identifier without a Grove role coding.
        let native = try #require(clinical.identifier?.first { $0.type == nil })
        clinical.identifier?.removeAll { $0 == native }
        attachment.identifier?.append(native)
        entries[clinicalIndex].resource = ResourceProxy(with: clinical)
        entries[attachmentIndex].resource = ResourceProxy(with: attachment)
        bundle.entry = entries
        #expect(throws: ExchangeGraphError.ruleViolation(.sensorRecordingDocumentIdentityAndContent)) {
            _ = try ExchangeGraph(kind: .active, bundle: bundle)
        }
    }

    @Test("A file R4 cannot size, or a sidecar without a SHA-1 digest, refuses the record")
    func malformedAttachmentsAreRefused() async throws {
        let (exporter, record) = try await Self.setUp()
        func refusal(_ payload: ClinicalAttachment.Payload) async throws -> HealthKitConversionError? {
            let attachment = ClinicalAttachment(
                identifier: GoldenFixtures.uuid(0xC2),
                name: "file",
                contentType: .pdf,
                creationDate: GoldenFixtures.sampleStart,
                payload: payload
            )
            let exports = try await ExporterFixtures.collect(exporter, [.clinicalRecord(record, attachments: [attachment])])
            guard case .refused(let error)? = exports.first?.outcome else {
                return nil
            }
            return error
        }
        let tooLarge = try await refusal(.sidecar(path: "documents/large.pdf", byteCount: Int(Int32.max) + 1, sha1: Data(count: 20)))
        #expect(tooLarge?.diagnostic.code == ExchangeGraphRule.mobileInputRecordingPayloadTooLarge.rawValue)
        #expect(try await refusal(.sidecar(path: "documents/file.pdf", byteCount: 4, sha1: Data(count: 19))) != nil)
        #expect(try await refusal(.sidecar(path: "", byteCount: 4, sha1: Data(count: 20))) != nil)
        #expect(try await refusal(.sidecar(path: "documents/file.pdf", byteCount: 4, sha1: Data(count: 20))) == nil)
    }

    @Test("Two files of one record with the same identifier cannot both be outputs")
    func duplicateAttachmentIdentifiersAreRefused() async throws {
        let (exporter, record) = try await Self.setUp()
        let attachment = ExporterGolden.clinicalAttachments[0]
        let exports = try await ExporterFixtures.collect(exporter, [.clinicalRecord(record, attachments: [attachment, attachment])])
        guard case .refused? = exports.first?.outcome else {
            Issue.record("A record whose two attachments share an identifier was exported")
            return
        }
    }

    @Test("The registry's source-declared media type admits a declared type in lowercase, else its fallback")
    func sourceDeclaredContentType() throws {
        let format = RegisteredRecordingFormat.sourceFile
        #expect(format.registeredContentTypes.isEmpty)
        #expect(format.sourceDeclaredContentType?.fallback == "application/octet-stream")
        #expect(format.statedContentType(declared: "application/PDF") == "application/pdf")
        #expect(format.statedContentType(declared: nil) == "application/octet-stream")
        #expect(format.statedContentType(declared: "not a media type") == "application/octet-stream")
        #expect(format.admitsContentType("image/jpeg"))
        #expect(format.admitsContentType("text/plain; charset=utf-8"))
        #expect(!format.admitsContentType("Image/JPEG"))
        #expect(!format.admitsContentType("text"))
        #expect(RegisteredRecordingFormat.providerIssuedFHIRJSON.sourceDeclaredContentType == nil)
        #expect(RegisteredRecordingFormat.providerIssuedFHIRJSON.statedContentType(declared: "application/pdf") == nil)
        // A provider-issued FHIR payload admits any release its producer declares, and nothing without one.
        let fhir = RegisteredRecordingFormat.providerIssuedFHIRJSON
        #expect(fhir.registeredContentTypes.isEmpty)
        #expect(fhir.admitsContentType("application/fhir+json; fhirVersion=1.0"))
        #expect(fhir.admitsContentType("application/fhir+json; fhirVersion=4.0"))
        #expect(fhir.admitsContentType("application/fhir+json; fhirVersion=5.0"))
        #expect(!fhir.admitsContentType("application/fhir+json"))
        #expect(!fhir.admitsContentType("application/fhir+json; fhirVersion=4"))
        #expect(RegisteredRecordingFormat.beatIntervalSeries.statedContentType(declared: "application/pdf") == "text/csv")
    }
}

#endif
