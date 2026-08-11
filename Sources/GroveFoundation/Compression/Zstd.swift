//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable attributes

public import Foundation
public import libzstd
import ThreadLocal

/// A wrapper around the [`Zstd`](https://github.com/facebook/zstd) compression library.
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
public enum Zstd: CompressionAlgorithm {
    public typealias DecompressionError = CompressionError
    
    public enum CompressionError: Error {
        /// The input sequence didn't have an underlying contiguous storage
        case invalidInput
        case notEnoughMemory
        case other(ZSTD_ErrorCode)
    }
    
    public struct CompressionOptions: CompressionOptionsProtocol {
        /// The compression level.
        ///
        /// ## Topics
        ///
        /// ### Predefined Compression Levels
        /// - ``default``
        /// - ``minRegular``
        /// - ``maxRegular``
        ///
        /// ### Initializers
        /// - ``init(rawValue:)``
        ///
        /// ### Instance Properties
        /// - ``rawValue``
        public struct Level: RawRepresentable, Sendable {
            /// The minimum regular compression level.
            ///
            /// This level maximises speed, at the cost of compression.
            @inlinable public static var minRegular: Self {
                Self(rawValue: 0)
            }
            /// The maximum regular compression level.
            ///
            /// This level maximises compression, at the cost of speed.
            @inlinable public static var maxRegular: Self {
                Self(rawValue: 20)
            }
            
            /// The default compression level
            @inlinable public static var `default`: Self {
                Self(rawValue: ZSTD_CLEVEL_DEFAULT)
            }
            
            /// The compression level's underlying raw value.
            public let rawValue: Int32
            
            /// Creates a compression level from a raw value.
            ///
            /// - Note: This initializer performs no validation of the value. The caller must ensure that it is valid.
            @inlinable
            public init(rawValue: Int32) {
                self.rawValue = rawValue
            }
        }
        
        /// The compression level.
        public let level: Level
        
        @inlinable
        public init() {
            self.init(level: .default)
        }
        
        /// Creates compression options.
        @inlinable
        public init(level: Level) {
            self.level = level
        }
    }
    
    
    /// The compression context
    @ThreadLocal(deallocator: .custom(ZSTD_freeCCtx))
    private static var cCtx: OpaquePointer = ZSTD_createCCtx()
    
    /// The decompression context
    @ThreadLocal(deallocator: .custom(ZSTD_freeDCtx))
    private static var dCtx: OpaquePointer = ZSTD_createDCtx()
    
    
    public static func compress(_ bytes: borrowing some Collection<UInt8>, options: CompressionOptions) throws(CompressionError) -> Data {
        let inputLen = bytes.count
        let result: Result<Data, CompressionError>? = bytes.withContiguousStorageIfAvailable { inputBuffer in
            assert(inputBuffer.count == inputLen)
            guard let inputBufferPtr = inputBuffer.baseAddress else {
                return .failure(.invalidInput)
            }
            let outputBufferSize = ZSTD_compressBound(inputBuffer.count)
            let outputBuffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: outputBufferSize)
            let result = ZSTD_compressCCtx(Self.cCtx, outputBuffer, outputBufferSize, inputBufferPtr, inputLen, options.level.rawValue)
            if ZSTD_isError(result) == 0 {
                return .success(Data(bytesNoCopy: outputBuffer, count: result, deallocator: .free))
            } else {
                switch ZSTD_getErrorCode(result) {
                case ZSTD_error_memory_allocation:
                    return .failure(.notEnoughMemory)
                case let errorCode:
                    return .failure(.other(errorCode))
                }
            }
        }
        guard let result else {
            // the input didn't have a contiguous storage representation
            throw .invalidInput
        }
        return try result.get()
    }
    
    
    public static func decompress(_ bytes: borrowing some Collection<UInt8>) throws(DecompressionError) -> Data {
        let inputLen = bytes.count
        let result: Result<Data, DecompressionError>? = bytes.withContiguousStorageIfAvailable { inputBuffer in
            guard let inputBufferPtr = inputBuffer.baseAddress else {
                return .failure(.invalidInput)
            }
            assert(inputBuffer.count == inputLen)
            switch ZSTD_getFrameContentSize(inputBufferPtr, inputLen) {
            case ZSTD_CONTENTSIZE_ERROR:
                // likely not compressed by Zstd
                return .failure(.invalidInput)
            case ZSTD_CONTENTSIZE_UNKNOWN:
                // could try to use streaming decompression for this at some point in the future
                return .failure(.invalidInput)
            case let contentSize:
                let contentSize = Int(contentSize)
                let outputBuffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: contentSize)
                let result = ZSTD_decompressDCtx(Self.dCtx, outputBuffer, contentSize, inputBufferPtr, inputBuffer.count)
                if ZSTD_isError(result) == 0 {
                    return .success(Data(bytesNoCopy: outputBuffer, count: contentSize, deallocator: .free))
                } else {
                    switch ZSTD_getErrorCode(result) {
                    case ZSTD_error_memory_allocation:
                        return .failure(.notEnoughMemory)
                    case let errorCode:
                        return .failure(.other(errorCode))
                    }
                }
            }
        }
        guard let result else {
            // the input didn't have a contiguous storage representation
            throw .invalidInput
        }
        return try result.get()
    }
}
