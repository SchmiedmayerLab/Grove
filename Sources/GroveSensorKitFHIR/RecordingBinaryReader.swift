//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Members are ordered to read as a narrative rather than by kind.
// swiftlint:disable type_contents_order

public import Foundation

/// Reads the primitives ``RecordingBinaryWriter`` writes, in the same order.
///
/// Every read is bounds-checked and fails closed: a truncated payload throws rather than
/// returning a plausible value assembled from bytes that were never there.
public struct RecordingBinaryReader: ~Copyable {
    /// Why a payload could not be read.
    public enum ReaderError: Error, Equatable {
        /// The payload ended before the value did.
        case unexpectedEnd
        /// A varint ran past the ten bytes a 64-bit value can occupy.
        case varintOverflow
        /// A value used more bytes than its shortest unsigned LEB128 encoding.
        case nonCanonicalVarint
        /// A boolean byte was neither `0x00` nor `0x01`.
        case invalidBoolean(UInt8)
        /// A string's bytes are not valid UTF-8.
        case invalidUTF8
        /// A binary64 value was NaN or infinite.
        case nonFiniteFloat
        /// Negative zero is not the canonical encoding of zero.
        case nonCanonicalNegativeZero
        /// A set member was duplicate or did not follow its predecessor in ascending order.
        case nonAscendingSet
        /// A count would not fit this platform's `Int`.
        case countOutOfRange(UInt64)
        /// Bytes remained after the last declared value.
        case trailingBytes(Int)
    }

    private let bytes: [UInt8]
    private var offset: Int

    /// Creates a reader over an exact payload.
    public init(_ data: Data) {
        self.bytes = Array(data)
        self.offset = 0
    }

    /// Whether every byte has been consumed.
    public var isAtEnd: Bool {
        offset == bytes.count
    }

    /// Requires that the payload is fully consumed, so a partial parse cannot pass as a whole one.
    public consuming func finish() throws {
        guard offset == bytes.count else {
            throw ReaderError.trailingBytes(bytes.count - offset)
        }
    }

    private mutating func next() throws -> UInt8 {
        guard offset < bytes.count else {
            throw ReaderError.unexpectedEnd
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    /// Unsigned LEB128.
    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<10 {
            let byte = try next()
            if index == 9, byte > 0x01 {
                throw ReaderError.varintOverflow
            }
            result |= UInt64(byte & 0x7F) << UInt64(index * 7)
            if byte & 0x80 == 0 {
                if index > 0, byte == 0 {
                    throw ReaderError.nonCanonicalVarint
                }
                return result
            }
        }
        throw ReaderError.varintOverflow
    }

    /// A signed integer, recovered from the two's-complement pattern the writer stored.
    public mutating func readSignedVarint() throws -> Int64 {
        Int64(bitPattern: try readVarint())
    }

    /// IEEE-754 binary64 in network byte order.
    public mutating func readFloat64() throws -> Double {
        var pattern: UInt64 = 0
        for _ in 0..<8 {
            pattern = (pattern << 8) | UInt64(try next())
        }
        let value = Double(bitPattern: pattern)
        guard value.isFinite else {
            throw ReaderError.nonFiniteFloat
        }
        guard pattern != (-0.0).bitPattern else {
            throw ReaderError.nonCanonicalNegativeZero
        }
        return value
    }

    /// One byte: `0x00` false, `0x01` true. Any other byte is a malformed payload, not `true`.
    public mutating func readBoolean() throws -> Bool {
        let byte = try next()
        switch byte {
        case 0x00: return false
        case 0x01: return true
        default: throw ReaderError.invalidBoolean(byte)
        }
    }

    /// A varint UTF-8 byte count, then the bytes.
    public mutating func readString() throws -> String {
        let count = try readCount()
        guard offset + count <= bytes.count else {
            throw ReaderError.unexpectedEnd
        }
        defer { offset += count }
        guard let value = String(bytes: bytes[offset..<(offset + count)], encoding: .utf8) else {
            throw ReaderError.invalidUTF8
        }
        return value
    }

    /// A presence byte, then the value when present.
    public mutating func readOptionalFloat64() throws -> Double? {
        try readBoolean() ? try readFloat64() : nil
    }

    /// A varint element count, then each element in order.
    public mutating func readArray<Element>(element: (inout Self) throws -> Element) throws -> [Element] {
        let count = try readCount()
        var values: [Element] = []
        values.reserveCapacity(min(count, 1024))
        for _ in 0..<count {
            values.append(try element(&self))
        }
        return values
    }

    /// Reads a canonical set and rejects duplicates and non-ascending values.
    public mutating func readCanonicalSet<Element: Comparable>(
        element: (inout Self) throws -> Element
    ) throws -> [Element] {
        let values = try readArray(element: element)
        for (previous, current) in zip(values, values.dropFirst()) where current <= previous {
            throw ReaderError.nonAscendingSet
        }
        return values
    }

    private mutating func readCount() throws -> Int {
        let raw = try readVarint()
        guard let count = Int(exactly: raw), count <= bytes.count - offset else {
            throw ReaderError.countOutOfRange(raw)
        }
        return count
    }
}
