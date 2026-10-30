//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import HealthKit


/// CDA documents and clinical records. The vectors are data on every platform; watchOS, which has neither,
/// skips them when it rebuilds the records.
extension ContentCorpusGrid {
    /// A provider's R4 resource, carried byte for byte.
    static let clinicalResource = #"{"resourceType":"Observation","id":"r4"}"#

    /// CDA documents and clinical records: every type and admitted release, refused releases and payloads,
    /// missing payloads, bytes kept as delivered, and every link.
    static var clinicalDocuments: [ContentCorpusVector] {
        cdaDocuments + clinicalRecords
    }

    /// The goldens' CDA document, then a blank and a padded title, an empty document and none at all, and every link.
    static var cdaDocuments: [ContentCorpusVector] {
        func document(_ label: String, title: String, document: String?) -> ContentCorpusVector {
            convert("cda/\(label)", ContentCorpusSource(.cdaDocument(title: title, document: document), end: start + 1))
        }
        let xml = GoldenCase.clinicalDocumentXML
        var linked = ContentCorpusSource(.cdaDocument(title: "Grove Golden Summary", document: xml), end: start + 1)
        linked.device = .watch
        linked.context = .linked
        linked.metadata[HKMetadataKeyWasUserEntered] = .boolean(true)
        return [
            document("row", title: "Grove Golden Summary", document: xml),
            document("blank-title", title: "  ", document: xml),
            document("padded-title", title: "  Summary\n", document: xml),
            document("empty-document", title: "Grove Golden Summary", document: ""),
            document("no-document", title: "Grove Golden Summary", document: nil),
            convert("cda/linked", linked)
        ]
    }

    /// Every clinical type in R4, then DSTU2, an unknown release, payloads the guides refuse, a missing resource,
    /// bytes kept with their whitespace, every link, and which refusal comes first, the record's source facts last.
    static var clinicalRecords: [ContentCorpusVector] {
        let labResult = "HKClinicalTypeIdentifierLabResultRecord"
        func record(
            _ label: String,
            type: String = labResult,
            version: String = "4.0.1",
            resource: String? = clinicalResource,
            metadata: [String: ContentCorpusMetadataValue] = zone
        ) -> ContentCorpusVector {
            convert("clinical/\(label)", ContentCorpusSource(.clinicalRecord(type: type, fhirVersion: version, resource: resource), end: start, metadata: metadata))
        }
        let types = rows(prefix: "HKClinicalTypeIdentifier").map { record("type/\($0.sourceTypeIdentifier)", type: $0.sourceTypeIdentifier) }
        var linked = ContentCorpusSource(.clinicalRecord(type: labResult, fhirVersion: "4.0.1", resource: clinicalResource))
        linked.device = .watch
        linked.context = .linked
        linked.metadata[HKMetadataKeyWasUserEntered] = .boolean(true)
        let duplicateMember = #"{"resourceType":"Observation","resourceType":"Patient"}"#
        return types + [
            record("dstu2", version: "1.0.2", resource: #"{"resourceType":"Observation","id":"dstu2"}"#),
            record("unknown-release", version: "3.0.1"),
            record("undecodable/duplicate-member", resource: duplicateMember),
            record("undecodable/lowercase-type", resource: #"{"resourceType":"observation"}"#),
            // The payload starts with a byte order mark (U+FEFF), which the corpus prints escaped.
            record("undecodable/byte-order-mark", resource: "\u{FEFF}" + clinicalResource),
            record("undecodable/array", resource: "[]"),
            record("no-resource", resource: nil),
            record("whitespace-kept", resource: "  {\n  \"resourceType\": \"Observation\", \"id\": \"r4\"\n}\n"),
            convert("clinical/linked", linked),
            record("precedence/release-before-payload", version: "3.0.1", resource: duplicateMember),
            record("precedence/empty-before-release", version: "3.0.1", resource: nil),
            record("precedence/payload-before-sync", resource: duplicateMember, metadata: brokenSync)
        ]
    }
}

#endif
