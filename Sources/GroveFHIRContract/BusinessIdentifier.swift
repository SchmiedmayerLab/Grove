//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
package import Foundation
public import ModelsR4


/// A complete business identifier: the exact `Identifier.system` and `Identifier.value` pair.
///
/// The strings are kept as configured instead of round-tripping through `Foundation.URL`, whose
/// normalization could change the bytes the UUIDv5 algorithm names.
public struct BusinessIdentifier: Hashable, Sendable {
    public let system: IdentifierSystem
    public let value: String

    public var fhirIdentifier: Identifier {
        Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: system.rawValue)),
            value: value.asFHIRStringPrimitive()
        )
    }

    /// The deterministic lowercase RFC 4122 version-5 UUID URN this identifier names.
    public var fullURL: FHIRPrimitive<FHIRURI> {
        get throws(ExchangeIdentityError) {
            FHIRPrimitive(FHIRURI(stringLiteral: try fullURLString))
        }
    }

    package var fullURLString: String {
        get throws(ExchangeIdentityError) {
            guard let namespace = UUID(uuidString: ExchangeContract.fullURLNamespace) else {
                throw .invalidNamespace(ExchangeContract.fullURLNamespace)
            }
            let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
            let digest = Insecure.SHA1.hash(data: Data(namespaceBytes) + (try canonicalNameData))
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
    }

    /// The length-framed UUID-v5 name bytes of this identifier.
    package var canonicalNameData: Data {
        get throws(ExchangeIdentityError) {
            do {
                return try LengthFramedUTF8.encode([system.rawValue, value])
            } catch {
                switch error {
                case .componentTooLarge(let byteCount):
                    throw .identityComponentTooLarge(byteCount)
                default:
                    throw .identityFramingFailure
                }
            }
        }
    }

    public init(system: IdentifierSystem, value: String) throws(ExchangeIdentityError) {
        guard !value.isEmpty else {
            throw .missingIdentifierValue
        }
        self.system = system
        self.value = value
    }

    /// Reads the system and value; a Grove identifier role is ``RoledIdentifier``'s concern.
    public init(_ identifier: Identifier) throws(ExchangeIdentityError) {
        guard let system = identifier.system?.value?.url.absoluteString else {
            throw .missingIdentifierSystem
        }
        guard let value = identifier.value?.value?.string, !value.isEmpty else {
            throw .missingIdentifierValue
        }
        try self.init(system: IdentifierSystem(system), value: value)
    }

    /// For values this module has already shaped, such as a minted `v0:` or `e0:` form.
    init(system: IdentifierSystem, nonemptyValue value: String) {
        self.system = system
        self.value = value
    }
}


extension BusinessIdentifier {
    /// Creates an identifier-only logical Reference with an explicit target resource type.
    ///
    /// Grove conversion contexts use this shape when the referenced resource does not travel in
    /// the same Bundle. Literal references remain reserved for resolvable Bundle entries.
    public func reference(to resourceType: ResourceType) -> Reference {
        Reference(
            identifier: fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }
}
