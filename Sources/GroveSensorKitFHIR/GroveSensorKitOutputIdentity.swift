//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
import GroveFHIRContract


enum GroveSensorKitOutputIdentity {
    static func businessIdentifier(
        source: GroveSensorKitSourceRecordID,
        discriminator: String
    ) throws -> GroveFHIRBusinessIdentifier {
        guard let namespace = UUID(uuidString: GroveSensorKitContract.outputIdentifierNamespace) else {
            throw GroveFHIRExchangeIdentityError.invalidNamespace(
                GroveSensorKitContract.outputIdentifierNamespace
            )
        }
        let name = canonicalName(
            system: GroveSensorKitContract.sourceRecordIdentifierSystem,
            value: source.value,
            discriminator: discriminator
        )
        let namespaceBytes = namespace.uuidString
            .replacingOccurrences(of: "-", with: "")
            .hexBytes
        let digest = Insecure.SHA1.hash(data: Data(namespaceBytes) + Data(name.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }
        let value = [
            hex[0...3].joined(),
            hex[4...5].joined(),
            hex[6...7].joined(),
            hex[8...9].joined(),
            hex[10...15].joined()
        ].joined(separator: "-")
        return try GroveFHIRBusinessIdentifier(
            system: GroveSensorKitContract.outputIdentifierSystem,
            value: value
        )
    }

    static func canonicalName(system: String, value: String, discriminator: String) -> String {
        "[\(quote(system)),\(quote(value)),\(quote(discriminator))]"
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0a: result += "\\n"
            case 0x0c: result += "\\f"
            case 0x0d: result += "\\r"
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 0x00...0x1f: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
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
