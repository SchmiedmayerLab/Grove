//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import ByteCoding
import ByteCodingTesting
import Foundation
import NIOCore
import Testing


@Suite("ByteCodable")
struct ByteCodableTests {
    @available(*, deprecated, message: "Forward deprecation warning.")
    @Test("Deprecated Types")
    func testDeprecatedTypes() throws {
        // ensure that preferredEndianness is still forwarded to Primitive ByteCodable protocols and isn't just ignored

        let data = try #require(Data(hex: "0x0D05"))
        var buffer = ByteBuffer(data: data)

        let value = try #require(UInt16(data: data, preferredEndianness: .big))
        let value0 = try #require(UInt16(from: &buffer, preferredEndianness: .big))
        #expect(value == 3333)
        #expect(value0 == 3333)

        buffer = ByteBuffer()

        let data0 = value.encode(preferredEndianness: .big)
        value0.encode(to: &buffer, preferredEndianness: .big)
        #expect(data0 == data)
        #expect(buffer.getData(at: 0, length: buffer.readableBytes) == data)
    }

    @Test("Ambiguous Data")
    func testAmbiguousData() throws {
        // basically just a test if it compiles

        // PRIMITIVE BYTE CODABLE
        let data = try #require(Data(hex: "0x050D"))
        let value = UInt16(data: data)

        #expect(value == 3333)

        // BYTE CODABLE
        let stringData = Data("Hello World".utf8)
        let stringValue = try #require(String(data: stringData))
        #expect(stringValue == "Hello World")
    }

    @Test("Data")
    func testData() throws {
        let data = try #require(Data(hex: "0xAABBCCDDEE"))

        try testIdentity(of: Data.self, from: data)

        let data0 = Data(data: data)
        #expect(data0 == data)
    }

    @Test("Bool")
    func testBoolean() throws {
        let trueData = try #require(Data(hex: "0x01"))
        try testIdentity(of: Bool.self, from: trueData)

        let falseData = try #require(Data(hex: "0x00"))
        try testIdentity(of: Bool.self, from: falseData)

        var empty = ByteBuffer()
        #expect(Bool(from: &empty) == nil)
    }

    @Test("String")
    func testString() throws {
        let data = Data("Hello World".utf8)
        try testIdentity(of: String.self, from: data)

        var empty = ByteBuffer()
        let string = try #require(String(from: &empty))
        #expect(string.isEmpty)
    }

    @Test("Int8")
    func testInt8() throws {
        try testIdentity(from: Int8.max)
        try testIdentity(from: Int8.min)
    }

    @Test("Int16")
    func testInt16() throws {
        try testIdentity(from: Int16.max)
        try testIdentity(from: Int16.min)
    }

    @Test("Int32")
    func testInt32() throws {
        try testIdentity(from: Int32.max)
        try testIdentity(from: Int32.min)
    }

    @Test("Int64")
    func testInt64() throws {
        try testIdentity(from: Int64.max)
        try testIdentity(from: Int64.min)
    }

    @Test("UInt8")
    func testUInt8() throws {
        try testIdentity(from: UInt8.max)
        try testIdentity(from: UInt8.min)

        var empty = ByteBuffer()
        #expect(UInt8(from: &empty) == nil)
    }

    @Test("UInt16")
    func testUInt16() throws {
        try testIdentity(from: UInt16.max)
        try testIdentity(from: UInt16.min)
    }

    @Test("UInt32")
    func testUInt32() throws {
        try testIdentity(from: UInt32.max)
        try testIdentity(from: UInt32.min)
    }

    @Test("UInt64")
    func testUInt64() throws {
        try testIdentity(from: UInt64.max)
        try testIdentity(from: UInt64.min)
    }

    @Test("Float32")
    func testFloat32() throws {
        try testIdentity(from: Float32.pi)
        try testIdentity(from: Float32.infinity)
        try testIdentity(from: Float32(17.2783912))
    }

    @Test("Float64")
    func testFloat64() throws {
        try testIdentity(from: Float64.pi)
        try testIdentity(from: Float64.infinity)
        try testIdentity(from: Float64(23712.2123123))
    }
}
