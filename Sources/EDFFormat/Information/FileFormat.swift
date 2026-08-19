//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ByteCoding
public import NIO


/// The file format.
public enum FileFormat: String {
    /// European Data Format
    ///
    /// 16-bit signals.
    case edf
    /// BioSemi Data Format.
    ///
    /// 24-bit signals.
    case bdf


    var bdfReservedField: String {
        switch self {
        case .edf:
            "BIOSEMI"
        case .bdf:
            "24BIT"
        }
    }
}


extension FileFormat: Hashable, Sendable {}


extension FileFormat: ByteEncodable {
    public func encode(to byteBuffer: inout ByteBuffer) {
        switch self {
        case .edf:
            byteBuffer.writeEDFAscii(".", length: 8)
        case .bdf:
            byteBuffer.writeInteger(UInt8.max)
            byteBuffer.writeEDFAscii("BIOSEMI", length: 7)
        }
    }
}
