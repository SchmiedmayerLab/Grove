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

import CryptoKit
import Foundation
public import ModelsR4


/// A complete business identifier used to identify one exchange-graph node.
///
/// This preserves the exact strings used by the UUIDv5 algorithm instead of round-tripping
/// them through `Foundation.URL`, whose normalization can change their bytes.
public struct BusinessIdentifier: Hashable, Sendable {
    public let system: IdentifierSystem
    public let value: String

    /// The namespace as the text the wire carries.
    public var systemValue: String { system.rawValue }

    public init(system: IdentifierSystem, value: String) throws {
        guard !value.isEmpty else {
            throw ExchangeIdentityError.missingIdentifierValue
        }
        self.system = system
        self.value = value
    }

    /// Accepts a namespace that is still text — a generated constant or a deployment setting.
    ///
    /// - Warning: Prefer ``init(system:value:)-(IdentifierSystem,_)``. This overload re-parses the
    ///   namespace on every call and reports a malformed one here rather than where it was
    ///   configured.
    @_disfavoredOverload
    public init(system: String, value: String) throws {
        try self.init(system: IdentifierSystem(system), value: value)
    }

    public init(_ identifier: Identifier) throws {
        guard let system = identifier.system?.value?.url.absoluteString else {
            throw ExchangeIdentityError.missingIdentifierSystem
        }
        guard let value = identifier.value?.value?.string, !value.isEmpty else {
            throw ExchangeIdentityError.missingIdentifierValue
        }
        try self.init(system: system, value: value)
    }

    public var fhirIdentifier: Identifier {
        Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: systemValue)),
            value: value.asFHIRStringPrimitive()
        )
    }
}


/// A repository-assigned logical Resource id.
///
/// Source identities and UUID URNs belong in business identifiers and Bundle fullUrls;
/// this type exists only for callers that already have a repository id assignment.
public struct RepositoryID: Hashable, Sendable {
    public let rawValue: String

    // Spelled out rather than matched with `Regex`, which needs iOS 16/macOS 13 and would lift
    // this module above the package deployment floor.
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")

    public init(_ rawValue: String) throws {
        guard (1...64).contains(rawValue.count),
              rawValue.allSatisfy(Self.allowedCharacters.contains) else {
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
    case duplicateEntryIdentifier(BusinessIdentifier)
    case duplicateFullURL(String)
    case missingFullURL
    case incorrectFullURL(actual: String, expected: String)
    case invalidNamespace(String)
}


/// The normative Grove Mobile exchange-entry identity algorithm.
public enum ExchangeIdentity {
    /// The UUID-v5 name for one identifier: the system, a vertical bar, then the value.
    ///
    /// Only the system is barred from carrying a vertical bar, so the name splits at the first
    /// one. A value may carry them, because a composed identifier is built from them.
    public static func canonicalName(system: String, value: String) -> String {
        "\(system)|\(value)"
    }

    /// Deterministic lowercase RFC 4122 version-5 UUID URN for a complete identifier.
    public static func fullURL(system: String, value: String) throws -> String {
        guard let namespace = UUID(uuidString: ExchangeContract.fullURLNamespace) else {
            throw ExchangeIdentityError.invalidNamespace(ExchangeContract.fullURLNamespace)
        }
        let namespaceBytes = namespace.uuidString
            .replacingOccurrences(of: "-", with: "")
            .hexBytes
        let name = canonicalName(system: system, value: value)
        let digest = Insecure.SHA1.hash(data: Data(namespaceBytes) + Data(name.utf8))
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
                url: ExchangeContract.entryIdentifierExtension,
                value: .identifier(identifier.fhirIdentifier)
            )],
            fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: try fullURL(for: identifier))),
            resource: resource
        )
    }

    /// Verifies the graph-level uniqueness invariants before a Bundle is returned.
    public static func validate(entries: [BundleEntry]) throws {
        var identifiers: Set<BusinessIdentifier> = []
        var fullURLs: Set<String> = []
        for entry in entries {
            guard case .identifier(let identifier)? = entry.extension?.first(where: {
                $0.url == ExchangeContract.entryIdentifierExtension
            })?.value else {
                throw ExchangeIdentityError.missingIdentifierSystem
            }
            let businessIdentifier = try BusinessIdentifier(identifier)
            guard identifiers.insert(businessIdentifier).inserted else {
                throw ExchangeIdentityError.duplicateEntryIdentifier(businessIdentifier)
            }
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString else {
                throw ExchangeIdentityError.missingFullURL
            }
            guard fullURLs.insert(fullURL).inserted else {
                throw ExchangeIdentityError.duplicateFullURL(fullURL)
            }
            let expected = try self.fullURL(for: businessIdentifier)
            guard fullURL == expected else {
                throw ExchangeIdentityError.incorrectFullURL(actual: fullURL, expected: expected)
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
