//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ByteCoding
public import Foundation
import NIOCore
public import Testing


/// Tests the identity invariant of a `ByteCodable` implementation.
/// 
/// This function encodes a provided value into its byte representation, then
/// decodes it back into the value and asserts its equality using `XCTAssertEqual`.
/// 
/// - Parameters:
///   - value: The value to encode and decode.
///   - sourceLocation: The source location where this check is performed.
/// - Throws: Failed to decode.
public func testIdentity<T: ByteCodable & Equatable>(from value: T, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let data = value.encode()

    var decodingBuffer = ByteBuffer(data: data)

    let instance: T = try #require(T(from: &decodingBuffer), sourceLocation: sourceLocation)

    #expect(instance == value, sourceLocation: sourceLocation)
}


/// Tests the identity invariant of a `ByteCodable` implementation.
///
/// This function decodes the type from the provided byte representation, then
/// encodes it back into its byte representations and asserts its equality using `XCTAssertEqual`.
/// - Parameters:
///   - type: The type to test.
///   - data: The data representation to decode.
///   - sourceLocation: The source location where this check is performed.
/// - Throws: Failed to decode.
public func testIdentity<T: ByteCodable>(of type: T.Type, from data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
    var decodingBuffer = ByteBuffer(data: data)

    let instance: T = try #require(T(from: &decodingBuffer), sourceLocation: sourceLocation)

    var encodingBuffer = ByteBuffer()
    encodingBuffer.reserveCapacity(data.count)

    instance.encode(to: &encodingBuffer)

    let encodingData = Data(buffer: encodingBuffer)
    #expect(encodingData == data, sourceLocation: sourceLocation)
}
