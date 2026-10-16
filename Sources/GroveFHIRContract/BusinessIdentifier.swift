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
    /// The bytes of ``ExchangeContract/fullURLNamespace``, parsed once.
    private static let fullURLNamespaceBytes: Data? = UUID(uuidString: ExchangeContract.fullURLNamespace).map { namespace in
        withUnsafeBytes(of: namespace.uuid) { Data($0) }
    }

    public let system: IdentifierSystem
    public let value: String

    public var fhirIdentifier: Identifier {
        Identifier(
            system: system.uri,
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
            guard let namespace = Self.fullURLNamespaceBytes else {
                throw .invalidNamespace(ExchangeContract.fullURLNamespace)
            }
            var hash = Insecure.SHA1()
            hash.update(data: namespace)
            hash.update(data: try canonicalNameData)
            var bytes = Array(hash.finalize().prefix(16))
            bytes[6] = (bytes[6] & 0x0f) | 0x50
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            return Self.uuidURN(bytes)
        }
    }

    /// The length-framed UUID-v5 name bytes of this identifier.
    package var canonicalNameData: Data {
        get throws(ExchangeIdentityError) {
            try Data(lengthFramedUTF8: [system.rawValue, value])
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

    /// `urn:uuid:` and the 16 bytes as lowercase hex in the 8-4-4-4-12 grouping.
    private static func uuidURN(_ bytes: [UInt8]) -> String {
        let hexDigits = Array("0123456789abcdef".utf8)
        let prefix = Array("urn:uuid:".utf8)
        return String(unsafeUninitializedCapacity: prefix.count + 36) { buffer in
            var index = 0
            for byte in prefix {
                buffer[index] = byte
                index += 1
            }
            for (offset, byte) in bytes.enumerated() {
                if offset == 4 || offset == 6 || offset == 8 || offset == 10 {
                    buffer[index] = UInt8(ascii: "-")
                    index += 1
                }
                buffer[index] = hexDigits[Int(byte >> 4)]
                buffer[index + 1] = hexDigits[Int(byte & 0x0f)]
                index += 2
            }
            return index
        }
    }
}


extension BusinessIdentifier {
    /// Creates an identifier-only logical Reference with an explicit target resource type.
    ///
    /// Grove exchange graphs use this shape when the referenced resource does not travel in
    /// the same Bundle. Literal references remain reserved for resolvable Bundle entries.
    public func reference(to resourceType: ResourceType) -> Reference {
        Reference(
            identifier: fhirIdentifier,
            type: FHIRPrimitive(FHIRURI(stringLiteral: resourceType.rawValue))
        )
    }
}
