//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import struct NIOCore.ByteBuffer
public import enum NIOCore.Endianness


extension Float32: PrimitiveByteCodable {
    /// Decodes a float from its byte representation.
    ///
    /// Decodes a `Float32` from a `ByteBuffer`.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to decode from.
    ///   - endianness: The endianness to use for decoding.
    public init?(from byteBuffer: inout ByteBuffer, endianness: Endianness) {
        guard let bitPattern = UInt32(from: &byteBuffer, endianness: endianness) else {
            return nil
        }

        self.init(bitPattern: bitPattern)
    }

    /// Encodes a float to its byte representation.
    ///
    /// Encodes a `Float32` into a `ByteBuffer`.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to write to.
    ///   - endianness: The endianness to use for encoding.
    public func encode(to byteBuffer: inout ByteBuffer, endianness: Endianness) {
        bitPattern.encode(to: &byteBuffer, endianness: endianness)
    }
}


extension Float64: PrimitiveByteCodable {
    /// Decodes a float from its byte representation.
    ///
    /// Decodes a `Float64` from a `ByteBuffer`.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to decode from.
    ///   - endianness: The endianness to use for decoding.
    public init?(from byteBuffer: inout ByteBuffer, endianness: Endianness) {
        guard let bitPattern = UInt64(from: &byteBuffer, endianness: endianness) else {
            return nil
        }

        self.init(bitPattern: bitPattern)
    }

    /// Encodes a float to its byte representation.
    ///
    /// Encodes a `Float64` into a `ByteBuffer`.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to write to.
    ///   - endianness: The endianness to use for encoding.
    public func encode(to byteBuffer: inout ByteBuffer, endianness: Endianness) {
        bitPattern.encode(to: &byteBuffer, endianness: endianness)
    }
}
