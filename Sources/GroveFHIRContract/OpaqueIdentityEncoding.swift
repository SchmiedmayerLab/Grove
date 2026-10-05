//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


extension Data {
    /// The bytes in base64url (RFC 4648 §5) without padding.
    package var base64URLEncodedStringWithoutPadding: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Every UTF-8 field preceded by its unsigned 32-bit big-endian byte count: the frozen framing of every HMAC
    /// preimage and UUIDv5 entry name, so no delimiter is special.
    package init(lengthFramedUTF8 fields: [String]) throws(ExchangeIdentityError) {
        var data = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            guard let length = UInt32(exactly: bytes.count) else {
                throw .identityComponentTooLarge(bytes.count)
            }
            var bigEndianLength = length.bigEndian
            Swift.withUnsafeBytes(of: &bigEndianLength) { data.append(contentsOf: $0) }
            data.append(bytes)
        }
        self = data
    }
}


extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }
}
