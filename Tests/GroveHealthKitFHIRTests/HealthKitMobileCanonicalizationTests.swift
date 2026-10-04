//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
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

    struct PercentCase: CustomTestStringConvertible, Sendable {
        let fraction: Double
        let expected: String

        var testDescription: String {
            "\(fraction) -> \(expected)"
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
        let result = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: testCase.source), zone: nil)

        #expect(result.value?.description == testCase.expected)
    }

    @Test("Mobile effective instants preserve the source offset and exactly emit .251")
    func sourceOffsetAndFractionRegression() throws {
        let source = Date(timeIntervalSince1970: 1_787_148_600.251)
        let sourceTimeZone = try #require(TimeZone(secondsFromGMT: -7 * 60 * 60))

        let result = try HealthKitEffectiveTime.dateTime(source, zone: sourceTimeZone)

        #expect(result.value?.description == "2026-08-19T07:10:00.251-07:00")
    }

    @Test("Scalar quantities use the shortest round-trip decimal representation")
    func scalarDecimal() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.bodyTemperature.quantity))

        #expect(try template.quantity(36.52).value?.value?.decimal.description == "36.52")
    }

    /// A percent type's fraction stated in percent: the shortest round-trip text of the fraction shifted two places
    /// and rounded once to binary64 (spec F4-percent), never the binary64 product `fraction * 100`.
    @Test(
        "Percent states the fraction's decimal shifted two places, rounded once",
        arguments: [
            // Changed by the fix; `fraction * 100` states each with a binary64 tail.
            PercentCase(fraction: 0.07, expected: "7"),
            PercentCase(fraction: 0.14, expected: "14"),
            PercentCase(fraction: 0.28, expected: "28"),
            PercentCase(fraction: 0.29, expected: "29"),
            PercentCase(fraction: 0.282, expected: "28.2"),
            PercentCase(fraction: 0.55, expected: "55"),
            PercentCase(fraction: 0.56, expected: "56"),
            PercentCase(fraction: 0.57, expected: "57"),
            PercentCase(fraction: 0.58, expected: "58"),
            PercentCase(fraction: 0.0007, expected: "0.07"),
            PercentCase(fraction: 1e-7, expected: "0.00001"),
            // Controls: the product states the same lexeme.
            PercentCase(fraction: 0.98, expected: "98"),
            PercentCase(fraction: 0.235, expected: "23.5"),
            PercentCase(fraction: 0.223, expected: "22.3"),
            PercentCase(fraction: 0.975, expected: "97.5"),
            PercentCase(fraction: 0.042, expected: "4.2"),
            PercentCase(fraction: 0.71, expected: "71"),
            PercentCase(fraction: 0.5, expected: "50"),
            PercentCase(fraction: 0.001, expected: "0.1"),
            PercentCase(fraction: 0.0001, expected: "0.01"),
            PercentCase(fraction: 1, expected: "100"),
            PercentCase(fraction: 0, expected: "0"),
            PercentCase(fraction: -0.0, expected: "0"),
            PercentCase(fraction: 0.30000000000000004, expected: "30.000000000000004"),
            PercentCase(fraction: 1.0 / 3.0, expected: "33.33333333333333"),
            // Seventeen significant digits: the shifted text 49.543508709194095 is rounded to binary64, whose
            // shortest round-trip text has sixteen.
            PercentCase(fraction: 0.49543508709194095, expected: "49.54350870919409")
        ]
    )
    func percentOfFraction(testCase: PercentCase) throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.oxygenSaturation.quantity))

        let quantity = try template.quantity(QuantityRead.percent(ofFraction: testCase.fraction))

        #expect(quantity.value?.value?.decimal.description == testCase.expected)
    }

    /// Every fraction with up to three decimals against an integer oracle: `fraction * 100` misses 246 of them.
    @Test("Percent states every three-decimal fraction exactly")
    func percentOfThreeDecimalFractions() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.oxygenSaturation.quantity))
        var mismatches: [String] = []
        for thousandths in 0...1_000 {
            let expected = thousandths.isMultiple(of: 10) ? "\(thousandths / 10)" : "\(thousandths / 10).\(thousandths % 10)"
            let fraction = Double(thousandths) / 1_000
            let actual = try template.quantity(QuantityRead.percent(ofFraction: fraction)).value?.value?.decimal.description
            if actual != expected {
                mismatches.append("\(fraction) -> \(actual ?? "nil"), not \(expected)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) fractions: \(mismatches.prefix(10))")
    }

    @Test("Percent states a non-finite fraction as NaN, and the template refuses it as any non-finite value")
    func percentOfNonFiniteFraction() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.oxygenSaturation.quantity))
        for fraction in [Double.nan, .infinity, -.infinity] {
            #expect(QuantityRead.percent(ofFraction: fraction).isNaN)
            #expect(throws: HealthKitConversionError.ValueFailure.outsideDomain) {
                try template.quantity(QuantityRead.percent(ofFraction: fraction))
            }
        }
    }

    @Test("Non-finite quantities are outside the domain; a non-finite effective instant is no valid FHIR date-time")
    func nonFiniteValues() throws {
        let template = QuantityTemplate(try #require(MeasurementCatalog.bodyTemperature.quantity))
        #expect(throws: HealthKitConversionError.ValueFailure.outsideDomain) {
            try template.quantity(.infinity)
        }
        #expect(throws: HealthKitConversionError.ValueFailure.outsideDomain) {
            try template.quantity(.nan)
        }
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: .infinity), zone: nil)
        }
    }
}

#endif
