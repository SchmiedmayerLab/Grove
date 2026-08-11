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


extension ByteBuffer {
    /// Get 24-bit signed integer at a given index without moving the reader index.
    ///
    /// - Parameters:
    ///   - index: The starting index of the integer in the `ByteBuffer`.
    ///   - endianness: The endianness of the integer in the `ByteBuffer`.
    /// - Returns: A 24-bit signed integer put into a `Int32` type or `nil` if the bytes are not readable.
    @inlinable
    public func getInt24(at index: Int, endianness: Endianness = .big) -> Int32? {
        guard var bitPattern = getUInt24(at: index, endianness: endianness) else {
            return nil
        }

        // what this method is doing here, is translating the 24-bit two's complement into a 32-bit two's complement.

        // if its larger than the largest positive number, we want to make sure that all upper 8 bits are flipped to one.
        if bitPattern > 0x7FFFFF { // (2 ^ 23) - 1
            bitPattern |= 0xFF000000
        }

        // I love Swift for that! We can just reinterpret the 32UInt bit pattern into a Int32!
        return Int32(bitPattern: bitPattern)
    }

    /// Read 24-bit signed integer and move the reader index forward accordingly.
    ///
    /// - Parameter endianness: The endianness of the integer in the `ByteBuffer`.
    /// - Returns: A 24-bit signed integer put into a `Int32` type or `nil` if the bytes are not readable.
    @inlinable
    public mutating func readInt24(endianness: Endianness = .big) -> Int32? {
        guard let value = getInt24(at: self.readerIndex, endianness: endianness) else {
            return nil
        }
        self.moveReaderIndex(forwardBy: 3)
        return value
    }
}


// see https://github.com/apple/swift-nio-extras/pull/114
extension ByteBuffer {
    /// Get 24-bit unsigned integer at a given index without moving the reader index.
    ///
    /// - Parameters:
    ///   - index: The starting index of the integer in the `ByteBuffer`.
    ///   - endianness: The endianness of the integer in the `ByteBuffer`.
    /// - Returns: A 24-bit unsigned integer put into a `UInt32` type or `nil` if the bytes are not readable.
    @inlinable
    public func getUInt24(at index: Int, endianness: Endianness = .big) -> UInt32? {
        let mostSignificant: UInt16
        let leastSignificant: UInt8
        switch endianness {
        case .big:
            guard let uint16 = self.getInteger(at: index, endianness: .big, as: UInt16.self),
                  let uint8 = self.getInteger(at: index + 2, endianness: .big, as: UInt8.self) else { return nil }
            mostSignificant = uint16
            leastSignificant = uint8
        case .little:
            guard let uint8 = self.getInteger(at: index, endianness: .little, as: UInt8.self),
                  let uint16 = self.getInteger(at: index + 1, endianness: .little, as: UInt16.self) else { return nil }
            mostSignificant = uint16
            leastSignificant = uint8
        }
        return (UInt32(mostSignificant) << 8) &+ UInt32(leastSignificant)
    }

    /// Read 24-bit unsigned integer and move the reader index forward accordingly.
    ///
    /// - Parameter endianness: The endianness of the integer in the `ByteBuffer`.
    /// - Returns: A 24-bit unsigned integer put into a `UInt32` type or `nil` if the bytes are not readable.
    @inlinable
    public mutating func readUInt24(endianness: Endianness = .big) -> UInt32? {
        guard let integer = getUInt24(at: self.readerIndex, endianness: endianness) else {
            return nil
        }
        self.moveReaderIndex(forwardBy: 3)
        return integer
    }
}


extension ByteBuffer {
    /// The maximum 24-bit integer in a `Int32` type.
    @usableFromInline static let maxInt24 = Int32(bitPattern: 0x007FFFFF)
    /// The minimum 24-bit integer in a `Int32` type.
    @usableFromInline static let minInt24 = Int32(bitPattern: 0xFF800000)

    /// Set 24-bit signed integer at a given index without moving the writer index.
    ///
    /// Note that while the method accepts an `Int32`, the value range is restricted to an `Int24`.
    /// Passing a larger value will result in a runtime crash.
    ///
    /// - Parameters:
    ///   - integer: The integer to write.
    ///   - index: The index of the first byte to write.
    ///   - endianness: The endianness to use for writing.
    /// - Returns: The number of bytes written.
    @inlinable
    @discardableResult
    public mutating func setInt24(_ integer: Int32, at index: Int, endianness: Endianness = .big) -> Int {
        precondition(integer <= Self.maxInt24 && integer >= Self.minInt24, "integer value does not fit into 24 bit integer")

        var bitPattern = UInt32(bitPattern: integer)

        // we verified above that this integer fits into the range, so now just set to most significant byte to zero (2s complement representation of Int32)
        bitPattern &= 0xFF_FF_FF

        return self.setUInt24(bitPattern, at: index, endianness: endianness)
    }

    /// Write 24-bit signed integer and move the writer index forward accordingly.
    ///
    /// Note that while the method accepts an `Int32`, the value range is restricted to an `Int24`.
    /// Passing a larger value will result in a runtime crash.
    ///
    /// - Parameters:
    ///   - integer: The integer to write.
    ///   - endianness: The endianness to use for writing.
    /// - Returns: The number of bytes written.
    @inlinable
    @discardableResult
    public mutating func writeInt24(_ integer: Int32, endianness: Endianness = .big) -> Int {
        let bytesWritten = setInt24(integer, at: self.writerIndex, endianness: endianness)
        self.moveWriterIndex(forwardBy: 3)
        return bytesWritten
    }
}


extension ByteBuffer {
    /// Set 24-bit unsigned integer at a given index without moving the writer index.
    ///
    /// Note that while the method accepts an  `UInt32`, the value range is restricted to an `UInt24`.
    /// Passing a larger value will result in a runtime crash.
    ///
    /// - Parameters:
    ///   - integer: The integer to write.
    ///   - index: The index of the first byte to write.
    ///   - endianness: The endianness to use for writing.
    /// - Returns: The number of bytes written.
    @inlinable
    @discardableResult
    public mutating func setUInt24(_ integer: UInt32, at index: Int, endianness: Endianness = .big) -> Int {
        precondition(integer & 0xFF_FF_FF == integer, "integer value does not fit into 24 bit un-singed integer")
        switch endianness {
        case .little:
            return setInteger(UInt8(integer & 0xFF), at: index, endianness: .little)
                + setInteger(UInt16((integer >> 8) & 0xFF_FF), at: index + 1, endianness: .little)
        case .big:
            return setInteger(UInt16((integer >> 8) & 0xFF_FF), at: index, endianness: .big) +
                setInteger(UInt8(integer & 0xFF), at: index + 2, endianness: .big)
        }
    }

    /// Write 24-bit unsigned integer and move the writer index forward accordingly.
    ///
    /// Note that while the method accepts an `UInt32`, the value range is restricted to an `UInt24`.
    /// Passing a larger value will result in a runtime crash.
    ///
    /// - Parameters:
    ///   - integer: The integer to write.
    ///   - endianness: The endianness to use for writing.
    /// - Returns: The number of bytes written.
    @inlinable
    @discardableResult
    public mutating func writeUInt24(_ integer: UInt32, endianness: Endianness = .big) -> Int {
        let bytesWritten = setUInt24(integer, at: self.writerIndex, endianness: endianness)
        self.moveWriterIndex(forwardBy: 3)
        return bytesWritten
    }
}
