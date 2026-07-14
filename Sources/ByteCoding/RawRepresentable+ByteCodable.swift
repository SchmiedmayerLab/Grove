//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import NIOCore


extension ByteDecodable where Self: RawRepresentable, Self.RawValue: ByteDecodable {
    /// Decode the type from the `ByteBuffer` using the underlying `RawValue` representation.
    /// - Parameter byteBuffer: The ByteBuffer to read from.
    public init?(from byteBuffer: inout ByteBuffer) {
        guard let rawValue = Self.RawValue(from: &byteBuffer) else {
            return nil
        }
        self.init(rawValue: rawValue)
    }
}


extension ByteEncodable where Self: RawRepresentable, Self.RawValue: ByteEncodable {
    /// Encode into the `ByteBuffer` using the underlying `RawValue` representation.
    /// - Parameter byteBuffer: The ByteBuffer to write into.
    public func encode(to byteBuffer: inout ByteBuffer) {
        rawValue.encode(to: &byteBuffer)
    }
}
