//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIR
import GroveHealthKit
import HealthKit
import ModelsDSTU2
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKSample {
    /// An attachment that was loaded from the health store
    struct LoadedAttachment: Sendable {
        let id: UUID
        let contentType: UTType
        let data: Data
    }
    
    fileprivate func loadAttachments(using healthKit: HealthKit) async throws -> [LoadedAttachment] {
        try await withThrowingTaskGroup/*(of: LoadedAttachment.self, returning: [LoadedAttachment].self)*/ { taskGroup in
            let store = HKAttachmentStore(healthStore: healthKit.healthStore)
            for attachment in try await store.attachments(for: self) {
                taskGroup.addTask {
                    let dataReader = store.dataReader(for: attachment)
                    return LoadedAttachment(
                        id: attachment.identifier,
                        contentType: attachment.contentType,
                        data: try await dataReader.data
                    )
                }
            }
            var results: [LoadedAttachment] = []
            while let result = try await taskGroup.next() {
                results.append(result)
            }
            return results
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRResource {
    /// Loads attachments for the FHIR resource from a HealthKit sample.
    /// - Parameters:
    ///   - healthKitSample: The HealthKit sample containing attachments.
    ///   - store: The health store to use. Defaults to a new `HKHealthStore` instance.
    mutating func loadAttachments(from sample: HKSample, using healthKit: HealthKit) async throws { // swiftlint:disable:this type_contents_order
        guard category == .document || category == .diagnostic else {
            return
        }
        let attachments = try await sample.loadAttachments(using: healthKit)
        // We inject the data right in the resource if it has the same content type.
        // We assume that the content type is a MIME type, we would need to more checks around the content.format to be fully correct.
        // Otherwise we create a new content entry to inject this information in here.
        switch versionedResource {
        case .r4(var resource):
            try Self.process(attachments, into: &resource)
            self = .init(versionedResource: .r4(resource), displayName: self.displayName)
        case .dstu2(var resource):
            try Self.process(attachments, into: &resource)
            self = .init(versionedResource: .dstu2(resource), displayName: self.displayName)
        }
    }
    
    /// Adds attachments into the resource
    static func process(_ attachments: [HKSample.LoadedAttachment], into resource: inout any ModelsR4.Resource) throws {
        switch resource {
        case var reference as ModelsR4.DocumentReference:
            for attachment in attachments {
                let b64Binary = FHIRPrimitive(ModelsR4.Base64Binary(attachment.data.base64EncodedString()))
                let attachmentContentType: ModelsR4.FHIRPrimitive = (attachment.contentType.preferredMIMEType ?? attachment.contentType.identifier)
                    .asFHIRStringPrimitive()
                if let matchingContentIdx = reference.content.firstIndex(where: {
                    $0.attachment.contentType == attachmentContentType && $0.attachment.data == nil
                }) {
                    reference.content[matchingContentIdx].attachment.data = b64Binary
                } else {
                    reference.content.append(DocumentReferenceContent(attachment: Attachment(contentType: attachmentContentType, data: b64Binary)))
                }
                resource = reference
            }
        case var report as ModelsR4.DiagnosticReport:
            for attachment in attachments {
                let b64Binary = FHIRPrimitive(ModelsR4.Base64Binary(attachment.data.base64EncodedString()))
                let attachmentContentType: ModelsR4.FHIRPrimitive = (attachment.contentType.preferredMIMEType ?? attachment.contentType.identifier)
                    .asFHIRStringPrimitive()
                if let matchingAttachmentIdx = (report.presentedForm ?? []).firstIndex(where: {
                    $0.contentType == attachmentContentType && $0.data == nil
                }) {
                    // SAFETY: if there is an index, we know that the array is not nil.
                    // swiftlint:disable:next force_unwrapping
                    report.presentedForm![matchingAttachmentIdx].data = b64Binary
                } else {
                    if report.presentedForm == nil {
                        report.presentedForm = []
                    }
                    // swiftlint:disable:next force_unwrapping
                    report.presentedForm!.append(Attachment(contentType: attachmentContentType, data: b64Binary))
                }
                resource = report
            }
        default:
            throw GroveHealthKitFHIRError.invalidFHIRResource
        }
    }

    static func process(_ attachments: [HKSample.LoadedAttachment], into resource: inout any ModelsDSTU2.Resource) throws {
        switch resource {
        case var reference as ModelsDSTU2.DocumentReference:
            for attachment in attachments {
                let b64Binary = FHIRPrimitive(ModelsDSTU2.Base64Binary(attachment.data.base64EncodedString()))
                let attachmentContentType: ModelsDSTU2.FHIRPrimitive = (attachment.contentType.preferredMIMEType ?? attachment.contentType.identifier)
                    .asFHIRStringPrimitive()
                if let matchingContentIdx = reference.content.firstIndex(where: {
                    $0.attachment.contentType == attachmentContentType && $0.attachment.data == nil
                }) {
                    reference.content[matchingContentIdx].attachment.data = b64Binary
                } else {
                    reference.content.append(DocumentReferenceContent(attachment: Attachment(contentType: attachmentContentType, data: b64Binary)))
                }
                resource = reference
            }
        case var report as ModelsDSTU2.DiagnosticReport:
            for attachment in attachments {
                let b64Binary = FHIRPrimitive(ModelsDSTU2.Base64Binary(attachment.data.base64EncodedString()))
                let attachmentContentType: ModelsDSTU2.FHIRPrimitive = (attachment.contentType.preferredMIMEType ?? attachment.contentType.identifier)
                    .asFHIRStringPrimitive()
                if let matchingAttachmentIdx = (report.presentedForm ?? []).firstIndex(where: {
                    $0.contentType == attachmentContentType && $0.data == nil
                }) {
                    // SAFETY: if there is an index, we know that the array is not nil.
                    // swiftlint:disable:next force_unwrapping
                    report.presentedForm![matchingAttachmentIdx].data = b64Binary
                } else {
                    if report.presentedForm == nil {
                        report.presentedForm = []
                    }
                    // swiftlint:disable:next force_unwrapping
                    report.presentedForm!.append(Attachment(contentType: attachmentContentType, data: b64Binary))
                }
                resource = report
            }
        default:
            throw GroveHealthKitFHIRError.invalidFHIRResource
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKAttachmentStore: @retroactive @unchecked Sendable {}

#endif
