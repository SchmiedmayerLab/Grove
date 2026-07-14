//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import NIOCore


extension String: ByteCodable {
    /// Decodes an utf8 string from its byte representation.
    ///
    /// Decodes an utf8 string from a `ByteBuffer`.
    ///
    /// - Note: This implementation assumes that all bytes in the ByteBuffer are representing
    ///     the string.
    /// - Parameter byteBuffer: The ByteBuffer to decode from.
    public init?(from byteBuffer: inout ByteBuffer) {
        guard let string = byteBuffer.readString(length: byteBuffer.readableBytes) else {
            return nil
        }

        self = string
    }

    /// Encodes an utf8 string to its byte representation.
    ///
    /// Encodes an utf8 string into a `ByteBuffer`.
    ///
    /// - Parameter byteBuffer: The ByteBuffer to write to.
    public func encode(to byteBuffer: inout ByteBuffer) {
        byteBuffer.writeString(self)
    }
}
