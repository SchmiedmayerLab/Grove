//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
#if canImport(zlib)
public import zlib
#elseif canImport(GroveCZlib)
public import GroveCZlib
#else
#error("No zlib module found. On Linux ensure that you have zlib1g-dev installed.")
#endif

/// A wrapper around the [`zlib`](https://zlib.net/) compression library.
///
/// ## Topics
///
/// ### Operations
/// - ``compress(_:)``
/// - ``compress(_:options:)``
/// - ``decompress(_:)``
///
/// ### Supporting Types
/// - ``CompressionOptions``
/// - ``CompressionError``
/// - ``DecompressionError``
public enum Zlib: CompressionAlgorithm {
    public typealias DecompressionError = CompressionError
    
    public enum CompressionError: Error {
        case invalidInput
        case notEnoughMemory
        case other(Int32)
    }
    
    
    public struct CompressionOptions: CompressionOptionsProtocol {
        /// The compression level.
        ///
        /// ## Topics
        ///
        /// ### Predefined Compression Levels
        /// - ``default``
        /// - ``bestSpeed``
        /// - ``bestCompression``
        /// - ``none``
        ///
        /// ### Initializers
        /// - ``init(rawValue:)``
        ///
        /// ### Instance Properties
        /// - ``rawValue``
        public struct CompressionLevel: RawRepresentable, Sendable {
            /// A level that completely disables compression.
            @inlinable public static var none: Self {
                Self(rawValue: Z_NO_COMPRESSION)
            }
            /// A level that maximises speed, at the cost of compression.
            @inlinable public static var bestSpeed: Self {
                Self(rawValue: Z_BEST_SPEED)
            }
            /// A level that maximises compression, at the cost of speed.
            @inlinable public static var bestCompression: Self {
                Self(rawValue: Z_BEST_COMPRESSION)
            }
            /// The default level, which aims to be a sensible compromise of speed and compression.
            @inlinable public static var `default`: Self {
                Self(rawValue: Z_DEFAULT_COMPRESSION)
            }
            
            /// The compression level's underlying raw value.
            public let rawValue: Int32
            
            /// Creates a new compression level from its underlying raw value.
            @inlinable
            public init(rawValue: Int32) {
                precondition((0...9).contains(rawValue) || rawValue == Z_DEFAULT_COMPRESSION, "invalid compression level \(rawValue)")
                self.rawValue = rawValue
            }
        }
        
        /// The compression level.
        public let level: CompressionLevel
        
        @inlinable
        public init() {
            self.init(level: .default)
        }
        
        /// Creates new compression options.
        @inlinable
        public init(level: CompressionLevel) {
            self.level = level
        }
    }
    
    
    public static func compress(_ bytes: borrowing some Collection<UInt8>, options: CompressionOptions) throws(CompressionError) -> Data {
        let inputLen = bytes.count
        let result: Result<Data, CompressionError>? = bytes.withContiguousStorageIfAvailable { inputBuffer in
            assert(inputBuffer.count == inputLen)
            guard let inputBufferPtr = inputBuffer.baseAddress else {
                return .failure(.invalidInput)
            }
            let outputBufferSize = compressBound(UInt(inputBuffer.count))
            let outputBuffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: Int(outputBufferSize))
            var compressedSize: UInt = outputBufferSize
            let status = compress2(outputBuffer, &compressedSize, inputBufferPtr, UInt(inputBuffer.count), options.level.rawValue)
            switch status {
            case Z_OK:
                return .success(Data(bytesNoCopy: outputBuffer, count: Int(compressedSize), deallocator: .free))
            case Z_MEM_ERROR:
                outputBuffer.deallocate()
                return .failure(.notEnoughMemory)
            case Z_BUF_ERROR:
                // shouldn't happen, since we use compressBound() to determine the expected output buffer size...
                fallthrough // swiftlint:disable:this no_fallthrough_only
            case Z_STREAM_ERROR:
                // should be unreachable, since we only ever pass valid levels (ie, 0-9) into compress2...
                fallthrough // swiftlint:disable:this no_fallthrough_only
            default:
                // should also be unreachable, since the switch above covers all status codes mentioned in the zlib documentation.
                outputBuffer.deallocate()
                return .failure(.other(status))
            }
        }
        if let result {
            return try result.get()
        } else {
            throw .invalidInput
        }
    }
    
    
    public static func decompress(_ bytes: borrowing some Collection<UInt8>) throws(DecompressionError) -> Data {
        try decompress(bytes, expectedOutputLength: bytes.count)
    }
    
    private static func decompress(_ bytes: borrowing some Collection<UInt8>, expectedOutputLength: Int) throws(DecompressionError) -> Data {
        let inputLen = bytes.count
        let result: Result<Data, CompressionError>? = bytes.withContiguousStorageIfAvailable { inputBuffer in
            assert(inputBuffer.count == inputLen)
            guard let inputBufferPtr = inputBuffer.baseAddress else {
                return .failure(.invalidInput)
            }
            let outputBufferSize = UInt(expectedOutputLength)
            let outputBuffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: Int(outputBufferSize))
            var decompressedSize: UInt = outputBufferSize
            let status = uncompress(outputBuffer, &decompressedSize, inputBufferPtr, UInt(inputBuffer.count))
            switch status {
            case Z_OK:
                return .success(Data(bytesNoCopy: outputBuffer, count: Int(decompressedSize), deallocator: .free))
            case Z_MEM_ERROR:
                outputBuffer.deallocate()
                return .failure(.notEnoughMemory)
            case Z_BUF_ERROR:
                // if we end up in here, out output buffer was too small.
                fallthrough // swiftlint:disable:this no_fallthrough_only
            case Z_STREAM_ERROR:
                // should be unreachable, since we only ever pass valid levels (ie, 0-9) into compress2...
                fallthrough // swiftlint:disable:this no_fallthrough_only
            default:
                // should also be unreachable, since the switch above covers all status codes mentioned in the zlib documentation.
                outputBuffer.deallocate()
                return .failure(.other(status))
            }
        }
        guard let result else {
            throw .invalidInput
        }
        do {
            return try result.get()
        } catch DecompressionError.other(Z_BUF_ERROR) {
            return try Self.decompress(bytes, expectedOutputLength: expectedOutputLength + (expectedOutputLength / 2))
        } catch {
            throw error
        }
    }
}
