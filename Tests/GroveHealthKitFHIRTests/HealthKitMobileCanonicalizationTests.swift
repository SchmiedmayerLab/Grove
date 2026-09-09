//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKitFHIR
import Testing


@Suite
struct HealthKitFHIRMobileCanonicalizationTests {
    struct InstantCase: CustomTestStringConvertible, Sendable {
        let source: TimeInterval
        let expected: String

        var testDescription: String {
            "\(source) -> \(expected)"
        }
    }

    @Test(
        "Mobile effective instants use millisecond half-even rounding across the epoch",
        arguments: [
            InstantCase(source: 0.0005, expected: "1970-01-01T00:00:00Z"),
            InstantCase(source: 0.0015, expected: "1970-01-01T00:00:00.002Z"),
            InstantCase(source: -0.0005, expected: "1970-01-01T00:00:00Z"),
            InstantCase(source: -0.0015, expected: "1969-12-31T23:59:59.998Z"),
            InstantCase(source: 0.9995, expected: "1970-01-01T00:00:01Z"),
            InstantCase(source: 1.0005, expected: "1970-01-01T00:00:01Z")
        ]
    )
    func effectiveInstant(testCase: InstantCase) throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let result = try HealthKitMobileCanonicalization.effectiveDateTime(
            Date(timeIntervalSince1970: testCase.source),
            timeZone: utc
        )

        #expect(result.description == testCase.expected)
    }

    @Test("Mobile effective instants preserve the source offset and exactly emit .251")
    func sourceOffsetAndFractionRegression() throws {
        let source = Date(timeIntervalSince1970: 1_787_148_600.251)
        let sourceTimeZone = try #require(TimeZone(secondsFromGMT: -7 * 60 * 60))

        let result = try HealthKitMobileCanonicalization.effectiveDateTime(
            source,
            timeZone: sourceTimeZone
        )

        #expect(result.description == "2026-08-19T07:10:00.251-07:00")
    }

    @Test("Scalar quantities use the shortest round-trip decimal representation")
    func scalarDecimal() throws {
        let value = try HealthKitMobileCanonicalization.scalarDecimal(36.52)

        #expect(value.value?.decimal.description == "36.52")
    }

    @Test("Non-finite effective instants and quantities fail closed")
    func nonFiniteValues() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitMobileCanonicalization.scalarDecimal(.infinity)
        }
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitMobileCanonicalization.scalarDecimal(.nan)
        }
        #expect(throws: HealthKitConversionError.invalidValue) {
            try HealthKitMobileCanonicalization.effectiveDateTime(
                Date(timeIntervalSince1970: .infinity),
                timeZone: utc
            )
        }
    }
}

#endif
