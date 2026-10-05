//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation
package import ModelsR4


/// Failures raised when a binary64 value cannot be represented by the Grove R4 decimal contract.
package enum GroveFHIRDecimalError: Error, Equatable, Sendable {
    case nonFinite(Double)
    case outsideFHIRDecimalDomain(String)
}


/// A measured binary64 value proven representable by the R4 decimal model used on the wire.
package struct GroveFHIRDecimal: Hashable, Sendable {
    package let lexical: String
    package let decimal: Decimal

    package var primitive: FHIRPrimitive<FHIRDecimal> {
        FHIRPrimitive(FHIRDecimal(decimal))
    }

    package init(_ value: Double) throws(GroveFHIRDecimalError) {
        guard value.isFinite else {
            throw .nonFinite(value)
        }
        // Representability is proven against the text, not against `NSDecimalNumber`: its
        // Decimal-to-Double conversion is inexact for ordinary values such as 36.52 and would
        // refuse them.
        let lexical = String(groveFHIRPlainDecimal: value)
        guard let decimal = Decimal(string: lexical, locale: .posix), Double(lexical) == value else {
            throw .outsideFHIRDecimalDomain(lexical)
        }
        self.lexical = lexical
        self.decimal = decimal
    }
}


extension Locale {
    /// The fixed `en_US_POSIX` locale, built once, for reading and writing machine-readable numbers.
    package static let posix = Locale(identifier: "en_US_POSIX")
}
