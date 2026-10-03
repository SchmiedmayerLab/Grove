//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation
package import ModelsR4


/// Converter clock instants as the wire states them: UTC, millisecond precision, ASCII.
///
/// The lexeme is computed from the instant's own binary64 value with integer arithmetic over the
/// proleptic Gregorian calendar, never through a `Formatter`, `Calendar` or `Locale`, so the same
/// instant yields the same bytes in every process, on every platform, under every locale.
/// Milliseconds are rounded half to even, trailing fraction zeros are dropped, and a whole second
/// carries no fraction: `2026-10-03T10:30:00Z`, `…:00.5Z`, `…:00.251Z`.
package enum ExchangeInstant {
    private struct CivilDate {
        let year: Int64
        let month: Int64
        let day: Int64
    }

    /// `Date` counts from 2001-01-01T00:00:00Z; the wire counts from 1970.
    private static let referenceEpochMilliseconds: Int64 = 978_307_200_000

    /// The instant as a FHIR `instant` lexeme in UTC.
    package static func utcLexeme(_ date: Date) -> String {
        let (days, millisecondOfDay) = floorDivide(millisecondsSinceEpoch(date), by: 86_400_000)
        let civil = civilDate(fromDays: days)
        let secondOfDay = millisecondOfDay / 1000
        let millisecond = millisecondOfDay % 1000
        var lexeme = ""
        lexeme.reserveCapacity(24)
        lexeme += padded(civil.year, width: 4)
        lexeme += "-" + padded(civil.month, width: 2) + "-" + padded(civil.day, width: 2)
        lexeme += "T" + padded(secondOfDay / 3600, width: 2)
        lexeme += ":" + padded(secondOfDay / 60 % 60, width: 2)
        lexeme += ":" + padded(secondOfDay % 60, width: 2)
        if millisecond != 0 {
            var fraction = padded(millisecond, width: 3)
            while fraction.hasSuffix("0") {
                fraction.removeLast()
            }
            lexeme += "." + fraction
        }
        lexeme += "Z"
        return lexeme
    }

    /// The instant as a FHIR `Instant`, which keeps the parsed lexeme and prints it back verbatim.
    package static func fhirInstant(_ date: Date) throws -> Instant {
        try Instant(utcLexeme(date))
    }

    /// The instant as a FHIR `DateTime`, which keeps the parsed lexeme and prints it back verbatim.
    package static func fhirDateTime(_ date: Date) throws -> DateTime {
        try DateTime(utcLexeme(date))
    }

    /// Milliseconds since 1970-01-01T00:00:00Z, rounded half to even from the instant's own binary64 value.
    ///
    /// A non-finite or out-of-range instant saturates; its lexeme then names no FHIR-representable year.
    static func millisecondsSinceEpoch(_ date: Date) -> Int64 {
        let scaled = (date.timeIntervalSinceReferenceDate * 1000).rounded(.toNearestOrEven)
        let sinceReference = Int64(exactly: scaled) ?? (scaled < 0 ? .min : .max)
        let (sum, overflow) = sinceReference.addingReportingOverflow(referenceEpochMilliseconds)
        return overflow ? .max : sum
    }

    /// The instant at exactly these milliseconds since 1970-01-01T00:00:00Z.
    ///
    /// Round-trips through ``millisecondsSinceEpoch(_:)``: the nearest binary64 second count is within
    /// a fraction of a millisecond of the exact value, so rounding recovers the same count.
    static func date(millisecondsSinceEpoch milliseconds: Int64) -> Date {
        let (sinceReference, overflow) = milliseconds.subtractingReportingOverflow(referenceEpochMilliseconds)
        return Date(timeIntervalSinceReferenceDate: Double(overflow ? .min : sinceReference) / 1000)
    }

    private static func floorDivide(_ value: Int64, by divisor: Int64) -> (quotient: Int64, remainder: Int64) {
        var quotient = value / divisor
        var remainder = value % divisor
        if remainder < 0 {
            quotient -= 1
            remainder += divisor
        }
        return (quotient, remainder)
    }

    /// Days since 1970-01-01 to a proleptic Gregorian date (Howard Hinnant's `civil_from_days`).
    private static func civilDate(fromDays days: Int64) -> CivilDate {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return CivilDate(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    /// ASCII decimal digits, zero-padded to `width`; `String(_:)` never consults the locale.
    private static func padded(_ value: Int64, width: Int) -> String {
        let digits = String(value.magnitude)
        let zeros = String(repeating: "0", count: max(0, width - digits.count))
        return (value < 0 ? "-" : "") + zeros + digits
    }
}
