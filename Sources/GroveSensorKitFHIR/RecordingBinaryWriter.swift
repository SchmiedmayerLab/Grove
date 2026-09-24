//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Writes the primitives the Grove binary recording formats are specified in.
///
/// `grove-ppg-1` is specified down to LEB128 varints and big-endian binary64. Grove ships the
/// primitives so a producer encodes the published bytes rather than re-deriving them: a varint is
/// easy to write and easy to write differently.
public struct RecordingBinaryWriter: ~Copyable {
    /// A value that has no canonical representation in a registered binary payload.
    public enum WriterError: Error, Equatable, Sendable {
        /// NaN and infinities are outside the registered finite binary64 domain.
        case nonFiniteFloat
        /// A mathematical set cannot contain the same logical value twice.
        case duplicateSetValue
    }

    private var bytes: Data

    /// Creates an empty writer.
    public init() {
        bytes = Data()
    }

    /// The bytes written so far.
    public consuming func data() -> Data {
        bytes
    }

    /// Unsigned LEB128.
    public mutating func writeVarint(_ value: UInt64) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while remaining != 0
    }

    /// A signed integer, truncated to its 64-bit two's-complement pattern first, so a negative
    /// value occupies ten bytes exactly as the registry states.
    public mutating func writeVarint(_ value: Int64) {
        writeVarint(UInt64(bitPattern: value))
    }

    /// IEEE-754 binary64 in network byte order.
    public mutating func writeFloat64(_ value: Double) throws(WriterError) {
        guard value.isFinite else {
            throw .nonFiniteFloat
        }
        let canonical = value == 0 ? 0.0 : value
        withUnsafeBytes(of: canonical.bitPattern.bigEndian) { bytes.append(contentsOf: $0) }
    }

    /// One byte: `0x00` false, `0x01` true.
    public mutating func writeBoolean(_ value: Bool) {
        bytes.append(value ? 0x01 : 0x00)
    }

    /// A varint UTF-8 byte count, then the bytes.
    public mutating func writeString(_ value: String) {
        let utf8 = Array(value.utf8)
        writeVarint(UInt64(utf8.count))
        bytes.append(contentsOf: utf8)
    }

    /// A presence byte, then the value when present.
    public mutating func writeOptionalFloat64(_ value: Double?) throws(WriterError) {
        writeBoolean(value != nil)
        if let value {
            try writeFloat64(value)
        }
    }

    /// A varint element count, then each element in order.
    public mutating func writeArray<Element>(
        _ elements: [Element],
        element: (inout Self, Element) throws -> Void
    ) rethrows {
        writeVarint(UInt64(elements.count))
        for value in elements {
            try element(&self, value)
        }
    }

    /// A canonical set: reject duplicates, sort ascending, then write count and values.
    public mutating func writeCanonicalSet<Element: Comparable & Hashable>(
        _ elements: [Element],
        element: (inout Self, Element) throws -> Void
    ) throws {
        guard Set(elements).count == elements.count else {
            throw WriterError.duplicateSetValue
        }
        try writeArray(elements.sorted(), element: element)
    }
}
