//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import NIO


extension ByteBuffer {
    mutating func writeEDFAsciiTrimming(_ value: String, length: Int) {
        self.writeEDFAscii(String(value.prefix(length)), length: length)
    }

    mutating func writeEDFAscii(_ value: String, length: Int) {
        precondition(value.isASCII, "Input string is not ascii: \"\(value)\"")
        precondition(value.count <= length, "Tried to encode string that was longer than \(length) bytes: \"\(value)\"")
        let padding = String(repeating: " ", count: max(0, length - value.count))

        let previousIndex = writerIndex
        writeString(value)
        writeString(padding)
        assert(writerIndex == previousIndex + length, "Unexpected writer increase from \(previousIndex) to \(writerIndex) which is not a offset of \(length).")
    }

    mutating func writeEDFAsciiTrimming<Value: BinaryInteger>(_ value: Value, length: Int) {
        writeEDFAsciiTrimming(value.description, length: length)
    }

    mutating func writeEDFAscii<Value: BinaryInteger>(_ value: Value, length: Int) {
        writeEDFAscii(value.description, length: length)
    }

    mutating func writeEDFAsciiTrimming(_ value: Double, length: Int) {
        writeEDFAscii(value.edfRepresentation(idealLength: length), length: length)
    }
}
