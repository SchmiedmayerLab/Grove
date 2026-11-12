//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


extension ExchangeGraph {
    private struct LiteralReference {
        let value: String
        let declaredType: String?
    }

    private static let allowedEntryKeyRoles: Set<GroveIdentifierRole> = [
        .sourceOutput, .sourceArtifact, .sourceRecord, .writerRecord, .recordingDevice, .deviceSnapshot, .contextSnapshot,
        .recordVersion, .recordRetraction
    ]

    private static let identifierPriority: [GroveIdentifierRole] = [
        .sourceOutput, .sourceArtifact, .sourceRecord, .writerRecord, .deviceSnapshot, .contextSnapshot, .recordingDevice
    ]

    static func diagnostic(_ rule: ExchangeGraphRule, location: String) -> ExchangeGraphError {
        .contractViolation(ProducerDiagnostic(code: rule.rawValue, reason: rule.reason, location: location))
    }

    /// Every Grove-typed resource Identifier carries one closed role, a canonical value, and a role no
    /// other Identifier of the resource repeats.
    static func validateResourceIdentifiers(
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        for (entryIndex, entry) in entries.enumerated() {
            guard let resource = entry.resource else {
                continue
            }
            let decodedIdentifiers: [Result<Identifier, any Error>]
            do {
                decodedIdentifiers = try document.resourceIdentifiers(at: entryIndex)
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            var roles: Set<GroveIdentifierRole> = []
            for (index, decoded) in decodedIdentifiers.enumerated() {
                let location = "\(resource.resourceType).identifier[\(index)]"
                let identifier: Identifier
                do {
                    identifier = try decoded.get()
                } catch {
                    throw .invalidEntries(String(reflecting: type(of: error)))
                }
                let roleCodings = identifier.type?.coding?.filter {
                    $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
                } ?? []
                guard !roleCodings.isEmpty else {
                    continue
                }
                let roled: RoledIdentifier
                do {
                    roled = try RoledIdentifier(identifier)
                } catch .duplicateIdentifierRole, .invalidIdentifierRole {
                    throw diagnostic(.mobileExchangeIdentifierRole, location: location)
                } catch {
                    throw diagnostic(.mobileExchangeOpaqueResourceIdentity, location: location)
                }
                guard roled.role != .recordVersion, roled.role != .recordRetraction,
                      ExchangeIdentity.isCanonicalOpaqueIdentifierValue(roled.identifier.value) else {
                    throw diagnostic(.mobileExchangeOpaqueResourceIdentity, location: location)
                }
                guard roles.insert(roled.role).inserted else {
                    throw diagnostic(.mobileExchangeDistinctResourceIdentityRole, location: location)
                }
            }
        }
    }

    /// Every entry carries one complete key, no two entries share a key, and each fullUrl is the key's UUIDv5.
    ///
    /// The key is its resource's highest-priority typed identifier; a Provenance and a QuestionnaireResponse, which carry
    /// no typed identifier for it, are keyed by a role of their own. Keys derived from content are checked for shape only.
    static func validateEntryKeys(kind: Kind, entries: [BundleEntry], document: ValidationDocument) throws(ExchangeGraphError) {
        var keys: Set<BusinessIdentifier> = []
        var resourceTypesByFullURL: [String: String] = [:]
        for (index, entry) in entries.enumerated() {
            let key = try entryKey(in: entry, index: index, kind: kind, document: document)
            guard keys.insert(key.identifier).inserted else {
                throw diagnostic(.mobileExchangeDistinctEntryKey, location: entryKeyLocation(index))
            }
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString,
                  resourceTypesByFullURL.updateValue(entry.resource?.resourceType ?? "", forKey: fullURL) == nil,
                  fullURL == (try? key.identifier.fullURLString) else {
                throw .ruleViolation(.mobileExchangeDeterministicFullUrl)
            }
        }
        try validateLiteralReferences(in: entries, document: document, resourceTypesByFullURL: resourceTypesByFullURL)
    }

    private static func entryKey(
        in entry: BundleEntry,
        index: Int,
        kind: Kind,
        document: ValidationDocument
    ) throws(ExchangeGraphError) -> RoledIdentifier {
        guard let resource = entry.resource else {
            throw .invalidEntries("Bundle entry has no resource")
        }
        guard let key = document.entryKey(at: index),
              allowedEntryKeyRoles.contains(key.role) else {
            throw .ruleViolation(.mobileExchangeEntryKey)
        }
        switch resource {
        case .provenance:
            try validateProvenanceKey(key, index: index, kind: kind, document: document)
        case .questionnaireResponse:
            try validateQuestionnaireResponseKey(key, index: index, document: document)
        default:
            try validateTypedKey(key, resourceType: resource.resourceType, index: index, document: document)
        }
        return key
    }

    /// A Provenance has no `identifier` in R4, so it is keyed by its record-version or record-retraction identity, and a
    /// conversion Provenance repeats the key in its one `grove-record-version`.
    private static func validateProvenanceKey(
        _ key: RoledIdentifier,
        index: Int,
        kind: Kind,
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        let expectedRole: GroveIdentifierRole = kind == .active ? .recordVersion : .recordRetraction
        guard key.role == expectedRole else {
            throw diagnostic(.mobileExchangeEntryKeySelection, location: entryKeyLocation(index))
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(key.identifier.value) else {
            let rule: ExchangeGraphRule = kind == .active ? .mobileExchangeRecordVersionKey : .mobileRetractionRetractionKey
            throw diagnostic(rule, location: "\(entryKeyLocation(index)).value")
        }
        let versions = try topLevelExtensionIdentifiers(at: index, url: Canonicals.recordVersionValue, document: document)
        let isRepeated = kind == .active
            ? versions.count == 1 && versions[0] == key
            : versions.isEmpty
        guard isRepeated else {
            throw diagnostic(.mobileExchangeRecordVersionExtension, location: "Bundle.entry[\(index)].resource.extension")
        }
    }

    /// A QuestionnaireResponse's one `identifier` holds the submission's, so it is keyed by its context-snapshot identity
    /// and repeats the key in its one `grove-context-snapshot`.
    private static func validateQuestionnaireResponseKey(
        _ key: RoledIdentifier,
        index: Int,
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        guard key.role == .contextSnapshot else {
            throw diagnostic(.mobileExchangeEntryKeySelection, location: entryKeyLocation(index))
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(key.identifier.value) else {
            throw diagnostic(.mobileExchangeContentSnapshotKey, location: "\(entryKeyLocation(index)).value")
        }
        let snapshots = try topLevelExtensionIdentifiers(at: index, url: Canonicals.contextSnapshotValue, document: document)
        guard snapshots.count == 1, snapshots[0] == key else {
            throw diagnostic(.mobileExchangeContextSnapshotExtension, location: "Bundle.entry[\(index)].resource.extension")
        }
    }

    /// Every other resource is keyed by its highest-priority typed identifier, a shared node by its content snapshot.
    private static func validateTypedKey(
        _ key: RoledIdentifier,
        resourceType: String,
        index: Int,
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        let snapshots = try topLevelExtensionIdentifiers(at: index, url: Canonicals.contextSnapshotValue, document: document)
        guard snapshots.isEmpty else {
            throw diagnostic(.mobileExchangeContextSnapshotExtension, location: "Bundle.entry[\(index)].resource.extension")
        }
        let typed: [RoledIdentifier]
        do {
            typed = try document.typedResourceIdentifiers(at: index)
        } catch {
            throw .ruleViolation(.mobileExchangeEntryKey)
        }
        let snapshotRole = contentSnapshotRole(ofResourceType: resourceType)
        if let snapshotRole, !typed.contains(where: { $0.role == snapshotRole }) {
            throw diagnostic(.mobileExchangeContentSnapshotKey, location: "Bundle.entry[\(index)].resource.identifier")
        }
        guard ExchangeIdentity.isCanonicalOpaqueIdentifierValue(key.identifier.value) else {
            throw diagnostic(.mobileExchangeOpaqueResourceIdentity, location: entryKeyLocation(index))
        }
        guard typed.contains(key) else {
            throw diagnostic(.mobileOutputSourceOutputRequired, location: "Bundle.entry[\(index)].resource.identifier")
        }
        let selected = identifierPriority.lazy.compactMap { role in typed.first { $0.role == role } }.first
        guard selected == key, snapshotRole == nil || key.role == snapshotRole else {
            throw diagnostic(.mobileExchangeEntryKeySelection, location: entryKeyLocation(index))
        }
    }

    /// The content-snapshot role a shared node of `resourceType` is keyed by, or `nil` for any other resource.
    private static func contentSnapshotRole(ofResourceType resourceType: String) -> GroveIdentifierRole? {
        if resourceType == ResourceType.device.rawValue {
            return .deviceSnapshot
        }
        return ContextSnapshotRole(resourceType: resourceType) == nil ? nil : .contextSnapshot
    }

    /// The Grove-typed `valueIdentifier` of every top-level extension of the entry's resource with this url.
    ///
    /// An element that states no well-formed Grove-typed Identifier is read as `nil`, which equals no key.
    private static func topLevelExtensionIdentifiers(
        at index: Int,
        url: String,
        document: ValidationDocument
    ) throws(ExchangeGraphError) -> [RoledIdentifier?] {
        let extensions: [[String: Any]]
        do {
            extensions = (try document.resourceObject(at: index) as? [String: Any])?["extension"] as? [[String: Any]] ?? []
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        return extensions.filter { $0["url"] as? String == url }.map { element in
            (element["valueIdentifier"] as? [String: Any]).flatMap(roledIdentifier(in:))
        }
    }

    /// The Grove-typed Identifier a JSON object states, read as ``RoledIdentifier`` reads it.
    private static func roledIdentifier(in object: [String: Any]) -> RoledIdentifier? {
        let codings = (object["type"] as? [String: Any])?["coding"] as? [[String: Any]] ?? []
        let roles = codings.filter { $0["system"] as? String == Canonicals.identifierRoleCodeSystemValue }
        guard roles.count == 1,
              let role = (roles[0]["code"] as? String).flatMap(GroveIdentifierRole.init(rawValue:)),
              let rawSystem = object["system"] as? String,
              let system = try? IdentifierSystem(rawSystem),
              let value = object["value"] as? String,
              let identifier = try? BusinessIdentifier(system: system, value: value) else {
            return nil
        }
        return RoledIdentifier(identifier: identifier, role: role)
    }

    private static func validateLiteralReferences(
        in entries: [BundleEntry],
        document: ValidationDocument,
        resourceTypesByFullURL: [String: String]
    ) throws(ExchangeGraphError) {
        for (index, entry) in entries.enumerated() where entry.resource != nil {
            let json: Any?
            let objects: [[String: Any]]
            do {
                json = try document.resourceObject(at: index)
                objects = try document.resourceObjects(at: index)
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            guard let object = json as? [String: Any], object["contained"] == nil else {
                throw .ruleViolation(.mobileExchangeContainedResourceProhibited)
            }
            let references = objects.compactMap { node -> LiteralReference? in
                guard let reference = node["reference"] as? String, node["identifier"] == nil else {
                    return nil
                }
                return LiteralReference(value: reference, declaredType: node["type"] as? String)
            }
            for reference in references {
                guard !reference.value.hasPrefix("#") else {
                    throw .ruleViolation(.mobileExchangeContainedResourceProhibited)
                }
                guard let actualType = resourceTypesByFullURL[reference.value] else {
                    throw .ruleViolation(.mobileExchangeResolvedReference)
                }
                if let declaredType = reference.declaredType, declaredType != actualType {
                    throw .ruleViolation(.mobileExchangeReferenceDeclaredType)
                }
            }
        }
    }
}
