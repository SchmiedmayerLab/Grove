//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Members are ordered to read as a narrative rather than by kind.
// swiftlint:disable type_contents_order

#if canImport(HealthKit) && !os(watchOS)

public import Foundation
internal import GroveFHIRContract
public import GroveFoundation
public import GroveHealthKit
public import HealthKit
public import ModelsR4


/// One attachment HealthKit stores alongside a clinical record.
///
/// This value is not part of the Grove clinical-record exchange graph. The graph carries only the
/// provider-issued FHIR resource from `HKClinicalRecord.fhirResource`; a caller that reads these
/// separately stored documents must govern and exchange them through its own explicit contract.
public struct HealthKitClinicalAttachment: Sendable {
    /// The attachment's media type as HealthKit reports it.
    public let contentType: MIMEType
    /// The attachment's exact bytes.
    public let data: Data

    public init(contentType: MIMEType, data: Data) {
        self.contentType = contentType
        self.data = data
    }
}


/// A byte-preserved R4 clinical record read from HealthKit.
///
/// This is not a conversion. A clinical record already *is* FHIR — an institution's own resource,
/// delivered through HealthKit — so Grove reads and identifies it rather than re-modelling it.
/// The adapter catalog records these source types as platform-exclusive for that reason.
public struct HealthKitClinicalRecord: Sendable {
    /// The HealthKit object the record was read from.
    public let sourceUUID: UUID
    /// The exact bytes HealthKit returned. These bytes, not a re-encoded model, are the payload
    /// carried in the exchange graph and covered by `Attachment.hash` and `Attachment.size`.
    public let sourceData: Data
    /// A decoded view for clients that need to inspect the provider-issued resource. Grove never
    /// serializes this value back into the carried payload.
    public let resource: any ModelsR4.Resource
    /// Documents HealthKit stores alongside the record, returned for caller-managed use outside
    /// the Grove clinical-record exchange graph.
    public let attachments: [HealthKitClinicalAttachment]
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Decodes an R4 clinical record for inspection, and optionally reads its associated documents.
    ///
    /// This typed inspection API rejects DSTU2. Transport does not require decoding: use
    /// `convert(_:context:)` to carry either admitted release unchanged, and
    /// `readAttachments(of:using:)` to load its associated documents for caller-managed use outside
    /// the Grove clinical-record exchange graph.
    ///
    /// - Parameters:
    ///   - record: The clinical record to read.
    ///   - healthKit: The `HealthKit` instance used to reach the attachment store. Pass `nil` to
    ///     read the resource alone.
    /// - Returns: The record's own resource plus any separately managed HealthKit attachments.
    public func read(
        _ record: HKClinicalRecord,
        using healthKit: HealthKit? = nil
    ) async throws(HealthKitConversionError) -> HealthKitClinicalRecord {
        guard let fhirResource = record.fhirResource else {
            throw .clinicalRecordWithoutResource(record.uuid)
        }
        let resource = try Self.decodeR4ClinicalResource(
            data: fhirResource.data,
            release: fhirResource.fhirVersion.fhirRelease,
            versionDescription: fhirResource.fhirVersion.stringRepresentation,
            sourceUUID: record.uuid
        )
        var attachments: [HealthKitClinicalAttachment] = []
        if let healthKit {
            attachments = try await readAttachments(of: record, using: healthKit)
        }
        return HealthKitClinicalRecord(
            sourceUUID: record.uuid,
            sourceData: fhirResource.data,
            resource: resource,
            attachments: attachments
        )
    }

    /// Reads provider documents HealthKit stores alongside a clinical record.
    ///
    /// This operation is independent of the record's FHIR release. Its results are not referenced
    /// by the Grove clinical-record Bundle; a caller must not present them as part of that exchange
    /// without a separate document identity, integrity, and retrieval contract.
    public func readAttachments(
        of record: HKClinicalRecord,
        using healthKit: HealthKit
    ) async throws(HealthKitConversionError) -> [HealthKitClinicalAttachment] {
        do {
            return try await Self.attachments(of: record, using: healthKit)
        } catch {
            throw .unreadableClinicalAttachment(record.uuid)
        }
    }

    /// Fails before decoding unless HealthKit explicitly declares R4. Keeping this gate separate
    /// makes the DSTU2 rejection testable without constructing Apple's read-only HKFHIRResource.
    static func decodeR4ClinicalResource(
        data: Data,
        release: HKFHIRRelease,
        versionDescription: String,
        sourceUUID: UUID
    ) throws(HealthKitConversionError) -> any ModelsR4.Resource {
        guard release == .r4 else {
            throw .unsupportedClinicalRelease(versionDescription)
        }
        do {
            return try JSONDecoder().decode(ModelsR4.ResourceProxy.self, from: data).get()
        } catch {
            throw .undecodableClinicalRecord(sourceUUID)
        }
    }

    private static func attachments(
        of record: HKClinicalRecord,
        using healthKit: HealthKit
    ) async throws -> [HealthKitClinicalAttachment] {
        // Read sequentially: a record carries a handful of documents at most, and `HKAttachmentStore`
        // is not sendable, so a task group would buy nothing and cost a store per task.
        let store = HKAttachmentStore(healthStore: healthKit.healthStore)
        var loaded: [HealthKitClinicalAttachment] = []
        for attachment in try await store.attachments(for: record) {
            loaded.append(HealthKitClinicalAttachment(
                contentType: MIMEType(attachment.contentType) ?? .octetStream,
                data: try await store.dataReader(for: attachment).data
            ))
        }
        return loaded
    }
}

#endif

// swiftlint:enable type_contents_order
