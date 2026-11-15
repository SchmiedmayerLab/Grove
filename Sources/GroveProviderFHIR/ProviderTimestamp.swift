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


/// An exact source timestamp, retaining its RFC 3339 spelling and up to nanosecond precision.
/// Ordering and equality compare absolute instants without a floating-point conversion.
public struct ProviderTimestamp: Sendable, Hashable, Comparable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidTimestamp
        case unsupportedUTCOffset
    }

    public let originalValue: String
    let secondsSinceEpoch: Int64
    let nanoseconds: Int64

    public init(_ originalValue: String) throws {
        let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$"#
        guard (20...35).contains(originalValue.utf8.count),
              originalValue.utf8.allSatisfy({ $0 < 128 }),
              originalValue.range(of: pattern, options: .regularExpression) == originalValue.startIndex..<originalValue.endIndex,
              !originalValue.hasSuffix("-00:00"),
              let instant = try? Instant(originalValue),
              (1...9999).contains(instant.date.year), instant.time.second < 60 else {
            throw ValidationError.invalidTimestamp
        }
        let year = Int64(instant.date.year)
        let month = Int64(instant.date.month)
        let day = Int64(instant.date.day)
        let days = ExchangeInstant.days(fromYear: year, month: month, day: day)
        let civil = ExchangeInstant.civilDate(fromDays: days)
        guard civil.year == year, civil.month == month, civil.day == day else {
            throw ValidationError.invalidTimestamp
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

    /// Expresses this instant with a source-reported UTC offset without rounding its fraction.
    /// The caller retains the original timestamp and offset fields as acquisition evidence.
    /// FHIR offsets must be whole minutes within −14:00 through +14:00.
    public func localized(toUTCOffsetSeconds offset: Int) throws -> Self {
        guard (-50_400...50_400).contains(offset), offset.isMultiple(of: 60) else {
            throw ValidationError.unsupportedUTCOffset
        }
        let (days, secondsOfDay) = ExchangeInstant.floorDivide(secondsSinceEpoch + Int64(offset), by: 86_400)
        let civil = ExchangeInstant.civilDate(fromDays: days)
        guard (1...9999).contains(civil.year) else { throw ValidationError.invalidTimestamp }
        let fraction = originalValue.dropFirst(19).prefix { $0 == "." || $0.isASCII && $0.isNumber }
        let date = "\(ExchangeInstant.padded(civil.year, width: 4))-\(ExchangeInstant.padded(civil.month, width: 2))"
            + "-\(ExchangeInstant.padded(civil.day, width: 2))"
        let time = "\(ExchangeInstant.padded(secondsOfDay / 3_600, width: 2)):"
            + "\(ExchangeInstant.padded(secondsOfDay % 3_600 / 60, width: 2)):"
            + "\(ExchangeInstant.padded(secondsOfDay % 60, width: 2))\(fraction)"
        let absoluteOffset = Int64(abs(offset))
        let suffix = offset == 0 ? "Z" : "\(offset < 0 ? "-" : "+")"
            + "\(ExchangeInstant.padded(absoluteOffset / 3_600, width: 2)):"
            + "\(ExchangeInstant.padded(absoluteOffset % 3_600 / 60, width: 2))"
        return try Self("\(date)T\(time)\(suffix)")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(secondsSinceEpoch)
        hasher.combine(nanoseconds)
    }
}
