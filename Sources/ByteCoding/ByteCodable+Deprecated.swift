//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import struct NIOCore.ByteBuffer
public import enum NIOCore.Endianness


// MARK: - ByteBuffer

extension ByteDecodable {
    /// Decode the type from the `ByteBuffer`.
    ///
    /// Initialize a new instance using the byte representation provided by the `ByteBuffer`.
    /// This call should move the `readerIndex` forwards.
    ///
    /// - Note: Returns nil if no valid byte representation could be found.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to read from.
    ///   - endianness: The preferred endianness to use for decoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    @available(*, deprecated, message: "Preferred Endianness was removed. Refer to PrimitiveByteDecodable/init(from:endianness:) if applicable.")
    @_documentation(visibility: internal)
    @_disfavoredOverload
    init?(from byteBuffer: inout ByteBuffer, preferredEndianness endianness: Endianness) {
        self.init(from: &byteBuffer)
    }
}


extension PrimitiveByteDecodable {
    /// Decode the type from the `ByteBuffer`.
    ///
    /// Initialize a new instance using the byte representation provided by the `ByteBuffer`.
    /// This call should move the `readerIndex` forwards.
    ///
    /// - Note: Returns nil if no valid byte representation could be found.
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to read from.
    ///   - endianness: The preferred endianness to use for decoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    @available(*, deprecated, renamed: "init(from:endianness:)", message: "Preferred Endianness was replaced by the PrimitiveCodable protocols.")
    @_documentation(visibility: internal)
    init?(from byteBuffer: inout ByteBuffer, preferredEndianness endianness: Endianness) {
        self.init(from: &byteBuffer, endianness: endianness)
    }
}


extension ByteEncodable {
    /// Encode into the `ByteBuffer`.
    ///
    /// Encode the byte representation of this type into the provided `ByteBuffer`.
    /// This call should move the `writerIndex` forwards.
    ///
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to write into.
    ///   - endianness: The preferred endianness to use for encoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    @available(*, deprecated, message: "Preferred Endianness was removed. Refer to PrimitiveByteEncodable/encode(to:endianness:) if applicable.")
    @_documentation(visibility: internal)
    @_disfavoredOverload
    func encode(to byteBuffer: inout ByteBuffer, preferredEndianness endianness: Endianness) {
        self.encode(to: &byteBuffer)
    }
}


extension PrimitiveByteEncodable {
    /// Encode into the `ByteBuffer`.
    ///
    /// Encode the byte representation of this type into the provided `ByteBuffer`.
    /// This call should move the `writerIndex` forwards.
    ///
    /// - Parameters:
    ///   - byteBuffer: The ByteBuffer to write into.
    ///   - endianness: The preferred endianness to use for encoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    @available(*, deprecated, renamed: "encode(to:endianness:)", message: "Preferred Endianness was replaced by the PrimitiveCodable protocols.")
    @_documentation(visibility: internal)
    func encode(to byteBuffer: inout ByteBuffer, preferredEndianness endianness: Endianness) {
        self.encode(to: &byteBuffer, endianness: endianness)
    }
}

// MARK: - Data

extension ByteDecodable {
    /// Decode the type from `Data`.
    ///
    /// Initialize a new instance using the byte representation provided.
    ///
    /// - Note: Returns nil if no valid byte representation could be found.
    /// - Parameters:
    ///   - data: The data to decode.
    ///   - endianness: The preferred endianness to use for decoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    @available(*, deprecated, message: "Preferred Endianness was removed. Refer to PrimitiveByteDecodable/init(data:endianness:) if applicable.")
    @_documentation(visibility: internal)
    @_disfavoredOverload
    public init?(data: Data, preferredEndianness endianness: Endianness) {
        var buffer = ByteBuffer(data: data)
        self.init(from: &buffer)
    }
}


extension PrimitiveByteDecodable {
    /// Decode the type from `Data`.
    ///
    /// Initialize a new instance using the byte representation provided.
    ///
    /// - Note: Returns nil if no valid byte representation could be found.
    /// - Parameters:
    ///   - data: The data to decode.
    ///   - endianness: The preferred endianness to use for decoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    @available(*, deprecated, renamed: "init(data:endianness:)", message: "Preferred Endianness was replaced by the PrimitiveCodable protocols.")
    @_documentation(visibility: internal)
    public init?(data: Data, preferredEndianness endianness: Endianness) {
        self.init(data: data, endianness: endianness)
    }
}


extension ByteEncodable {
    /// Encode to data.
    ///
    /// Encode the byte representation of this type.
    ///
    /// - Parameter endianness: The preferred endianness to use for encoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    /// - Returns: The encoded data.
    @available(*, deprecated, message: "Preferred Endianness was removed. Please refer to PrimitiveByteEncodable/encode(endianness:) if applicable.")
    @_documentation(visibility: internal)
    @_disfavoredOverload
    public func encode(preferredEndianness endianness: Endianness) -> Data {
        var buffer = ByteBuffer()
        encode(to: &buffer)
        return buffer.getData(at: 0, length: buffer.readableBytes) ?? Data()
    }
}

extension PrimitiveByteEncodable {
    /// Encode to data.
    ///
    /// Encode the byte representation of this type.
    ///
    /// - Parameter endianness: The preferred endianness to use for encoding if applicable.
    ///     This might not apply to certain data structures that operate on single byte level.
    /// - Returns: The encoded data.
    @available(*, deprecated, renamed: "encode(endianness:)", message: "Preferred Endianness was replaced by the PrimitiveCodable protocols.")
    @_documentation(visibility: internal)
    public func encode(preferredEndianness endianness: Endianness) -> Data {
        encode(endianness: endianness)
    }
}
