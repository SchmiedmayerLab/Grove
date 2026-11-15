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
    public struct Measure: Sendable {
        public let type: Int
        public let value: Int64
        public let unit: Int

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

    public let id: String
    public let date: Date
    public let measures: [Measure]

    public init(id: String, date: Date, measures: [Measure]) {
        self.id = id
        self.date = date
        self.measures = measures
    }
}
