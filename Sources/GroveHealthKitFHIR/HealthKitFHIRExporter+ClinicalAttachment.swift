//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import HealthKit
public import UniformTypeIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Record {
    /// One file HealthKit stores with a clinical record, such as a clinical note's PDF, as `HKAttachmentStore` lists it.
    ///
    /// Each becomes a HealthKit Clinical Record Attachment document beside the record's clinical-record document, which it
    /// appends to. The exporter never reads HealthKit, so the caller reads the file and passes its bytes, or the location
    /// it put them at, as the ``payload``. Every file of a record is carried; none is skipped for its size.
    public struct ClinicalAttachment: Sendable {
        /// Where the attachment document finds the file's exact bytes.
        public enum Payload: Hashable, Sendable {
            /// The bytes themselves, embedded in the document.
            case inline(Data)
            /// An immutable, version-specific location of the bytes that the deployment resolves, such as the path of an
            /// entry in the archive that carries the Bundle, with the bytes' count and their SHA-1 digest. Grove never
            /// reads the location.
            case sidecar(path: String, byteCount: Int, sha1: Data)
        }

        /// `HKAttachment.identifier`, which names the attachment's own output.
        public let identifier: UUID
        /// `HKAttachment.name`, stated as the attachment's title.
        public let name: String
        /// `HKAttachment.contentType`, whose preferred MIME type the document states.
        public let contentType: UTType
        /// `HKAttachment.creationDate`, stated as the attachment's creation; it also orders the record's attachments.
        public let creationDate: Date
        /// `HKAttachment.metadata`, whose `String`, `NSNumber` and `Date` values HealthKit admits; carried in the HealthKit
        /// source-metadata extension under the rules of sample metadata.
        public let metadata: [String: any Sendable]
        /// The file's bytes, or where they are.
        public let payload: Payload

        public init(
            identifier: UUID,
            name: String,
            contentType: UTType,
            creationDate: Date,
            metadata: [String: any Sendable] = [:],
            payload: Payload
        ) {
            self.identifier = identifier
            self.name = name
            self.contentType = contentType
            self.creationDate = creationDate
            self.metadata = metadata
            self.payload = payload
        }

        /// The attachment HealthKit lists as `attachment`, carried as `payload`.
        ///
        /// Metadata values of a class HealthKit does not admit are left out, as a sample's are.
        public init(_ attachment: HKAttachment, payload: Payload) {
            self.init(
                identifier: attachment.identifier,
                name: attachment.name,
                contentType: attachment.contentType,
                creationDate: attachment.creationDate,
                metadata: Self.sendableMetadata(attachment.metadata ?? [:]),
                payload: payload
            )
        }

        /// The values of `metadata` of the classes `HKAttachment` admits.
        static func sendableMetadata(_ metadata: [String: Any]) -> [String: any Sendable] {
            metadata.compactMapValues { value -> (any Sendable)? in
                switch value {
                case let text as String: text
                case let number as NSNumber: number
                case let date as Date: date
                default: nil
                }
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Record.ClinicalAttachment.Payload {
    /// The number of the file's bytes.
    var byteCount: Int {
        switch self {
        case .inline(let data): data.count
        case .sidecar(_, let byteCount, _): byteCount
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Array where Element == HealthKitFHIRExporter.Record.ClinicalAttachment {
    /// The attachments in the order their part index follows: by creation date, then by the lowercase text of their
    /// identifier, so the order never depends on the order the caller listed them in.
    var inPartOrder: [Element] {
        sorted { lhs, rhs in
            if lhs.creationDate != rhs.creationDate {
                return lhs.creationDate < rhs.creationDate
            }
            return lhs.identifier.uuidString.lowercased() < rhs.identifier.uuidString.lowercased()
        }
    }
}

#endif
