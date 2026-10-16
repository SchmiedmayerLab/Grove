//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import Testing


/// Every producer serializes a measured `Double` through one implementation, so the same value
/// reaches the wire as the same characters whichever adapter emitted it.
@Suite
struct GroveFHIRPlainDecimalTests {
    @Test(
        "Shortest round-trip text, never an exponent",
        arguments: [
            (0.0, "0"),
            (-0.0, "0"),
            (1.0, "1"),
            (-1.5, "-1.5"),
            (1.0 / 3.0, "0.3333333333333333"),
            (97.5, "97.5"),
            (1e-7, "0.0000001"),
            (-1e-7, "-0.0000001"),
            (1e21, "1000000000000000000000"),
            (1.5e-8, "0.000000015")
        ] as [(Double, String)]
    )
    func plainDecimalMatches(value: Double, expected: String) {
        #expect(String(groveFHIRPlainDecimal: value) == expected)
    }

    @Test("The widened binary expansion is never emitted")
    func neverWidensToTheBinaryExpansion() {
        // Decimal(_: Double) and NSDecimalNumber(value:) both yield 0.333333333333333248 here.
        // Emitting that would change the exchanged value depending on which adapter converted it.
        let third = 1.0 / 3.0
        #expect(String(groveFHIRPlainDecimal: third) != "\(Decimal(third))")
        #expect(String(groveFHIRPlainDecimal: third) != NSDecimalNumber(value: third).stringValue)
    }

    @Test("Every emitted value parses back to the source Double")
    func roundTripsExactly() {
        for value in [0.1, 1.0 / 3.0, 97.5, -42.125, 1e-7, 6.02e23, Double.pi] {
            #expect(Double(String(groveFHIRPlainDecimal: value)) == value, "\(value)")
        }
    }
}
