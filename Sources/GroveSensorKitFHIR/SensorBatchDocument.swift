//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SensorKit)

import CryptoKit
import FHIRModelsExtensions
public import Foundation
public import ModelsR4
public import SensorKit


/// A raw sensor batch — a PPG waveform, an accelerometer run, the per-app detail behind
/// a device-usage summary — packaged as the `DocumentReference` consumers resolve.
///
/// The bytes either travel inside the resource or as a sidecar file in the upload
/// archive, addressed by the same relative path the archive entry uses. Either way the
/// attachment carries the media type, the SHA-1 hash and the byte count, so a consumer
/// can verify what it received. Summary Observations point back at the document through
/// `derivedFrom` — see ``SensorKitObservationConvertible/observation(identifierKey:subject:device:derivedFrom:issued:)``.
@available(iOS 18, *)
public struct SensorBatchDocument: Sendable {
    /// Where a batch's bytes travel.
    public enum Payload: Sendable {
        /// Inside the resource, base64-encoded. Suitable only for small batches.
        case inline(Data)
        /// As a file in the upload archive, at the path
        /// ``SensorBatchArchive/addFile(path:data:)`` was given.
        case sidecar(path: String, bytes: Data)
    }

    /// An error occurring while building a batch document.
    public enum DocumentError: Error {
        /// The sidecar path is not a usable relative URL.
        case invalidPayloadPath(String)
        /// The payload exceeds what an R4 `unsignedInt` can express.
        case payloadTooLarge(byteCount: Int)
    }

    private static let profile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/core/StructureDefinition/grove-sensor-batch-document"

    /// The sensor stream the batch came from; becomes `DocumentReference.type`.
    public let sensor: SRSensor
    /// The payload's real media type, e.g. `text/csv` or `application/fhir+ndjson`.
    public let contentType: String
    /// The bytes and how they travel.
    public let payload: Payload
    /// Names the payload's schema or compression beyond its media type.
    public let format: Coding?

    private var bytes: Data {
        switch payload {
        case let .inline(bytes), let .sidecar(_, bytes):
            bytes
        }
    }

    public init(sensor: SRSensor, contentType: String, payload: Payload, format: Coding? = nil) {
        self.sensor = sensor
        self.contentType = contentType
        self.payload = payload
        self.format = format
    }

    /// The batch's content-derived identity, keyed like every other SensorKit record.
    public func identifier(key: SensorKitIdentifierKey) -> Identifier {
        var hasher = SensorKitSampleIDHasher(key: key)
        hasher.combine(sensor.rawValue)
        hasher.combine(contentType)
        hasher.combine(Data(SHA256.hash(data: bytes)).base64EncodedString())
        return Identifier(
            system: GroveSensorKitVocabulary.sampleId,
            value: hasher.finalize().uuidString.asFHIRStringPrimitive()
        )
    }

    /// The reference a summary Observation carries in `derivedFrom`.
    ///
    /// Both a literal and a logical reference: an upload that has not been through a
    /// server yet has no server-assigned id, so the identifier is what actually resolves.
    public func reference(key: SensorKitIdentifierKey) -> Reference {
        let identifier = identifier(key: key)
        return Reference(
            identifier: identifier,
            reference: "DocumentReference/\(identifier.value?.value?.string ?? "")".asFHIRStringPrimitive(),
            type: "DocumentReference"
        )
    }

    /// Builds the `DocumentReference` conforming to the Grove Sensor Batch Document profile.
    public func documentReference(key: SensorKitIdentifierKey, subject: Reference, date: Date = Date()) throws -> DocumentReference {
        let identifier = identifier(key: key)
        var document = DocumentReference(
            content: [DocumentReferenceContent(attachment: try attachment(), format: format)],
            status: FHIRPrimitive(.current)
        )
        document.id = identifier.value
        document.meta = Meta(profile: [Self.profile])
        document.masterIdentifier = identifier
        document.type = CodeableConcept(coding: [
            Coding(
            code: sensor.rawValue.asFHIRStringPrimitive(),
            system: GroveSensorKitVocabulary.sampleType
        )
        ])
        document.subject = subject
        document.date = FHIRPrimitive(try Instant(date: date))
        return document
    }

    private func attachment() throws -> Attachment {
        guard let size = Int32(exactly: bytes.count) else {
            throw DocumentError.payloadTooLarge(byteCount: bytes.count)
        }
        var attachment = Attachment()
        attachment.contentType = contentType.asFHIRStringPrimitive()
        // R4 defines Attachment.hash as the base64-encoded SHA-1 of the payload.
        attachment.hash = FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: bytes))))
        attachment.size = FHIRPrimitive(FHIRUnsignedInteger(size))
        switch payload {
        case let .inline(bytes):
            attachment.data = FHIRPrimitive(Base64Binary(with: bytes))
        case let .sidecar(path, _):
            guard let url = URL(string: path) else {
                throw DocumentError.invalidPayloadPath(path)
            }
            attachment.url = FHIRPrimitive(FHIRURI(url))
        }
        return attachment
    }
}

#endif
