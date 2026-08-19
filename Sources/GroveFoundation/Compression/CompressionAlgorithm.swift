//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Options to control a compression operation.
public protocol CompressionOptionsProtocol: Sendable {
    /// Default compression options.
    @inlinable
    init()
}


/// A compression algorithm.
///
/// ## Topics
///
/// ### Compressing Data
/// - ``compress(_:)``
/// - ``compress(_:options:)``
///
/// ### Decompressing Data
/// - ``decompress(_:)``
///
/// ### Associated Types
/// - ``CompressionOptions``
/// - ``CompressionError``
/// - ``DecompressionError``
///
/// ### Supporting Types
/// - ``CompressionOptionsProtocol``
public protocol CompressionAlgorithm {
    /// An error that can occur when compressing an input.
    associatedtype CompressionError: Swift.Error
    /// An error that can occur when decompressing an input.
    associatedtype DecompressionError: Swift.Error
    /// Options to control the compression operation.
    associatedtype CompressionOptions: CompressionOptionsProtocol
    
    /// Compresses the inputtt.
    ///
    /// - parameter bytes: The input which should be compressed.
    /// - parameter options: The compression options that should be used.
    static func compress(_ bytes: borrowing some Collection<UInt8>, options: CompressionOptions) throws(CompressionError) -> Data
    
    /// Decompresses the input.
    static func decompress(_ bytes: borrowing some Collection<UInt8>) throws(DecompressionError) -> Data
}


extension CompressionAlgorithm {
    /// Compresses the input, using default options.
    ///
    /// - parameter bytes: The input which should be compressed.
    @inlinable
    public static func compress(_ bytes: borrowing some Collection<UInt8>) throws(CompressionError) -> Data {
        try compress(bytes, options: .init())
    }
}


extension Collection<UInt8> {
    /// Compresses the collection of bytes using the specified ``CompressionAlgorithm``
    ///
    /// - parameter algorithm: The compression algorithm that should be used to compress the data.
    /// - parameter options: Compression options.
    @inlinable
    public func compressed<Algorithm: CompressionAlgorithm>(
        using algorithm: Algorithm.Type,
        options: Algorithm.CompressionOptions = .init()
    ) throws(Algorithm.CompressionError) -> Data {
        try algorithm.compress(self, options: options)
    }
    
    /// Decompresses the collection of bytes using the specified ``CompressionAlgorithm``
    @inlinable
    public func decompressed<Algorithm: CompressionAlgorithm>(
        using algorithm: Algorithm.Type
    ) throws(Algorithm.DecompressionError) -> Data {
        try algorithm.decompress(self)
    }
}
