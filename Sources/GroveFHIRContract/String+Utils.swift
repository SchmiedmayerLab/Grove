//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension String {
    /// The shortest decimal text that round-trips this value, never in exponent notation.
    ///
    /// Every Grove producer serializes a measured `Double` through here, so the same value is
    /// exchanged as the same characters whichever adapter emitted it — including the Kotlin and
    /// TypeScript producers, which have to reproduce these bytes exactly.
    ///
    /// FHIR forbids exponent notation in a `decimal`, and Swift's shortest round-trip form uses it
    /// beyond a threshold, so the exponent is expanded to positional digits here. The three
    /// Foundation routes to the same shape were each ruled out:
    ///
    /// - `Decimal(someDouble)` widens to the binary expansion; one third becomes
    ///   `0.333333333333333248` rather than `0.3333333333333333`.
    /// - `Decimal(string: String(someDouble))` keeps the shortest digits but is not total over
    ///   `Double`: a subnormal such as `5e-324` is outside `Decimal`'s range and parses to `nil`.
    /// - `formatted(.number…)` goes through ICU, whose digit and separator output depends on the
    ///   locale and the platform's ICU version — not something a frozen wire contract can rest on.
    package init(groveFHIRPlainDecimal value: Double) {
        guard value != 0 else {
            self = "0"
            return
        }
        let shortest = String(value)
        guard let exponentMarker = shortest.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            self = shortest.hasSuffix(".0") ? String(shortest.dropLast(2)) : shortest
            return
        }
        let mantissa = shortest[..<exponentMarker]
        let exponent = Int(shortest[shortest.index(after: exponentMarker)...]) ?? 0
        let isNegative = mantissa.first == "-"
        let unsigned = isNegative ? mantissa.dropFirst() : mantissa[...]
        let point = unsigned.firstIndex(of: ".")
        let scale = point.map { unsigned.distance(from: unsigned.startIndex, to: $0) } ?? unsigned.count
        let digits = unsigned.filter { $0 != "." }
        let expandedScale = scale + exponent

        let magnitude: String
        if expandedScale <= 0 {
            magnitude = "0." + String(repeating: "0", count: -expandedScale) + digits
        } else if expandedScale >= digits.count {
            magnitude = digits + String(repeating: "0", count: expandedScale - digits.count)
        } else {
            let insertion = digits.index(digits.startIndex, offsetBy: expandedScale)
            magnitude = digits[..<insertion] + "." + digits[insertion...]
        }
        self = isNegative ? "-" + magnitude : magnitude
    }
}


extension StringProtocol {
    /// Same result as `trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
    /// Uses the same set as `CharacterSet.whitespacesAndNewlines` (Unicode White_Space + U+200B).
    @inlinable package var isBlank: Bool {
        unicodeScalars.allSatisfy {
            switch $0.value {
            case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200B,
                0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
                true
            default:
                false
            }
        }
    }
}
