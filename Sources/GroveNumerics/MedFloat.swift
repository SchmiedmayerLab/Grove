//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import ByteCoding


/// Medical 16-bit float representation using base 10.
///
/// The `MedFloat16` (or ISO/IEEE 11073 SFLOAT-Type) is a 16-bit value that uses a 4-bit signed exponent to base 10 and a 12-bit signed mantissa.
/// It can be used to accurately store decimal digits of base 10 decimal integers.
///
/// The value of the `MedFloat16` can be calculated using the the following formula, where `**` denotes exponentiation:
///
///     x.mantissa * (10 ** x.exponent)
public struct MedFloat16: MedFloatProtocol {
    public typealias BitPattern = UInt16
    public typealias Exponent = Int8
    public typealias Mantissa = Int16
    
    public static var exponentBitWidth: Int { 4 }
    public static var mantissaBitWidth: Int { 12 }
    
    public let bitPattern: UInt16
    
    public init(bitPattern: UInt16) {
        self.bitPattern = bitPattern
    }
}


/// Medical 32-bit float representation using base 10.
///
/// The `MedFloat32` (or ISO/IEEE 11073 FLOAT-Type) is a 32-bit value that uses an 8-bit signed exponent to base 10 and a 24-bit signed mantissa.
/// It can be used to accurately store decimal digits of base 10 decimal integers.
///
/// The value of the `MedFloat32` can be calculated using the the following formula, where `**` denotes exponentiation:
///
///     x.mantissa * (10 ** x.exponent)
public struct MedFloat32: MedFloatProtocol {
    public typealias BitPattern = UInt32
    public typealias Exponent = Int8
    public typealias Mantissa = Int32
    
    public static var exponentBitWidth: Int { 8 }
    public static var mantissaBitWidth: Int { 24 }
    
    public let bitPattern: UInt32
    
    public init(bitPattern: UInt32) {
        self.bitPattern = bitPattern
    }
}

// swiftlint:enable file_types_order
