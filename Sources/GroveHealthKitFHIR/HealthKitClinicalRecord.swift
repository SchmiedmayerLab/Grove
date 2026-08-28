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
public import GroveHealthKit
public import HealthKit
public import ModelsR4


/// One attachment HealthKit stores alongside a clinical record.
///
/// The bytes are the institution's own document. They are never inlined into the record: a
/// discharge summary or imaging report is routinely larger than a resource should carry, so it
/// travels as a sidecar payload the receiving system fetches, exactly as a sensor recording does.
public struct HealthKitClinicalAttachment: Sendable {
    /// The attachment's media type as HealthKit reports it.
    public let contentType: String
    /// The attachment's exact bytes.
    public let data: Data

    public init(contentType: String, data: Data) {
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
    /// The documents HealthKit stores alongside the record, when the caller asked for them.
    public let attachments: [HealthKitClinicalAttachment]
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Reads a clinical record, and optionally the documents HealthKit stores with it.
    ///
    /// - Parameters:
    ///   - record: The clinical record to read.
    ///   - healthKit: The `HealthKit` instance used to reach the attachment store. Pass `nil` to
    ///     read the resource alone.
    /// - Returns: The record's own resource plus any attachments.
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
            do {
                attachments = try await Self.attachments(of: record, using: healthKit)
            } catch {
                throw .unreadableClinicalAttachment(record.uuid)
            }
        }
        return HealthKitClinicalRecord(
            sourceUUID: record.uuid,
            sourceData: fhirResource.data,
            resource: resource,
            attachments: attachments
        )
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
                contentType: attachment.contentType.preferredMIMEType ?? "application/octet-stream",
                data: try await store.dataReader(for: attachment).data
            ))
        }
        return loaded
    }
}

#endif

// swiftlint:enable type_contents_order
