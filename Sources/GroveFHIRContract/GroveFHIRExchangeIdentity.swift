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
public struct GroveFHIRBusinessIdentifier: Hashable, Sendable {
    public let system: String
    public let value: String

    public init(system: String, value: String) throws {
        guard !system.isEmpty else {
            throw GroveFHIRExchangeIdentityError.missingIdentifierSystem
        }
        guard !value.isEmpty else {
            throw GroveFHIRExchangeIdentityError.missingIdentifierValue
        }
        guard let url = URL(string: system), url.scheme != nil else {
            throw GroveFHIRExchangeIdentityError.invalidIdentifierSystem(system)
        }
        // FHIRModels stores uri values as Foundation.URL. Require its serialized form to
        // remain byte-for-byte stable so entry identity cannot diverge after encoding.
        guard url.absoluteString == system else {
            throw GroveFHIRExchangeIdentityError.nonCanonicalIdentifierSystem(
                supplied: system,
                encoded: url.absoluteString
            )
        }
        self.system = system
        self.value = value
    }

    public init(_ identifier: Identifier) throws {
        guard let system = identifier.system?.value?.url.absoluteString else {
            throw GroveFHIRExchangeIdentityError.missingIdentifierSystem
        }
        guard let value = identifier.value?.value?.string, !value.isEmpty else {
            throw GroveFHIRExchangeIdentityError.missingIdentifierValue
        }
        try self.init(system: system, value: value)
    }

    public var fhirIdentifier: Identifier {
        Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: system)),
            value: value.asFHIRStringPrimitive()
        )
    }
}


/// A repository-assigned logical Resource id.
///
/// Source identities and UUID URNs belong in business identifiers and Bundle fullUrls;
/// this type exists only for callers that already have a repository id assignment.
public struct GroveFHIRRepositoryID: Hashable, Sendable {
    public let rawValue: String

    // Spelled out rather than matched with `Regex`, which needs iOS 16/macOS 13 and would lift
    // this module above the package deployment floor.
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")

    public init(_ rawValue: String) throws {
        guard (1...64).contains(rawValue.count),
              rawValue.allSatisfy(Self.allowedCharacters.contains) else {
            throw GroveFHIRExchangeIdentityError.invalidRepositoryID(rawValue)
        }
        self.rawValue = rawValue
    }

    public var primitive: FHIRPrimitive<FHIRString> {
        rawValue.asFHIRStringPrimitive()
    }
}


/// Errors raised before an invalid exchange graph can be serialized.
public enum GroveFHIRExchangeIdentityError: Error, Equatable, Sendable {
    case missingIdentifierSystem
    case missingIdentifierValue
    case invalidIdentifierSystem(String)
    case nonCanonicalIdentifierSystem(supplied: String, encoded: String)
    case invalidRepositoryID(String)
    case duplicateEntryIdentifier(GroveFHIRBusinessIdentifier)
    case duplicateFullURL(String)
    case missingFullURL
    case incorrectFullURL(actual: String, expected: String)
    case invalidNamespace(String)
}


/// The normative Grove Mobile exchange-entry identity algorithm.
public enum GroveFHIRExchangeIdentity {
    /// RFC 8785/JCS serialization of exactly `[system,value]` for the restricted
    /// two-string input defined by `exchange-identity.json`.
    public static func canonicalName(system: String, value: String) -> String {
        "[\(quotedJCSString(system)),\(quotedJCSString(value))]"
    }

    /// Deterministic lowercase RFC 4122 version-5 UUID URN for a complete identifier.
    public static func fullURL(system: String, value: String) throws -> String {
        guard let namespace = UUID(uuidString: GroveFHIRExchangeContract.fullURLNamespace) else {
            throw GroveFHIRExchangeIdentityError.invalidNamespace(GroveFHIRExchangeContract.fullURLNamespace)
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
    public static func fullURL(for identifier: GroveFHIRBusinessIdentifier) throws -> String {
        try fullURL(system: identifier.system, value: identifier.value)
    }

    /// Builds an exchange entry with the required complete identifier extension.
    public static func entry(
        identifier: GroveFHIRBusinessIdentifier,
        resource: ResourceProxy
    ) throws -> BundleEntry {
        BundleEntry(
            extension: [Extension(
                url: GroveFHIRExchangeContract.entryIdentifierExtension,
                value: .identifier(identifier.fhirIdentifier)
            )],
            fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: try fullURL(for: identifier))),
            resource: resource
        )
    }

    /// Verifies the graph-level uniqueness invariants before a Bundle is returned.
    public static func validate(entries: [BundleEntry]) throws {
        var identifiers: Set<GroveFHIRBusinessIdentifier> = []
        var fullURLs: Set<String> = []
        for entry in entries {
            guard case .identifier(let identifier)? = entry.extension?.first(where: {
                $0.url == GroveFHIRExchangeContract.entryIdentifierExtension
            })?.value else {
                throw GroveFHIRExchangeIdentityError.missingIdentifierSystem
            }
            let businessIdentifier = try GroveFHIRBusinessIdentifier(identifier)
            guard identifiers.insert(businessIdentifier).inserted else {
                throw GroveFHIRExchangeIdentityError.duplicateEntryIdentifier(businessIdentifier)
            }
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString else {
                throw GroveFHIRExchangeIdentityError.missingFullURL
            }
            guard fullURLs.insert(fullURL).inserted else {
                throw GroveFHIRExchangeIdentityError.duplicateFullURL(fullURL)
            }
            let expected = try self.fullURL(for: businessIdentifier)
            guard fullURL == expected else {
                throw GroveFHIRExchangeIdentityError.incorrectFullURL(actual: fullURL, expected: expected)
            }
        }
    }

    static func quotedJCSString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08:
                result += "\\b"
            case 0x09:
                result += "\\t"
            case 0x0a:
                result += "\\n"
            case 0x0c:
                result += "\\f"
            case 0x0d:
                result += "\\r"
            case 0x22:
                result += "\\\""
            case 0x5c:
                result += "\\\\"
            case 0x00...0x1f:
                result += String(format: "\\u%04x", scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
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
