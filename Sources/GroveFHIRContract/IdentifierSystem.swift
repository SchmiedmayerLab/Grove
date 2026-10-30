//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The namespace half of a FHIR business identifier: an absolute ASCII RFC 3986 URI naming whose numbering
/// scheme a value belongs to.
///
/// Holding this as a type rather than a `String` means a malformed namespace is reported where the
/// deployment configures it, not later when a conversion is already under way.
///
/// The exact configured text is retained because exchange identities are derived from its UTF-8
/// bytes. IRIs must be converted to their punycoded and percent-escaped URI form by the caller;
/// implicit URL normalization would otherwise make identity bytes platform-dependent.
public struct IdentifierSystem: Hashable, Sendable {
    private static let uriCharacterBytes = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:/?#[]@!$&'()*+,;=-".utf8
    )

    public let rawValue: String

    /// Validates a namespace that is not known until runtime — read from configuration, a server
    /// response, or a deployment property list.
    public init(_ rawValue: String) throws(ExchangeIdentityError) {
        guard !rawValue.isEmpty else {
            throw .missingIdentifierSystem
        }
        let bytes = Array(rawValue.utf8)
        guard let colon = bytes.firstIndex(of: 0x3A),
              colon > 0,
              colon + 1 < bytes.count,
              bytes[0].isRFC3986Alpha,
              bytes[1..<colon].allSatisfy({
                  $0.isRFC3986AlphaNumeric || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E
              }),
              Self.hasValidURICharacters(bytes[(colon + 1)...]) else {
            throw .invalidIdentifierSystem(rawValue)
        }
        guard let parsed = URLComponents(string: rawValue),
              parsed.scheme != nil,
              Self.hasValidIPLiteral(in: parsed) else {
            throw .invalidIdentifierSystem(rawValue)
        }
        guard parsed.string == rawValue else {
            throw .nonCanonicalIdentifierSystem(supplied: rawValue, encoded: parsed.string ?? "")
        }
        self.rawValue = rawValue
    }

    private static func hasValidURICharacters(_ bytes: ArraySlice<UInt8>) -> Bool {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 0x25 {
                let first = bytes.index(after: index)
                guard first < bytes.endIndex else {
                    return false
                }
                let second = bytes.index(after: first)
                guard second < bytes.endIndex,
                      bytes[first].isRFC3986HexDigit,
                      bytes[second].isRFC3986HexDigit else {
                    return false
                }
                index = bytes.index(after: second)
            } else {
                guard uriCharacterBytes.contains(byte) else {
                    return false
                }
                index = bytes.index(after: index)
            }
        }
        return true
    }

    /// `URLComponents` preserves bracketed but malformed hosts such as `[zz]`. RFC 3986 admits a
    /// bracketed host only for IPv6 or IPvFuture, so validate that narrow grammar independently.
    private static func hasValidIPLiteral(in components: URLComponents) -> Bool {
        guard let host = components.percentEncodedHost,
              host.first == "[" || host.last == "]" else {
            return true
        }
        guard host.first == "[", host.last == "]" else {
            return false
        }
        let literal = String(host.dropFirst().dropLast())
        return isValidIPv6(literal) || isValidIPvFuture(literal)
    }

    private static func isValidIPvFuture(_ value: String) -> Bool {
        guard value.first == "v" || value.first == "V",
              let dot = value.firstIndex(of: "."),
              dot > value.index(after: value.startIndex) else {
            return false
        }
        let version = value[value.index(after: value.startIndex)..<dot]
        let address = value[value.index(after: dot)...]
        let addressBytes = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~!$&'()*+,;=:-".utf8
        )
        return version.utf8.allSatisfy(\.isRFC3986HexDigit)
            && !address.isEmpty
            && address.utf8.allSatisfy(addressBytes.contains)
    }

    private static func isValidIPv6(_ value: String) -> Bool {
        guard value.contains(":"), !value.contains(":::") else {
            return false
        }
        let compressedParts = value.components(separatedBy: "::")
        guard compressedParts.count <= 2 else {
            return false
        }
        let hasCompression = compressedParts.count == 2
        let groups = value.split(separator: ":", omittingEmptySubsequences: true)
        var groupCount = 0
        for (index, group) in groups.enumerated() {
            if group.contains(".") {
                guard index == groups.indices.last, isValidIPv4(String(group)) else {
                    return false
                }
                groupCount += 2
            } else {
                guard (1...4).contains(group.utf8.count),
                      group.utf8.allSatisfy(\.isRFC3986HexDigit) else {
                    return false
                }
                groupCount += 1
            }
        }
        if hasCompression {
            return groupCount < 8
        }
        return groupCount == 8 && !value.hasPrefix(":") && !value.hasSuffix(":")
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return false
        }
        return octets.allSatisfy { octet in
            guard let number = UInt8(octet) else {
                return false
            }
            return String(number) == octet
        }
    }
}


extension IdentifierSystem: CustomStringConvertible {
    public var description: String { rawValue }
}


extension IdentifierSystem: ExpressibleByStringLiteral {
    /// The literal form takes a `StaticString`, so only a namespace written in source can be
    /// spelled this way; anything computed at runtime goes through ``init(_:)`` and reports a
    /// malformed namespace instead of trapping.
    public typealias StringLiteralType = StaticString

    public init(stringLiteral value: StaticString) {
        guard let system = try? IdentifierSystem("\(value)") else {
            preconditionFailure("'\(value)' is not an absolute URI usable as an identifier system.")
        }
        self = system
    }
}


extension UInt8 {
    fileprivate var isRFC3986Alpha: Bool {
        (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }

    fileprivate var isRFC3986AlphaNumeric: Bool {
        isRFC3986Alpha || (0x30...0x39).contains(self)
    }

    fileprivate var isRFC3986HexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}
