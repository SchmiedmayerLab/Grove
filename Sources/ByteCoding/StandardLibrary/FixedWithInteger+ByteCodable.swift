//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import struct NIOCore.ByteBuffer
public import enum NIOCore.Endianness


/// `ByteCodable` types that are a `FixedWithInteger`.
protocol FixedWidthByteCodable: FixedWidthInteger, PrimitiveByteCodable {}


extension FixedWidthByteCodable {
    /// Decodes a fixed-width integer from its byte representation.
    ///
    /// Decodes a `FixedWidthInteger` from a `ByteBuffer`.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to decode from.
    ///   - endianness: The endianness to use for decoding.
    public init?(from byteBuffer: inout ByteBuffer, endianness: Endianness) {
        guard let value = byteBuffer.readInteger(endianness: endianness, as: Self.self) else {
            return nil
        }
        self = value
    }

    /// Encodes a fixed-width integer to its byte representation.
    ///
    /// Encodes a `FixedWidthInteger` into a `ByteBuffer`.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to write to.
    ///   - endianness: The endianness to use for encoding.
    public func encode(to byteBuffer: inout ByteBuffer, endianness: Endianness) {
        byteBuffer.writeInteger(self, endianness: endianness)
    }
}


extension UInt8: FixedWidthByteCodable {}
extension UInt16: FixedWidthByteCodable {}
extension UInt32: FixedWidthByteCodable {}
extension UInt64: FixedWidthByteCodable {}


extension Int8: FixedWidthByteCodable {}
extension Int16: FixedWidthByteCodable {}
extension Int32: FixedWidthByteCodable {}
extension Int64: FixedWidthByteCodable {}
