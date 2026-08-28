//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// Failures raised when a binary64 value cannot be represented by the Grove R4 decimal contract.
public enum GroveFHIRDecimalError: Error, Equatable, Sendable {
    case nonFinite(Double)
    case outsideFHIRDecimalDomain(String)
}


/// A measured binary64 value proven representable by the R4 decimal model used on the wire.
public struct GroveFHIRDecimal: Hashable, Sendable {
    public let lexical: String
    public let decimal: Decimal

    public var primitive: FHIRPrimitive<FHIRDecimal> {
        FHIRPrimitive(FHIRDecimal(decimal))
    }

    public init(_ value: Double) throws(GroveFHIRDecimalError) {
        guard value.isFinite else {
            throw .nonFinite(value)
        }
        let lexical = String(groveFHIRPlainDecimal: value)
        guard let decimal = Decimal(
            string: lexical,
            locale: Locale(identifier: "en_US_POSIX")
        ), NSDecimalNumber(decimal: decimal).doubleValue == value else {
            throw .outsideFHIRDecimalDomain(lexical)
        }
        self.lexical = lexical
        self.decimal = decimal
    }
}
