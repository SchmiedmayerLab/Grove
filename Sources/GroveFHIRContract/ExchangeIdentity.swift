//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Public value types keep their validating initializers beside stored values, and the UUID layout
// mirrors RFC 4122 groups for direct audit against the generated identity vectors.
// swiftlint:disable type_contents_order multiline_literal_brackets

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
public import Foundation
public import ModelsR4


/// A repository-assigned logical Resource id.
///
/// Source identities and UUID URNs belong in business identifiers and Bundle fullUrls;
/// this type exists only for callers that already have a repository id assignment.
public struct RepositoryID: Hashable, Sendable {
    public let rawValue: String

    // Spelled out rather than matched with `Regex`, which needs iOS 16/macOS 13 and would lift
    // this module above the package deployment floor.
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")

    static func isValidFHIRID(_ value: String) -> Bool {
        (1...64).contains(value.count) && value.allSatisfy(allowedCharacters.contains)
    }

    public init(_ rawValue: String) throws {
        guard Self.isValidFHIRID(rawValue) else {
            throw ExchangeIdentityError.invalidRepositoryID(rawValue)
        }
        self.rawValue = rawValue
    }

    public var primitive: FHIRPrimitive<FHIRString> {
        rawValue.asFHIRStringPrimitive()
    }
}


/// Errors raised before an invalid exchange graph can be serialized.
public enum ExchangeIdentityError: Error, Equatable, Sendable {
    case missingIdentifierSystem
    case missingIdentifierValue
    case invalidIdentifierSystem(String)
    case nonCanonicalIdentifierSystem(supplied: String, encoded: String)
    case invalidRepositoryID(String)
    case invalidIdentifierRole(String)
    case duplicateIdentifierRole
    case identifierSystemRoleMismatch(
        system: String,
        first: GroveIdentifierRole,
        conflicting: GroveIdentifierRole
    )
    case invalidProducerInstance(UUID)
    case invalidEventIdentifier(String)
    case invalidEventSequence(String, underlying: CanonicalDecimalError)
    case duplicateEntryIdentifier(BusinessIdentifier)
    case duplicateFullURL(String)
    case duplicateEntryKeyExtension
    case invalidEntryKeyRole
    case entryKeyPriorityMismatch
    case invalidEntryNodeRole
    case invalidEntryNodeValue(String)
    case missingFullURL
    case missingResource
    case unresolvedInternalReference(String)
    case containedResourcesProhibited
    case incorrectInternalReferenceType(reference: String, declared: String, actual: String)
    case incorrectFullURL(actual: String, expected: String)
    case invalidNamespace(String)
    case identityComponentTooLarge(Int)
    case identityFramingFailure
}


/// The normative Grove Mobile exchange-entry identity algorithm.
public enum ExchangeIdentity {
    /// Verifies that one Grove Identifier namespace has one graph role throughout a Bundle.
    ///
    /// The check walks nested identifier-only References and Provenance entities as well as
    /// top-level resource and entry identifiers. Untyped and non-Grove identifiers remain open.
    public static func validateIdentifierSystemRoles(in bundle: ModelsR4.Bundle) throws {
        let data = try JSONEncoder().encode(bundle)
        let json = try JSONSerialization.jsonObject(with: data)
        var roleBySystem: [String: GroveIdentifierRole] = [:]

        func visit(_ value: Any) throws {
            if let object = value as? [String: Any] {
                if let type = object["type"] as? [String: Any],
                   let codings = type["coding"] as? [[String: Any]] {
                    let groveRoleCodings = codings.filter {
                        $0["system"] as? String
                            == Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
                    }
                    if !groveRoleCodings.isEmpty {
                        guard groveRoleCodings.count == 1,
                              let rawRole = groveRoleCodings[0]["code"] as? String,
                              let role = GroveIdentifierRole(rawValue: rawRole),
                              let system = object["system"] as? String else {
                            throw ExchangeIdentityError.invalidIdentifierRole("missing")
                        }
                        _ = try IdentifierSystem(system)
                        if let first = roleBySystem[system], first != role {
                            throw ExchangeIdentityError.identifierSystemRoleMismatch(
                                system: system,
                                first: first,
                                conflicting: role
                            )
                        }
                        roleBySystem[system] = role
                    }
                }
                for child in object.values {
                    try visit(child)
                }
            } else if let array = value as? [Any] {
                for child in array {
                    try visit(child)
                }
            }
        }
        try visit(json)
    }

    /// Validates the exact, pre-decoding namespace text of every Grove-typed Identifier in JSON.
    ///
    /// `FHIRURI` is backed by `Foundation.URL`, which can percent-encode an IRI while decoding.
    /// Producers that replay stored JSON call this before model decoding so malformed or
    /// noncanonical identity bytes cannot be accepted in normalized form and uploaded unchanged.
    public static func validateSerializedIdentifierSystems(in data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        try validateSerializedIdentifierSystems(in: json)
    }

    private static func validateSerializedIdentifierSystems(in value: Any) throws {
        if let object = value as? [String: Any] {
            if let type = object["type"] as? [String: Any],
               let codings = type["coding"] as? [[String: Any]],
               codings.contains(where: {
                   $0["system"] as? String
                       == Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
               }) {
                guard let system = object["system"] as? String else {
                    throw ExchangeIdentityError.missingIdentifierSystem
                }
                _ = try IdentifierSystem(system)
            }
            for child in object.values {
                try validateSerializedIdentifierSystems(in: child)
            }
        } else if let array = value as? [Any] {
            for child in array {
                try validateSerializedIdentifierSystems(in: child)
            }
        }
    }

    /// Whether a value has the canonical wire form of a Grove pseudonymous identity.
    public static func isCanonicalOpaqueIdentifierValue(_ value: String) -> Bool {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == "v0",
              !components[1].isEmpty,
              components[1].utf8.allSatisfy({
                  $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
              }),
              (try? CanonicalPositiveDecimal(String(components[2]))) != nil,
              components[3].utf8.count == 43,
              components[3].utf8.allSatisfy({
                  $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x5F
              }) else {
            return false
        }
        return true
    }

    /// The length-framed UUID-v5 name bytes for one complete identifier.
    public static func canonicalNameData(for identifier: BusinessIdentifier) throws -> Data {
        do {
            return try LengthFramedUTF8.encode([identifier.systemValue, identifier.value])
        } catch {
            switch error {
            case .componentTooLarge(let byteCount):
                throw ExchangeIdentityError.identityComponentTooLarge(byteCount)
            default:
                throw ExchangeIdentityError.identityFramingFailure
            }
        }
    }

    /// Deterministic lowercase RFC 4122 version-5 UUID URN for a complete identifier.
    private static func fullURL(system: String, value: String) throws -> String {
        guard let namespace = UUID(uuidString: ExchangeContract.fullURLNamespace) else {
            throw ExchangeIdentityError.invalidNamespace(ExchangeContract.fullURLNamespace)
        }
        let namespaceBytes = namespace.uuidString
            .replacingOccurrences(of: "-", with: "")
            .hexBytes
        let identifier = try BusinessIdentifier(system: system, value: value)
        let name = try canonicalNameData(for: identifier)
        let digest = Insecure.SHA1.hash(data: Data(namespaceBytes) + name)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }
        let uuid = [
            hex[0...3].joined(),
            hex[4...5].joined(),
            hex[6...7].joined(),
            hex[8...9].joined(),
            hex[10...15].joined()
        ].joined(separator: "-")
        return "urn:uuid:\(uuid)"
    }

    /// Deterministic lowercase RFC 4122 version-5 UUID URN for a validated identifier.
    public static func fullURL(for identifier: BusinessIdentifier) throws -> String {
        try fullURL(system: identifier.systemValue, value: identifier.value)
    }

    /// Builds an exchange entry with the required complete identifier extension.
    public static func entry(
        identifier: BusinessIdentifier,
        resource: ResourceProxy
    ) throws -> BundleEntry {
        BundleEntry(
            extension: [Extension(
                url: Canonicals.entryNodeKey,
                value: .identifier(identifier.fhirIdentifier)
            )],
            fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: try fullURL(for: identifier))),
            resource: resource
        )
    }

    /// Builds an exchange entry for a resource, such as R4 Provenance, that has no business
    /// identifier element of its own.
    public static func entry(
        nodeKey: ExchangeNodeKey,
        resource: ResourceProxy
    ) throws -> BundleEntry {
        BundleEntry(
            extension: [Extension(
                url: Canonicals.entryNodeKey,
                value: .identifier(nodeKey.identifier.fhirIdentifier)
            )],
            fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: try fullURL(for: nodeKey.identifier))),
            resource: resource
        )
    }
}


extension ExchangeIdentity {
    /// Verifies the graph-level uniqueness invariants before a Bundle is returned.
    public static func validate(entries: [BundleEntry]) throws {
        var identifiers: Set<BusinessIdentifier> = []
        var resourceTypesByFullURL: [String: String] = [:]
        for entry in entries {
            let businessIdentifier = try entryBusinessIdentifier(in: entry)
            guard identifiers.insert(businessIdentifier).inserted else {
                throw ExchangeIdentityError.duplicateEntryIdentifier(businessIdentifier)
            }
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString else {
                throw ExchangeIdentityError.missingFullURL
            }
            guard resourceTypesByFullURL.updateValue(
                entry.resource?.resourceType ?? "",
                forKey: fullURL
            ) == nil else {
                throw ExchangeIdentityError.duplicateFullURL(fullURL)
            }
            let expected = try self.fullURL(for: businessIdentifier)
            guard fullURL == expected else {
                throw ExchangeIdentityError.incorrectFullURL(actual: fullURL, expected: expected)
            }
        }
        try validateLiteralReferences(
            in: entries,
            resourceTypesByFullURL: resourceTypesByFullURL
        )
    }

    private static let allowedEntryKeyRoles: Set<GroveIdentifierRole> = [
        .sourceOutput,
        .sourceArtifact,
        .sourceRecord,
        .writerRecord,
        .recordingDevice,
        .deviceSnapshot,
        .entryNode
    ]

    private static func entryBusinessIdentifier(in entry: BundleEntry) throws -> BusinessIdentifier {
        guard entry.resource != nil else {
            throw ExchangeIdentityError.missingResource
        }
        let entryKeys = entry.extension?.filter { $0.url == Canonicals.entryNodeKey } ?? []
        guard entryKeys.count == 1 else {
            throw ExchangeIdentityError.duplicateEntryKeyExtension
        }
        guard case .identifier(let identifier)? = entryKeys.first?.value else {
            throw ExchangeIdentityError.missingIdentifierSystem
        }
        let businessIdentifier = try BusinessIdentifier(identifier)
        guard let role = businessIdentifier.role, allowedEntryKeyRoles.contains(role) else {
            throw ExchangeIdentityError.invalidEntryKeyRole
        }
        let selected = try selectedResourceIdentifier(in: entry.resource)
        guard selected == businessIdentifier || (selected == nil && role == .entryNode) else {
            throw ExchangeIdentityError.entryKeyPriorityMismatch
        }
        return businessIdentifier
    }

    private static let identifierPriority: [GroveIdentifierRole] = [
        .sourceOutput,
        .sourceArtifact,
        .sourceRecord,
        .writerRecord,
        .deviceSnapshot,
        .recordingDevice
    ]

    private static func selectedResourceIdentifier(
        in resource: ResourceProxy?
    ) throws -> BusinessIdentifier? {
        let typed = try typedResourceIdentifiers(in: resource)
        for role in identifierPriority {
            if let identifier = typed.first(where: { $0.role == role }) {
                return identifier
            }
        }
        return nil
    }

    /// Returns the identifiers whose `Identifier.type` carries a Grove identifier role.
    ///
    /// A malformed Grove-typed identifier fails closed. Untyped business identifiers are not part
    /// of the exchange identity graph and are intentionally omitted.
    public static func typedResourceIdentifiers(
        in resource: ResourceProxy?
    ) throws -> [BusinessIdentifier] {
        guard let resource else {
            return []
        }
        let data = try JSONEncoder().encode(resource)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawIdentifiers = object["identifier"] as? [[String: Any]] else {
            return []
        }
        var identifiers: [BusinessIdentifier] = []
        for rawIdentifier in rawIdentifiers {
            let data = try JSONSerialization.data(withJSONObject: rawIdentifier)
            let identifier = try JSONDecoder().decode(Identifier.self, from: data)
            let carriesGroveRole = identifier.type?.coding?.contains {
                $0.system?.value?.url.absoluteString
                    == Canonicals.identifierRoleCodeSystem.value?.url.absoluteString
            } == true
            guard carriesGroveRole else {
                continue
            }
            let businessIdentifier = try BusinessIdentifier(identifier)
            guard businessIdentifier.role != nil else {
                throw ExchangeIdentityError.invalidIdentifierRole("missing")
            }
            identifiers.append(businessIdentifier)
        }
        return identifiers
    }

    private struct LiteralReference {
        let value: String
        let declaredType: String?
    }

    private static func validateLiteralReferences(
        in entries: [BundleEntry],
        resourceTypesByFullURL: [String: String]
    ) throws {
        for entry in entries {
            guard let resource = entry.resource else {
                continue
            }
            let data = try JSONEncoder().encode(resource)
            let json = try JSONSerialization.jsonObject(with: data)
            guard let object = json as? [String: Any] else {
                throw ExchangeIdentityError.missingResource
            }
            guard object["contained"] == nil else {
                throw ExchangeIdentityError.containedResourcesProhibited
            }
            var references: [LiteralReference] = []
            collectInternalReferences(from: json, into: &references)
            for reference in references {
                guard !reference.value.hasPrefix("#") else {
                    throw ExchangeIdentityError.containedResourcesProhibited
                }
                let actualType = resourceTypesByFullURL[reference.value]
                guard let actualType else {
                    throw ExchangeIdentityError.unresolvedInternalReference(reference.value)
                }
                if let declaredType = reference.declaredType, declaredType != actualType {
                    throw ExchangeIdentityError.incorrectInternalReferenceType(
                        reference: reference.value,
                        declared: declaredType,
                        actual: actualType
                    )
                }
            }
        }
    }

    private static func collectInternalReferences(
        from value: Any,
        into references: inout [LiteralReference]
    ) {
        if let object = value as? [String: Any] {
            if let reference = object["reference"] as? String,
               object["identifier"] == nil {
                references.append(LiteralReference(
                    value: reference,
                    declaredType: object["type"] as? String
                ))
            }
            for child in object.values {
                collectInternalReferences(from: child, into: &references)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectInternalReferences(from: child, into: &references)
            }
        }
    }
}


extension String {
    fileprivate var hexBytes: [UInt8] {
        stride(from: 0, to: count, by: 2).compactMap { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: 2)
            return UInt8(self[start..<end], radix: 16)
        }
    }
}
