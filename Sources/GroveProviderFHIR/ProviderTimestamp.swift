//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4


/// An exact source timestamp that keeps its RFC 3339 spelling and up to nanosecond precision.
///
/// Converted outputs state the original spelling, so they keep the source's UTC offset and fractional digits. Ordering
/// and equality compare the absolute instants without a floating-point conversion, so two spellings of one instant,
/// such as with different UTC offsets, are equal.
public struct ProviderTimestamp: Sendable, Hashable, Comparable {
    /// Why a timestamp is invalid.
    public enum ValidationError: Error, Sendable, Equatable {
        /// The value is not an RFC 3339 date-time with a seconds field, an optional fraction of up to nine digits and a
        /// UTC offset, or it names a date that doesn't exist.
        case invalidTimestamp
    }

    /// The timestamp exactly as the source spells it.
    public let originalValue: String
    let secondsSinceEpoch: Int64
    let nanoseconds: Int64

    /// Parses a source timestamp.
    public init(_ originalValue: String) throws(ValidationError) {
        let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$"#
        guard (20...35).contains(originalValue.utf8.count),
              originalValue.utf8.allSatisfy({ $0 < 128 }),
              originalValue.range(of: pattern, options: .regularExpression) == originalValue.startIndex..<originalValue.endIndex,
              !originalValue.hasSuffix("-00:00"),
              let instant = try? Instant(originalValue),
              (1...9999).contains(instant.date.year), instant.time.second < 60 else {
            throw .invalidTimestamp
        }
        let year = Int64(instant.date.year)
        let month = Int64(instant.date.month)
        let day = Int64(instant.date.day)
        let days = ExchangeInstant.days(fromYear: year, month: month, day: day)
        let civil = ExchangeInstant.civilDate(fromDays: days)
        guard civil.year == year, civil.month == month, civil.day == day else {
            throw .invalidTimestamp
        }
        let bytes = Array(originalValue.utf8)
        let seconds = Int64(bytes[17] - 48) * 10 + Int64(bytes[18] - 48)
        let fraction = bytes.dropFirst(19).drop(while: { $0 == 46 }).prefix(while: { (48...57).contains($0) })
        let nanoseconds = fraction.reduce(Int64.zero) { $0 * 10 + Int64($1 - 48) }
            * (0..<(9 - fraction.count)).reduce(Int64(1)) { value, _ in value * 10 }
        self.originalValue = originalValue
        self.secondsSinceEpoch = days * 86_400 + Int64(instant.time.hour) * 3_600
            + Int64(instant.time.minute) * 60 + seconds - Int64(instant.timeZone.secondsFromGMT())
        self.nanoseconds = nanoseconds
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.secondsSinceEpoch == rhs.secondsSinceEpoch && lhs.nanoseconds == rhs.nanoseconds
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.secondsSinceEpoch, lhs.nanoseconds) < (rhs.secondsSinceEpoch, rhs.nanoseconds)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(secondsSinceEpoch)
        hasher.combine(nanoseconds)
    }
}
