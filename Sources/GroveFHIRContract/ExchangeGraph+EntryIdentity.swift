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
        .sourceOutput, .sourceArtifact, .sourceRecord, .writerRecord, .recordingDevice, .deviceSnapshot, .entryNode
    ]

    private static let identifierPriority: [GroveIdentifierRole] = [
        .sourceOutput, .sourceArtifact, .sourceRecord, .writerRecord, .deviceSnapshot, .recordingDevice
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
                guard roled.role != .event, roled.role != .entryNode,
                      ExchangeIdentity.isCanonicalOpaqueIdentifierValue(roled.identifier.value) else {
                    throw diagnostic(.mobileExchangeOpaqueResourceIdentity, location: location)
                }
                guard roles.insert(roled.role).inserted else {
                    throw diagnostic(.mobileExchangeDistinctResourceIdentityRole, location: location)
                }
            }
        }
    }

    /// Every entry carries one complete key that is its resource's highest-priority typed identifier
    /// (or its entry-node key), no two entries share a key, and each fullUrl is the key's UUIDv5.
    static func validateEntryKeys(entries: [BundleEntry], document: ValidationDocument) throws(ExchangeGraphError) {
        var keys: Set<BusinessIdentifier> = []
        var resourceTypesByFullURL: [String: String] = [:]
        for (index, entry) in entries.enumerated() {
            let key = try entryKey(in: entry, index: index, document: document)
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
        document: ValidationDocument
    ) throws(ExchangeGraphError) -> RoledIdentifier {
        guard entry.resource != nil else {
            throw .invalidEntries("Bundle entry has no resource")
        }
        guard let key = document.entryKey(at: index),
              allowedEntryKeyRoles.contains(key.role) else {
            throw .ruleViolation(.mobileExchangeEntryNodeKey)
        }
        let typed: [RoledIdentifier]
        do {
            typed = try document.typedResourceIdentifiers(at: index)
        } catch {
            throw .ruleViolation(.mobileExchangeEntryNodeKey)
        }
        let selected = identifierPriority.lazy.compactMap { role in typed.first { $0.role == role } }.first
        if key.role == .entryNode {
            guard selected == nil else {
                throw diagnostic(.mobileExchangeEntryKeySelection, location: entryKeyLocation(index))
            }
            return key
        }
        guard typed.contains(key) else {
            throw diagnostic(.mobileOutputSourceOutputRequired, location: "Bundle.entry[\(index)].resource.identifier")
        }
        guard selected == key else {
            throw diagnostic(.mobileExchangeEntryKeySelection, location: entryKeyLocation(index))
        }
        return key
    }

    private static func validateLiteralReferences(
        in entries: [BundleEntry],
        document: ValidationDocument,
        resourceTypesByFullURL: [String: String]
    ) throws(ExchangeGraphError) {
        for (index, entry) in entries.enumerated() where entry.resource != nil {
            let json: Any?
            do {
                json = try document.resourceObject(at: index)
            } catch {
                throw .invalidEntries(String(reflecting: type(of: error)))
            }
            guard let object = json as? [String: Any], object["contained"] == nil else {
                throw .ruleViolation(.mobileExchangeContainedResourceProhibited)
            }
            var references: [LiteralReference] = []
            ExchangeIdentity.walkJSONObjects(object) { node in
                if let reference = node["reference"] as? String, node["identifier"] == nil {
                    references.append(LiteralReference(value: reference, declaredType: node["type"] as? String))
                }
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
