//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import ByteCoding
import Foundation
public import NIO


/// A description of a signal.
///
/// This describes the signal of a single channel.
public struct Signal {
    /// The label of the signal.
    ///
    /// Provides a description of the signal.
    public let label: SignalLabel


    /// Transducer type description.
    ///
    /// 80 Byte string describing the transducer description.
    ///
    /// For example, "active electrode` or "respiration belt".
    public let transducerType: String
    /// Description of the applied filtering.
    ///
    /// 80 Byte string describing the transducer description.
    ///
    /// For example, "HP:0,16; LP:500" (HP for high-pass and LP for low-pass).
    public let prefiltering: String

    /// The amount of samples each data record contains for this signal.
    public var sampleCount: Int

    /// Physical minimum in units of physical dimension.
    public let physicalMinimum: Int
    /// Physical maximum in units of physical dimension.
    public let physicalMaximum: Int
    /// The digital minimum.
    public let digitalMinimum: Int
    /// The digital maximum.
    public let digitalMaximum: Int

    /// 32 bytes of reserved area.
    public let reserved: String


    /// Create a new signal description.
    /// - Parameters:
    ///   - label: The label of the signal.
    ///   - transducerType: The transducer type.
    ///   - prefiltering: Description of the applied filtering.
    ///   - sampleCount: The amount of samples each data record contains for this signal.
    ///   - physicalMinimum: Physical minimum in units of physical dimension.
    ///   - physicalMaximum: Physical maximum in units of physical dimension.
    ///   - digitalMinimum: The digital minimum.
    ///   - digitalMaximum: The digital maximum.
    ///   - reserved: 32 bytes of reserved area.
    public init(
        label: SignalLabel,
        transducerType: String? = nil,
        prefiltering: String? = nil,
        sampleCount: Int,
        physicalMinimum: Int,
        physicalMaximum: Int,
        digitalMinimum: Int,
        digitalMaximum: Int,
        reserved: String? = nil
    ) {
        self.label = label
        self.transducerType = transducerType ?? ""
        self.prefiltering = prefiltering ?? ""
        self.sampleCount = sampleCount
        self.physicalMinimum = physicalMinimum
        self.physicalMaximum = physicalMaximum
        self.digitalMinimum = digitalMinimum
        self.digitalMaximum = digitalMaximum
        self.reserved = reserved ?? ""
    }
}


extension Signal: Hashable, Sendable {}


extension Signal {
    func verifyAsciiInputs() throws {
        try verifyAsciiInput(label.rawValue, maxLength: 16, for: "signal.label")
        try verifyAsciiInput(transducerType, maxLength: 80, for: "signal.transducerType")
        try verifyAsciiInput(label.dimension, maxLength: 8, for: "signal.dimension")

        try verifyAsciiInput(physicalMinimum, maxLength: 8, for: "signal.physicalMinimum")
        try verifyAsciiInput(physicalMaximum, maxLength: 8, for: "signal.physicalMaximum")
        try verifyAsciiInput(digitalMinimum, maxLength: 8, for: "signal.digitalMinimum")
        try verifyAsciiInput(digitalMaximum, maxLength: 8, for: "signal.digitalMaximum")

        try verifyAsciiInput(prefiltering, maxLength: 80, for: "signal.prefiltering")
        try verifyAsciiInput(sampleCount, maxLength: 8, for: "signal.sampleCount")

        try verifyAsciiInput(reserved, maxLength: 32, for: "signal.reserved")
    }
}


extension Swift.Array: ByteCoding.ByteEncodable where Element == Signal {
    public func encode(to byteBuffer: inout ByteBuffer) {
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.label.rawValue, length: 16)
        }
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.transducerType, length: 80)
        }
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.label.dimension, length: 8)
        }

        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.physicalMinimum, length: 8)
        }
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.physicalMaximum, length: 8)
        }
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.digitalMinimum, length: 8)
        }
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.digitalMaximum, length: 8)
        }

        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.prefiltering, length: 80)
        }
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.sampleCount, length: 8)
        }
        
        for header in self {
            byteBuffer.writeEDFAsciiTrimming(header.reserved, length: 32)
        }
    }
}
