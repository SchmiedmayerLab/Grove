//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ByteCoding
import ByteCodingTesting
import Foundation
import RealModule
@testable import SpeziNumerics
import Testing


@Suite("MedFloat")
struct MedFloatTests { // swiftlint:disable:this type_body_length
    @Test("Special Values")
    func testSpecialValues() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(MedFloat.nan.double.isNaN)
            #expect(MedFloat.nres.double.isNaN)
            #expect(MedFloat.reserved0.double.isNaN)
            #expect(MedFloat.infinity.double == .infinity)
            #expect(MedFloat.negativeInfinity.double == -Double.infinity)
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("Double Conversion")
    func testDoubleConversion() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(MedFloat(.nan).isNaN)
            #expect(MedFloat(.zero).isZero)
            #expect(MedFloat(.infinity) == .infinity)
            #expect(MedFloat(-.infinity) == .negativeInfinity)

            #expect(MedFloat(123000.0) == MedFloat(exponent: 3, mantissa: 123))
            #expect(MedFloat(12.34) == MedFloat(exponent: -2, mantissa: 1234))
            #expect(MedFloat(0.0000012) == MedFloat(exponent: -7, mantissa: 12))

            #expect(MedFloat(1234.0) == MedFloat(exponent: 0, mantissa: 1234))

            #expect(MedFloat(-123000.0) == MedFloat(exponent: 3, mantissa: -123))
            #expect(MedFloat(-12.34) == MedFloat(exponent: -2, mantissa: -1234))
            #expect(MedFloat(-0.0000012) == MedFloat(exponent: -7, mantissa: -12))

            for value in [1.0, 12.34, 1.125] {
                #expect(MedFloat(value).double.isApproximatelyEqual(to: value, absoluteTolerance: MedFloat.precision))
                #expect(SpeziNumerics.MedFloat16(value).double == value)
            }
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
        

        #expect(MedFloat32(52.471).double.isApproximatelyEqual(to: 52.471, absoluteTolerance: MedFloat32.precision))
        #expect(MedFloat16(52.471).double != 52.471)
        #expect(MedFloat16(52.471).double == 52.5)
    }

    @Test("Basic Representations")
    func testBasicRepresentations() { // swiftlint:disable:this function_body_length
        do { // MedFloat16
            let largeFloat = MedFloat16(exponent: 3, mantissa: 123)
            let smallFloat = MedFloat16(exponent: -2, mantissa: 1234)
            let smallSmallFloat = MedFloat16(exponent: -7, mantissa: 12)
            
            let zeroExponentFloat = MedFloat16(exponent: 0, mantissa: 1234)
            
            let negLargeFloat = MedFloat16(exponent: 3, mantissa: -123)
            let negSmallFloat = MedFloat16(exponent: -2, mantissa: -1234)
            let negSmallSmallFloat = MedFloat16(exponent: -7, mantissa: -12)
            
            #expect(largeFloat.exponent == 2)
            #expect(largeFloat.mantissa == 1230)
            #expect(smallFloat.exponent == -2)
            #expect(smallFloat.mantissa == 1234)
            #expect(smallSmallFloat.exponent == -8)
            #expect(smallSmallFloat.mantissa == 120)

            #expect(zeroExponentFloat.exponent == 0)
            #expect(zeroExponentFloat.mantissa == 1234)

            #expect(negLargeFloat.exponent == 2)
            #expect(negLargeFloat.mantissa == -1230)
            #expect(negSmallFloat.exponent == -2)
            #expect(negSmallFloat.mantissa == -1234)
            #expect(negSmallSmallFloat.exponent == -8)
            #expect(negSmallSmallFloat.mantissa == -120)

            #expect(largeFloat.isFinite)
            #expect(smallFloat.isFinite)
            #expect(smallSmallFloat.isFinite)
            #expect(negLargeFloat.isFinite)
            #expect(negSmallFloat.isFinite)
            #expect(negSmallSmallFloat.isFinite)
            
            #expect(largeFloat.double == 123000.0)
            #expect(smallFloat.double == 12.34)
            #expect(smallSmallFloat.double == 0.0000012)
            #expect(zeroExponentFloat.double == 1234.0)
            #expect(negLargeFloat.double == -123000.0)
            #expect(negSmallFloat.double == -12.34)
            #expect(negSmallSmallFloat.double == -0.0000012)

            
            #expect(MedFloat16.nan.description == "nan")
            #expect(MedFloat16.reserved0.description == "nan")
            #expect(MedFloat16.nres.description == "nres")
            #expect(MedFloat16.zero.description == "0.0")
            #expect(MedFloat16.infinity.description == "inf")
            #expect(MedFloat16.negativeInfinity.description == "-inf")

            #expect(largeFloat.description == "123000.0")
            #expect(smallFloat.description == "12.34")
            #expect(smallSmallFloat.description == "0.0000012")
            #expect(zeroExponentFloat.description == "1234.0")
            #expect(negLargeFloat.description == "-123000.0")
            #expect(negSmallFloat.description == "-12.34")
            #expect(negSmallSmallFloat.description == "-0.0000012")

            #expect(MedFloat16(127).description == "127.0")
            #expect(MedFloat16(12).description == "12.0")
        }
        
        
        do { // MedFloat32
            let largeFloat = MedFloat32(exponent: 3, mantissa: 123)
            let smallFloat = MedFloat32(exponent: -2, mantissa: 1234)
            let smallSmallFloat = MedFloat32(exponent: -7, mantissa: 12)
            
            let zeroExponentFloat = MedFloat32(exponent: 0, mantissa: 1234)
            
            let negLargeFloat = MedFloat32(exponent: 3, mantissa: -123)
            let negSmallFloat = MedFloat32(exponent: -2, mantissa: -1234)
            let negSmallSmallFloat = MedFloat32(exponent: -7, mantissa: -12)
            
            #expect(largeFloat.exponent == -1)
            #expect(largeFloat.mantissa == 1230000)
            #expect(smallFloat.exponent == -5)
            #expect(smallFloat.mantissa == 1234000)
            #expect(smallSmallFloat.exponent == -12)
            #expect(smallSmallFloat.mantissa == 1200000)

            #expect(zeroExponentFloat.exponent == -3)
            #expect(zeroExponentFloat.mantissa == 1234000)

            #expect(negLargeFloat.exponent == -1)
            #expect(negLargeFloat.mantissa == -1230000)
            #expect(negSmallFloat.exponent == -5)
            #expect(negSmallFloat.mantissa == -1234000)
            #expect(negSmallSmallFloat.exponent == -12)
            #expect(negSmallSmallFloat.mantissa == -1200000)

            #expect(largeFloat.isFinite)
            #expect(smallFloat.isFinite)
            #expect(smallSmallFloat.isFinite)
            #expect(negLargeFloat.isFinite)
            #expect(negSmallFloat.isFinite)
            #expect(negSmallSmallFloat.isFinite)
            
            #expect(largeFloat.double == 123000.0)
            #expect(smallFloat.double.isApproximatelyEqual(to: 12.34, absoluteTolerance: MedFloat32.precision))
            #expect(smallSmallFloat.double == 0.0000012)
            #expect(zeroExponentFloat.double == 1234.0)
            #expect(negLargeFloat.double == -123000.0)
            #expect(negSmallFloat.double.isApproximatelyEqual(to: -12.34, absoluteTolerance: MedFloat32.precision))
            #expect(negSmallSmallFloat.double == -0.0000012)

            
            #expect(MedFloat32.nan.description == "nan")
            #expect(MedFloat32.reserved0.description == "nan")
            #expect(MedFloat32.nres.description == "nres")
            #expect(MedFloat32.zero.description == "0.0")
            #expect(MedFloat32.infinity.description == "inf")
            #expect(MedFloat32.negativeInfinity.description == "-inf")

            #expect(largeFloat.description == "123000.0")
            #expect(smallFloat.description == "12.34")
            #expect(smallSmallFloat.description == "0.0000012")
            #expect(zeroExponentFloat.description == "1234.0")
            #expect(negLargeFloat.description == "-123000.0")
            #expect(negSmallFloat.description == "-12.34")
            #expect(negSmallSmallFloat.description == "-0.0000012")

            #expect(MedFloat32(127).description == "127.0")
            #expect(MedFloat32(12).description == "12.0")
        }
        
        
        #expect(MedFloat16(exponent: 45, mantissa: 23) == .infinity)
        #expect(MedFloat16(exponent: 2, mantissa: 23000) == .infinity)
        #expect(MedFloat16(exponent: 2, mantissa: -23000) == .negativeInfinity)
        #expect(MedFloat16(exponent: -2, mantissa: 6500) == .infinity)
        #expect(MedFloat16(exponent: -9, mantissa: 650) == .infinity)
        #expect(MedFloat16(exponent: -2, mantissa: -6500) == .negativeInfinity)
        #expect(MedFloat16(exponent: -9, mantissa: -650) == .negativeInfinity)

        let largeDoubleVal: Double = 23000000000000000000000000000000000000000000000.0
        #expect(MedFloat32(exponent: 45, mantissa: 23).double == largeDoubleVal)
        #expect(MedFloat32(largeDoubleVal).double == largeDoubleVal)
        #expect(MedFloat32(exponent: 2, mantissa: 23000) == 2300000)
        #expect(MedFloat32(exponent: 2, mantissa: -23000) == -2300000)
        #expect(MedFloat32(exponent: -2, mantissa: 6500) == 65.0)
        #expect(MedFloat32(exponent: -9, mantissa: 650) == 0.00000065)
        #expect(MedFloat32(exponent: -2, mantissa: -6500) == -65)
        #expect(MedFloat32(exponent: -9, mantissa: -650) == -0.00000065)

        #expect(MedFloat32(exponent: 127, mantissa: 500000000) == .infinity)
        #expect(MedFloat32(exponent: 2, mantissa: 500000000) == .infinity)
        #expect(MedFloat32(exponent: 2, mantissa: -500000000) == .negativeInfinity)
        #expect(MedFloat32(exponent: -2, mantissa: 65000000) == .infinity)
        #expect(MedFloat32(exponent: -9, mantissa: 65000000) == .infinity)
        #expect(MedFloat32(exponent: -2, mantissa: -65000000) == .negativeInfinity)
        #expect(MedFloat32(exponent: -9, mantissa: -65000000) == .negativeInfinity)
    }


    @Test("Hashable")
    func testHashable() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            var values: Set<MedFloat> = []
            
            #expect(values.insert(.nan).inserted)
            #expect(values.insert(.nan).inserted)
            #expect(values.insert(.zero).inserted)
            #expect(values.insert(MedFloat(exponent: -2, mantissa: 0)).inserted != true)
            #expect(values.insert(2).inserted)
            #expect(values.insert(4).inserted)
            #expect(values.insert(4).inserted != true)
            #expect(values.insert(.nres).inserted)
            #expect(values.insert(.nres).inserted)
            #expect(values.insert(.reserved0).inserted)
            #expect(values.insert(.reserved0).inserted)

            // swiftlint:disable identical_operands
            #expect(MedFloat.nan.hashValue == MedFloat.nan.hashValue)
            #expect(MedFloat.nres.hashValue == MedFloat.nres.hashValue)
            #expect(MedFloat.reserved0.hashValue == MedFloat.reserved0.hashValue)
            // swiftlint:enable identical_operands
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("Equality")
    func testEquality() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(MedFloat.nan != .nan)
            #expect(MedFloat.nan != .nres)
            #expect(MedFloat.nan != .infinity)
            #expect(MedFloat.nan != MedFloat(123))
            #expect(MedFloat.nres != .nres)

            
            let float0 = MedFloat(exponent: -1, mantissa: 130)
            let float1 = MedFloat(exponent: 0, mantissa: 13)
            let float2 = MedFloat(exponent: -2, mantissa: 1300)
            
            #expect(float0 == float1)
            #expect(float0 == float2)
            #expect(float1 == float2)
            #expect(float0.description == float1.description)
            #expect(float1.description == float2.description)

            let float3 = MedFloat(exponent: 1, mantissa: 10)
            let float4 = MedFloat(exponent: 0, mantissa: 100)
            
            #expect(float3 == float4)
            #expect(MedFloat.zero == MedFloat(exponent: 3, mantissa: 0))
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("Comparable")
    func testComparable() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(!(MedFloat.nan < .nan))
            #expect(!(MedFloat.nan < .nan))
            #expect(!(MedFloat.nan < .nres))
            #expect(!(MedFloat.nan < .reserved0))
            #expect(!(MedFloat.nres < .nres))
            #expect(!(MedFloat.nres < .nan))
            #expect(!(MedFloat.nres < .reserved0))
            #expect(!(MedFloat.reserved0 < .reserved0))
            #expect(!(MedFloat.reserved0 < .nan))
            #expect(!(MedFloat.reserved0 < .nres))

            #expect(!(MedFloat.negativeInfinity < .negativeInfinity))
            #expect(!(MedFloat.negativeInfinity < .nan))
            #expect(!(-503 < MedFloat.negativeInfinity))
            #expect(!(.nan < MedFloat.negativeInfinity))
            #expect(MedFloat.negativeInfinity < -503)
            #expect(MedFloat.negativeInfinity < .infinity)

            #expect(!(MedFloat.infinity < 1234012))
            #expect(!(MedFloat.infinity < .nan))
            #expect(!(MedFloat.infinity < .infinity))
            #expect(!(.nan < MedFloat.infinity))
            #expect(123123 < .infinity)

            #expect(!(MedFloat.zero < MedFloat(exponent: 3, mantissa: 0)))
            #expect(MedFloat(-3) < 0)
            #expect(MedFloat(-3) < 4)
            #expect(MedFloat.zero < 4)
            #expect(MedFloat(0.578) < 4)
            #expect(MedFloat(0.578) < 4)
            #expect(MedFloat(-0.578) < 4)

            #expect(MedFloat(-7.58) < -0.78)
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("Literal inits")
    func testLiteralInits() {
        #expect(MedFloat16(150000000000) == .infinity)
        #expect(MedFloat16(-150000000000) == .negativeInfinity)
    }


    @Test("Exactly Conversion")
    func testExactlyConversion() {
        #expect(MedFloat16(exactly: Int16.max) == nil)
        #expect(MedFloat16(exactly: UInt16.max) == nil)
        #expect(MedFloat32(exactly: Int16.max) != nil)
        #expect(MedFloat32(exactly: UInt16.max) != nil)

        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(MedFloat(exactly: UInt8.max) == 255)
            #expect(MedFloat(exactly: Int8.max) == 127)
            #expect(MedFloat(exactly: 12400) == 12400)

            #expect(MedFloat(exactly: Int32.max) == nil)
            #expect(MedFloat(exactly: UInt32.max) == nil)
            #expect(MedFloat(exactly: Int64.max) == nil)
            #expect(MedFloat(exactly: UInt64.max) == nil)
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("Addition")
    func testAddition() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect((MedFloat.infinity + .negativeInfinity).isNaN)
            #expect((MedFloat.negativeInfinity + .infinity).isNaN)
            
            #expect((MedFloat.nan + .nan).isNaN)
            #expect((MedFloat.nres + .nres).isNaN)
            #expect((MedFloat.nan + .nres).isNaN)
            #expect((MedFloat.nres + .nan).isNaN)
            #expect((MedFloat.reserved0 + .nan).isNaN)
            #expect((MedFloat.nan + .reserved0).isNaN)
            #expect((MedFloat.nres + .reserved0).isNaN)
            #expect((MedFloat.reserved0 + .nres).isNaN)
            
            #expect(MedFloat.infinity + .infinity == .infinity)
            #expect(MedFloat.infinity + 12 == .infinity)
            #expect(MedFloat.infinity + -12 == .infinity)

            #expect(MedFloat.negativeInfinity + .negativeInfinity == .negativeInfinity)
            #expect(MedFloat.negativeInfinity + 12 == .negativeInfinity)
            #expect(MedFloat.negativeInfinity + -12 == .negativeInfinity)

            
            #expect(MedFloat(15) + 12 == 27)
            #expect(MedFloat(1500000000) + 1200000000 == 2700000000)
            #expect(MedFloat(15000000) + 120000 == 15120000)
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
        
        #expect(MedFloat16(15000000000) + 12000000000 == .infinity)
        #expect(MedFloat32(15000000000) + 12000000000 == 27000000000)

        #expect(MedFloat32(MedFloat32.maxDoubleValue) != .infinity)
        #expect(MedFloat32(MedFloat32.maxDoubleValue.nextUp) == .infinity)
        let step = MedFloat32.maxDoubleValue.nextUp - MedFloat32.maxDoubleValue
        #expect((MedFloat32(MedFloat32.maxDoubleValue) + MedFloat32(step)).double == .infinity)
    }

    @Test("Negate")
    func testNegate() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(-MedFloat.negativeInfinity == .infinity)
            #expect(-MedFloat.infinity == .negativeInfinity)
            #expect((-MedFloat.nan).isNaN)
            #expect((-MedFloat.nres).isNRes)
            #expect(MedFloat(4) == 4)
            #expect(MedFloat(-4) == -4)
            #expect(MedFloat(-4.128) == -4.128)
            #expect(-MedFloat(4) == -4)
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("Multiply")
    func testMultiply() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            var value: MedFloat = 2
            
            value *= 10
            #expect(value == 20)

            value *= (0.25 as MedFloat)
            #expect(value == 5)
        }
    }

    @Test("Magnitude")
    func testMagnitude() {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) {
            #expect(MedFloat.nan.magnitude.isNaN)
            #expect(MedFloat.nres.magnitude.isNRes)
            #expect(MedFloat.reserved0.magnitude.isReserved0)
            
            #expect(MedFloat.infinity.magnitude == .infinity)
            #expect(MedFloat.negativeInfinity.magnitude == .infinity)

            #expect(MedFloat.zero.magnitude == .zero)

            #expect(MedFloat(12.5).magnitude == 12.5)
            #expect(MedFloat(-12.5).magnitude == 12.5)
        }
        imp(MedFloat16.self)
        imp(MedFloat32.self)
    }

    @Test("ByteCodable")
    func testByteCoding() throws {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) throws {
            try testIdentity(from: MedFloat.infinity)
            try testIdentity(from: MedFloat.negativeInfinity)
            try testIdentity(from: MedFloat.zero)
            try testIdentity(from: MedFloat(12.5))
            try testIdentity(from: MedFloat(-12.5))
        }
        try imp(MedFloat16.self)
        try imp(MedFloat32.self)
        
        // nan-like values don't compare, therefore we check for byte-wise equality
        try testIdentity(of: MedFloat16.self, from: #require(Data(hex: "0x07FF")))
        try testIdentity(of: MedFloat16.self, from: #require(Data(hex: "0x0800")))
        try testIdentity(of: MedFloat16.self, from: #require(Data(hex: "0x0801")))
        try testIdentity(of: MedFloat32.self, from: #require(Data(hex: "0x007FFFFF")))
        try testIdentity(of: MedFloat32.self, from: #require(Data(hex: "0x00800000")))
        try testIdentity(of: MedFloat32.self, from: #require(Data(hex: "0x00800001")))
    }

    @Test("Codable")
    func testCodable() throws {
        func imp<MedFloat: MedFloatProtocol>(_: MedFloat.Type) throws {
            func testCodableReturningResult<T: Codable & Equatable>(from value: T) throws -> T {
                let encoder = JSONEncoder()
                let decoder = JSONDecoder()
                
                let data = try encoder.encode(value)
                return try decoder.decode(T.self, from: data)
            }
            func testCodable<T: Codable & Equatable>(from value: T) throws {
                let result = try testCodableReturningResult(from: value)
                #expect(result == value)
            }
            
            try testCodable(from: MedFloat.infinity)
            try testCodable(from: MedFloat.negativeInfinity)
            try testCodable(from: MedFloat.zero)
            try testCodable(from: MedFloat(12.5))
            try testCodable(from: MedFloat(-12.5))
            
            // nan-like values don't compare, therefore we check for byte-wise equality
            #expect(try testCodableReturningResult(from: MedFloat.nan).bitPattern == MedFloat.nan.bitPattern)
            #expect(try testCodableReturningResult(from: MedFloat.nres).bitPattern == MedFloat.nres.bitPattern)
            #expect(try testCodableReturningResult(from: MedFloat.reserved0).bitPattern == MedFloat.reserved0.bitPattern)
        }
        try imp(MedFloat16.self)
        try imp(MedFloat32.self)
    }
}
