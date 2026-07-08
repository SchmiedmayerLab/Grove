//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A type that supports decoding.
public protocol TopLevelDecoder<Input> {
    /// The input type.
    associatedtype Input


    /// Decode a instance for the specified type.
    /// - Parameters:
    ///   - type: The type you want to decode.
    ///   - input: The input you want to decode from.
    /// - Returns: Returns the decoded instance.
    /// - Throws: Throws errors occurred while attempting to decode input.
    func decode<T: Decodable>(_ type: T.Type, from input: Input) throws -> T

    /// Decode a instance for the specified type that requires additional configuration.
    /// - Parameters:
    ///   - type: The type you want to decode.
    ///   - input: The input you want to decode from.
    ///   - configuration: The configuration that provides additional information for decoding.
    /// - Returns: Returns the decoded instance.
    /// - Throws: Throws errors occurred while attempting to decode input.
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
    func decode<T: DecodableWithConfiguration>(
        _ type: T.Type,
        from input: Input,
        configuration: T.DecodingConfiguration
    ) throws -> T

    /// Decode a instance for the specified type that requires additional configuration.
    /// - Parameters:
    ///   - type: The type you want to decode.
    ///   - input: The input you want to decode from.
    ///   - configuration: A type that provides additional information for decoding.
    /// - Returns: Returns the decoded instance.
    /// - Throws: Throws errors occurred while attempting to decode input.
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
    func decode<T: DecodableWithConfiguration, C: DecodingConfigurationProviding>(
        _ type: T.Type,
        from input: Input,
        configuration: C.Type
    ) throws -> T where T.DecodingConfiguration == C.DecodingConfiguration
}


extension JSONDecoder: TopLevelDecoder {}
extension PropertyListDecoder: TopLevelDecoder {}
