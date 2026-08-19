//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A type that supports encoding.
public protocol TopLevelEncoder<Output> {
    /// The output type.
    associatedtype Output

    /// Encode a value.
    /// - Parameter value: The value to encode.
    /// - Returns: The encoded instance.
    /// - Throws: Throws errors occurred while attempting to encode the value.
    func encode<T: Encodable>(_ value: T) throws -> Output

    /// Encode a value.
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - configuration: The configuration that provides additional information for encoding.
    /// - Returns: The encoded instance.
    /// - Throws: Throws errors occurred while attempting to encode the value.
    func encode<T: EncodableWithConfiguration>(_ value: T, configuration: T.EncodingConfiguration) throws -> Output

    /// Encode a value.
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - configuration: A type that provides additional information for encoding.
    /// - Returns: The encoded instance.
    /// - Throws: Throws errors occurred while attempting to encode the value.
    func encode<T: EncodableWithConfiguration, C: EncodingConfigurationProviding>(
        _ value: T,
        configuration: C.Type
    ) throws -> Output where T.EncodingConfiguration == C.EncodingConfiguration
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension JSONEncoder: TopLevelEncoder {}
@available(iOS 18, macOS 15, watchOS 11, *)
extension PropertyListEncoder: TopLevelEncoder {}
