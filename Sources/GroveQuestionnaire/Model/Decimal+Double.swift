//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


extension Decimal {
    /// The decimal with the shortest digits that convert back to `value`.
    ///
    /// A number typed into a form or read from JSON becomes the nearest `Double`, and its shortest
    /// round-trip digits are the digits that were given, up to 15 significant digits.
    /// `Decimal(value)` instead expands the binary value, so `36.52` becomes `36.52000000000000512`.
    ///
    /// `nil` for a value that is not finite or lies outside the range of `Decimal`.
    package init?(shortestDigitsOf value: Double) {
        guard value.isFinite,
              let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self = decimal
    }
}
