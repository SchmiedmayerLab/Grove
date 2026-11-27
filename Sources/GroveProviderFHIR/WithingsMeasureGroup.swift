//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// One upstream measure group. Types remain numeric so unknown and deliberately refused rows are distinguishable.
public struct WithingsMeasureGroup: Sendable {
    /// One measure of a group, its value scaled by a power of ten.
    public struct Measure: Sendable {
        /// The Withings measure type.
        public let type: Int
        /// The unscaled value.
        public let value: Int64
        /// The base-ten exponent of the value.
        public let unit: Int

        /// Creates a measure.
        public init(type: Int, value: Int64, unit: Int) {
            self.type = type
            self.value = value
            self.unit = unit
        }

        /// Exact base-ten scaling, without an intermediate binary floating-point value.
        func scaled(additionalExponent: Int = 0) throws -> Decimal {
            let (exponent, overflow) = unit.addingReportingOverflow(additionalExponent)
            guard !overflow, let power = Int16(exactly: exponent) else { throw ProviderConversionError.decimalOverflow }
            var input = Decimal(value)
            var result = Decimal()
            guard NSDecimalMultiplyByPowerOf10(&result, &input, power, .plain) == .noError, !result.isNaN else {
                throw ProviderConversionError.decimalOverflow
            }
            return result
        }
    }

    /// The group's identifier.
    public let id: String
    /// The group's measurement time.
    public let date: Date
    /// The group's measures.
    public let measures: [Measure]

    /// Creates a measure group.
    public init(id: String, date: Date, measures: [Measure]) {
        self.id = id
        self.date = date
        self.measures = measures
    }
}
