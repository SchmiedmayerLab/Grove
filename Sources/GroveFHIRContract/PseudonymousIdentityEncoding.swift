//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Failures raised before a pseudonymous identifier can be minted.
public enum PseudonymousIdentityError: Error, Equatable, Sendable {
    case invalidKeyID(String)
    case invalidEpoch(String)
    case keyTooShort(actualBytes: Int)
    case publishedConformanceKeyProhibited
    case emptyComponent(String)
    case invalidCodeToken(field: String, value: String)
    case providerKindRequired(String)
    case reusedIdentifierSystem
    case componentTooLarge(byteCount: Int)
    case invalidComponentCount(kind: PseudonymousIdentityKind, expected: Int, actual: Int)
}


/// The frozen byte framing shared by HMAC preimages and UUIDv5 entry names.
public enum LengthFramedUTF8 {
    /// Encodes every UTF-8 field with its unsigned 32-bit big-endian byte count.
    public static func encode(_ fields: [String]) throws(PseudonymousIdentityError) -> Data {
        var data = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            guard let length = UInt32(exactly: bytes.count) else {
                throw .componentTooLarge(byteCount: bytes.count)
            }
            var bigEndianLength = length.bigEndian
            withUnsafeBytes(of: &bigEndianLength) { data.append(contentsOf: $0) }
            data.append(bytes)
        }
        return data
    }
}


extension Data {
    var base64URLEncodedStringWithoutPadding: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}


extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }
}
