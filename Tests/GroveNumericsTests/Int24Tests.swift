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
@testable import GroveNumerics
import NIOCore
import Testing


@Suite("Int24")
struct Int24Tests {
    @Test("Read UInt24 Big Endian")
    func testReadInt24Big() throws {
        let data = try #require(Data(hex: "0xFF0000"))
        var buffer = ByteBuffer(data: data)

        let uint = try #require(buffer.getUInt24(at: 0, endianness: .big))
        let int = try #require({ buffer.readInt24(endianness: .big) }())

        #expect(uint == 0xFF0000)
        #expect(int == -65536)
    }

    @Test("Read UInt24 Little Endian")
    func testReadInt24Little() throws {
        let data = try #require(Data(hex: "0x0000FF"))
        var buffer = ByteBuffer(data: data)

        let uint = try #require({ buffer.readUInt24(endianness: .little) }())
        buffer.moveReaderIndex(to: 0)
        let int = try #require({ buffer.readInt24(endianness: .little) }())

        #expect(uint == 0xFF0000)
        #expect(int == -65536)
    }

    @Test("Read Int24")
    func testReadInt24Reading() throws {
        let data = try #require(Data(hex: "0x6fffff"))
        let buffer = ByteBuffer(data: data)

        let intBE = try #require(buffer.getInt24(at: 0, endianness: .big))
        let intLE = try #require(buffer.getInt24(at: 0, endianness: .little))

        #expect(intBE == 7340031)
        #expect(intLE == -145)
    }

    @Test("Write Int24 Little Endian")
    func testInt24WriteLE() {
        var buffer = ByteBuffer()

        buffer.writeInt24(-65536, endianness: .little)
        buffer.writeInt24(-8_388_608, endianness: .little)
        buffer.writeInt24(7340031, endianness: .little)

        let data = buffer.getData(at: 0, length: buffer.readableBytes)
        #expect(data?.hexString().uppercased() == "0000FF" + "000080" + "FFFF6F")
    }

    @Test("Write Int24 Big Endian")
    func testInt24WriteBE() throws {
        var buffer = ByteBuffer()

        buffer.writeInt24(-65536, endianness: .big)
        buffer.writeInt24(-8_388_608, endianness: .big)
        buffer.writeInt24(7340031, endianness: .big)

        let data = try #require(buffer.getData(at: 0, length: buffer.readableBytes))
        #expect(data.hexString().uppercased() == "FF0000" + "800000" + "6FFFFF")
    }

    @Test("Write UInt24")
    func testUint24Write() throws {
        var buffer = ByteBuffer()

        buffer.writeUInt24(256, endianness: .big)
        buffer.writeUInt24(512, endianness: .little)

        let data = try #require(buffer.getData(at: 0, length: buffer.readableBytes))
        #expect(data.hexString().uppercased() == "000100" + "000200")
    }
}
