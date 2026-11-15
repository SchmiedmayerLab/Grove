//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

import Foundation


/// Incremental JSON punctuation with Foundation's established primitive encoding.
struct SensorKitJSONFileEncoding {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    func value(_ value: some Encodable, append: (Data) throws -> Void) throws {
        try append(encoder.encode(value))
    }

    func object<Key: RawRepresentable>(
        _ keys: [Key], append: (Data) throws -> Void, value: (Key) throws -> Void
    ) throws where Key.RawValue == String {
        try append(Data("{".utf8))
        for (index, key) in keys.sorted(by: { $0.rawValue < $1.rawValue }).enumerated() {
            if index > 0 { try append(Data(",".utf8)) }
            try self.value(key.rawValue, append: append)
            try append(Data(":".utf8))
            try value(key)
        }
        try append(Data("}".utf8))
    }

    func object(_ keys: [String], append: (Data) throws -> Void, value: (String) throws -> Void) throws {
        try append(Data("{".utf8))
        for (index, key) in keys.sorted().enumerated() {
            if index > 0 { try append(Data(",".utf8)) }
            try self.value(key, append: append)
            try append(Data(":".utf8))
            try value(key)
        }
        try append(Data("}".utf8))
    }

    func array<Values: Sequence>(_ values: Values, append: (Data) throws -> Void, element: (Values.Element) throws -> Void) throws {
        try append(Data("[".utf8))
        for (index, value) in values.enumerated() {
            if index > 0 { try append(Data(",".utf8)) }
            try element(value)
        }
        try append(Data("]".utf8))
    }
}

#endif
