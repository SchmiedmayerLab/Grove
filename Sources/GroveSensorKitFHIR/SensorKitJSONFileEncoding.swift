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

    /// Appends an object whose members are `keys`, sorted by name, with each value `value` appends.
    func object<Key>(
        _ keys: [Key],
        name: (Key) -> String,
        append: (Data) throws -> Void,
        value: (Key) throws -> Void
    ) throws {
        try append(Data("{".utf8))
        for (index, key) in keys.sorted(by: { name($0) < name($1) }).enumerated() {
            if index > 0 {
                try append(Data(",".utf8))
            }
            try self.value(name(key), append: append)
            try append(Data(":".utf8))
            try value(key)
        }
        try append(Data("}".utf8))
    }

    func array<Values: Sequence>(_ values: Values, append: (Data) throws -> Void, element: (Values.Element) throws -> Void) throws {
        try append(Data("[".utf8))
        for (index, value) in values.enumerated() {
            if index > 0 {
                try append(Data(",".utf8))
            }
            try element(value)
        }
        try append(Data("]".utf8))
    }
}

#endif
