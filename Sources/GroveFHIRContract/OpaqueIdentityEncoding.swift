//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


extension Data {
    private static let base64URLAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// The bytes in base64url (RFC 4648 §5) without padding.
    package var base64URLEncodedStringWithoutPadding: String {
        let length = (count * 4 + 2) / 3
        return String(unsafeUninitializedCapacity: length) { output in
            Self.base64URLAlphabet.withUnsafeBufferPointer { alphabet in
                withUnsafeBytes { input in
                    // Each group of up to three bytes is 24 bits read six at a time; n bytes need n + 1 characters.
                    var written = 0
                    for start in stride(from: 0, to: input.count, by: 3) {
                        let width = Swift.min(3, input.count - start)
                        var group: UInt32 = 0
                        for offset in 0..<width {
                            group |= UInt32(input[start + offset]) << UInt32(16 - 8 * offset)
                        }
                        for index in 0...width {
                            output[written] = alphabet[Int((group >> UInt32(18 - 6 * index)) & 0x3F)]
                            written += 1
                        }
                    }
                    return written
                }
            }
        }
    }

    /// Every UTF-8 field preceded by its unsigned 32-bit big-endian byte count: the frozen framing of every HMAC
    /// preimage and UUIDv5 entry name, so no delimiter is special.
    package init(lengthFramedUTF8 fields: [String]) throws(ExchangeIdentityError) {
        var capacity = 0
        for field in fields {
            guard UInt32(exactly: field.utf8.count) != nil else {
                throw .identityComponentTooLarge(field.utf8.count)
            }
            capacity += 4 + field.utf8.count
        }
        var data = Data(capacity: capacity)
        for field in fields {
            var bigEndianLength = UInt32(field.utf8.count).bigEndian
            Swift.withUnsafeBytes(of: &bigEndianLength) { data.append(contentsOf: $0) }
            data.append(contentsOf: field.utf8)
        }
        self = data
    }
}


extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }
}
