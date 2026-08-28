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
public import ModelsDSTU2
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


/// A clinical record read from HealthKit, in the FHIR release the institution authored it in.
///
/// This is not a conversion. A clinical record already *is* FHIR — an institution's own resource,
/// delivered through HealthKit — so Grove reads and identifies it rather than re-modelling it.
/// The adapter catalog records these source types as platform-exclusive for that reason.
public struct HealthKitClinicalRecord: Sendable {
    /// The record's payload, in the release it was authored in.
    public enum Payload: Sendable {
        case r4(any ModelsR4.Resource) // swiftlint:disable:this identifier_name
        case dstu2(any ModelsDSTU2.Resource)
    }

    /// The HealthKit object the record was read from.
    public let sourceUUID: UUID
    /// The record's own FHIR resource.
    public let payload: Payload
    /// The documents HealthKit stores alongside the record, when the caller asked for them.
    public let attachments: [HealthKitClinicalAttachment]

    /// The `(system, value)` pair identifying the HealthKit object this record was read from.
    public var sourceIdentifier: ModelsR4.Identifier {
        ModelsR4.Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: Canonicals.healthKitObjectIdentifierSystem)),
            value: FHIRPrimitive(FHIRString(stringLiteral: sourceUUID.uuidString.lowercased()))
        )
    }
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
        let payload: HealthKitClinicalRecord.Payload
        do {
            let decoder = JSONDecoder()
            switch fhirResource.fhirVersion.fhirRelease {
            case .dstu2:
                payload = .dstu2(try decoder.decode(ModelsDSTU2.ResourceProxy.self, from: fhirResource.data).get())
            case .r4:
                payload = .r4(try decoder.decode(ModelsR4.ResourceProxy.self, from: fhirResource.data).get())
            default:
                throw HealthKitConversionError.unsupportedClinicalRelease(fhirResource.fhirVersion.stringRepresentation)
            }
        } catch let error as HealthKitConversionError {
            throw error
        } catch {
            throw .undecodableClinicalRecord(record.uuid)
        }
        var attachments: [HealthKitClinicalAttachment] = []
        if let healthKit {
            do {
                attachments = try await Self.attachments(of: record, using: healthKit)
            } catch {
                throw .unreadableClinicalAttachment(record.uuid)
            }
        }
        return HealthKitClinicalRecord(sourceUUID: record.uuid, payload: payload, attachments: attachments)
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
