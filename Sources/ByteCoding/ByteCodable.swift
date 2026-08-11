//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import struct NIOCore.ByteBuffer
import NIOFoundationCompat


/// A type that is decodable from a byte representation.
///
/// Conforming types can be decoded from a `ByteBuffer´ assuming it holds
/// properly formatted binary data.
public protocol ByteDecodable {
    /// Decode the type from the `ByteBuffer`.
    ///
    /// Initialize a new instance using the byte representation provided by the `ByteBuffer`.
    /// This call should move the `readerIndex` forwards.
    ///
    /// - Note: Returns nil if no valid byte representation could be found.
    /// - Parameter byteBuffer: The ByteBuffer to read from.
    init?(from byteBuffer: inout ByteBuffer)
}


/// A type that is decodable to a byte representation.
///
/// Conforming types can be encoded into a `ByteBuffer`.
public protocol ByteEncodable {
    /// Encode into the `ByteBuffer`.
    ///
    /// Encode the byte representation of this type into the provided `ByteBuffer`.
    /// This call should move the `writerIndex` forwards.
    ///
    /// - Parameter byteBuffer: The ByteBuffer to write into.
    func encode(to byteBuffer: inout ByteBuffer)
}


/// A type that is encodable to and decodable from a byte representation.
///
/// Conforming types can be encoded into or decodable from a `ByteBuffer`.
public typealias ByteCodable = ByteEncodable & ByteDecodable


extension ByteDecodable {
    /// Decode the type from `Data`.
    ///
    /// Initialize a new instance using the byte representation provided.
    ///
    /// - Note: Returns nil if no valid byte representation could be found.
    /// - Parameter data: The data to decode.
    public init?(data: Data) {
        var buffer = ByteBuffer(data: data)
        self.init(from: &buffer)
    }
}


extension ByteEncodable {
    /// Encode to data.
    ///
    /// Encode the byte representation of this type.
    ///
    /// - Returns: The encoded data.
    public func encode() -> Data {
        var buffer = ByteBuffer()
        encode(to: &buffer)
        return buffer.getData(at: 0, length: buffer.readableBytes) ?? Data()
    }
}
