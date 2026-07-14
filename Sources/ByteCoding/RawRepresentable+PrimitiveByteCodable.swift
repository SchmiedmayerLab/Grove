//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import NIOCore


extension PrimitiveByteDecodable where Self: RawRepresentable, Self.RawValue: PrimitiveByteDecodable {
    /// Decode the type from the `ByteBuffer` using the underlying `RawValue` representation.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to read from.
    ///   - endianness: The order in which bytes are arranged in the ByteBuffer.
    public init?(from byteBuffer: inout ByteBuffer, endianness: Endianness) {
        guard let rawValue = Self.RawValue(from: &byteBuffer, endianness: endianness) else {
            return nil
        }
        self.init(rawValue: rawValue)
    }
}


extension PrimitiveByteEncodable where Self: RawRepresentable, Self.RawValue: PrimitiveByteEncodable {
    /// Encode into the `ByteBuffer` using the underlying `RawValue` representation.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to write into.
    ///   - endianness: The order in which bytes are arranged in the ByteBuffer.
    public func encode(to byteBuffer: inout ByteBuffer, endianness: Endianness) {
        rawValue.encode(to: &byteBuffer, endianness: endianness)
    }
}
