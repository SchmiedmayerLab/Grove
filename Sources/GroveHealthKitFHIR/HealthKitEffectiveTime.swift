//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


/// How a measurement's effective time is drawn from a HealthKit sample's start and end.
@available(iOS 18, macOS 15, watchOS 11, *)
enum EffectiveRule: Hashable, Sendable {
    /// `effectiveDateTime` at the sample's start.
    case instant
    /// `effectivePeriod` from start to end; a reversed interval never qualifies, and a zero-width one
    /// qualifies only when the measurement does not require a non-zero Period. FHIR `per-1` admits
    /// `start == end`, so a point-in-time source keeps its instant as an equal-endpoint Period.
    case interval(nonZero: Bool)

    /// The effective value for a sample spanning `start` to `end` in the source's `zone`.
    func value(start: Date, end: Date, zone: TimeZone?) throws(HealthKitConversionError.ValueFailure) -> Observation.EffectiveX {
        switch self {
        case .instant:
            return .dateTime(try HealthKitEffectiveTime.dateTime(start, zone: zone))
        case let .interval(nonZero):
            guard end > start || (end == start && !nonZero) else {
                throw .effectivePeriodInvalid
            }
            return .period(try HealthKitEffectiveTime.period(start: start, end: end, zone: zone))
        }
    }
}


/// FHIR date-times for HealthKit instants, built from integer civil arithmetic instead of a `Calendar`.
///
/// Mobile effective instants round to the millisecond, ties to even, counted from 1970 — never through
/// ``ExchangeInstant``, whose milliseconds count from `Date`'s 2001 reference and so round other ties.
/// They keep the source zone's offset at the unrounded instant, print `.mmm` untrimmed, and write a
/// zero offset as `Z`. ECG timing instead keeps exact Decimal seconds (``exactDateTime(_:offset:zone:)``).
///
/// Dates are proleptic Gregorian, as ISO 8601 and FHIR define them, also before the 1582 reform where
/// Foundation's Gregorian calendar switches to Julian dates. A local year outside 0001 through 9999 has
/// no FHIR date-time and is refused. ``instant(of:)`` reads a date-time back in the same calendar.
@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitEffectiveTime {
    /// Wall-clock fields of one local second.
    private struct CivilTime {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
    }

    /// The years a FHIR date-time can state.
    private static let statableYears: ClosedRange<Int> = 1...9_999

    /// The widest UTC offset Foundation represents, ±18 hours.
    private static let maximumOffsetSeconds = 64_800

    /// An effective instant in the source's own zone, which also travels as the `timezone` extension,
    /// or in UTC when the source names none.
    static func dateTime(_ date: Date, zone: TimeZone?) throws(HealthKitConversionError.ValueFailure) -> FHIRPrimitive<DateTime> {
        guard let lexeme = mobileLexeme(date, zone: zone), let dateTime = try? DateTime(lexeme) else {
            throw .shapeInvalid
        }
        guard let zone else {
            return FHIRPrimitive(dateTime)
        }
        return FHIRPrimitive(
            dateTime,
            extension: [Extension(url: Canonicals.timezone, value: .code(zone.identifier.asFHIRStringPrimitive()))]
        )
    }

    /// An effective Period in the source's zone; the end is built first, as its failures take precedence.
    static func period(start: Date, end: Date, zone: TimeZone?) throws(HealthKitConversionError.ValueFailure) -> Period {
        let end = try dateTime(end, zone: zone)
        return Period(end: end, start: try dateTime(start, zone: zone))
    }

    /// An ECG instant: `date` plus an exact Decimal offset, at the zone's fixed offset for that second.
    ///
    /// The seconds stay exact Decimals — adding the offset through `Date` would round a second time and can
    /// break SampledData's period arithmetic — and print trimmed (`00.25`). No `timezone` extension is
    /// added; a fixed-offset zone keeps the second occurrence of a repeated DST hour from printing as the first.
    static func exactDateTime(_ date: Date, offset: Decimal, zone: TimeZone) throws(HealthKitConversionError) -> DateTime {
        let epochSeconds = date.timeIntervalSince1970
        guard epochSeconds.isFinite,
              let epochDecimal = Decimal(string: String(epochSeconds), locale: .posix) else {
            throw .ecgEvidence(.invalidSourcePeriod)
        }
        let target = epochDecimal + offset
        // The floor is taken in binary64 and corrected by one second; Int64's floor has no predecessor to correct to.
        guard var wholeSeconds = Int64(exactly: NSDecimalNumber(decimal: target).doubleValue.rounded(.down)),
              wholeSeconds != .min else {
            throw .ecgEvidence(.invalidSourcePeriod)
        }
        var fraction = target - Decimal(wholeSeconds)
        if fraction < 0 {
            wholeSeconds -= 1
            fraction += 1
        } else if fraction >= 1 {
            wholeSeconds += 1
            fraction -= 1
        }
        let wholeSecondDate = Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
        let fixedZone = zone.fixedOffset(at: wholeSecondDate)
        let fixedOffset = fixedZone.secondsFromGMT(for: wholeSecondDate)
        guard let civil = civilTime(seconds: wholeSeconds, offset: fixedOffset),
              let month = UInt8(exactly: civil.month),
              let day = UInt8(exactly: civil.day),
              let hour = UInt8(exactly: civil.hour),
              let minute = UInt8(exactly: civil.minute) else {
            throw .ecgEvidence(.invalidSourcePeriod)
        }
        return DateTime(
            date: FHIRDate(year: civil.year, month: month, day: day),
            time: FHIRTime(hour: hour, minute: minute, second: Decimal(civil.second) + fraction),
            timezone: fixedZone
        )
    }

    /// The instant a FHIR date-time states, the inverse of ``dateTime(_:zone:)`` and ``exactDateTime(_:offset:zone:)``:
    /// its fields as a proleptic Gregorian wall-clock time at its offset, a partial date at its first instant, and no
    /// offset read as UTC. The seconds, fraction included, are added to the whole minute in binary64, as FHIRModels'
    /// `asNSDate()` adds them. `nil` for a local year outside 0001 through 9999, which no FHIR date-time states.
    static func instant(of dateTime: DateTime) -> Date? {
        let date = dateTime.date
        guard statableYears.contains(date.year) else {
            return nil
        }
        let days = ExchangeInstant.days(fromYear: Int64(date.year), month: Int64(date.month ?? 1), day: Int64(date.day ?? 1))
        let time = dateTime.time
        let wallClock = days * 86_400 + Int64(time?.hour ?? 0) * 3_600 + Int64(time?.minute ?? 0) * 60
        let minute = Date(timeIntervalSince1970: TimeInterval(wallClock - offset(of: dateTime.timeZone, atWallClock: wallClock)))
        return minute.addingTimeInterval(NSDecimalNumber(decimal: time?.second ?? 0).doubleValue)
    }

    /// The offset from UTC in seconds at which `zone` states the wall-clock time `wallClock` (seconds since 1970 as if
    /// it were UTC), or 0 without a zone. A parsed date-time's zone is a fixed offset. A named zone, which only a
    /// date-time built in memory carries, follows Foundation's calendar at a transition within a day: a repeated
    /// wall-clock time reads as its first occurrence, and a skipped one at the offset before the change.
    private static func offset(of zone: TimeZone?, atWallClock wallClock: Int64) -> Int64 {
        guard let zone else {
            return 0
        }
        func secondsFromUTC(at seconds: Int64) -> Int64 {
            Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
        }
        let former = secondsFromUTC(at: wallClock - 86_400)
        let latter = secondsFromUTC(at: wallClock - former)
        return latter != former && secondsFromUTC(at: wallClock - latter) == latter ? latter : former
    }

    /// The Mobile lexeme `YYYY-MM-DDThh:mm:ss[.mmm](Z|±hh:mm)`, or `nil` when the instant has none:
    /// non-finite, beyond Int64 milliseconds, an offset that is not whole minutes within ±18 h, or a
    /// local year outside 1…9999.
    private static func mobileLexeme(_ date: Date, zone: TimeZone?) -> String? {
        guard let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1_000).rounded(.toNearestOrEven)) else {
            return nil
        }
        let offset = zone?.secondsFromGMT(for: date) ?? 0
        guard offset.isMultiple(of: 60), abs(offset) <= maximumOffsetSeconds else {
            return nil
        }
        let (wholeSeconds, millisecond) = ExchangeInstant.floorDivide(milliseconds, by: 1_000)
        guard let civil = civilTime(seconds: wholeSeconds, offset: offset) else {
            return nil
        }
        var lexeme = ExchangeInstant.padded(Int64(civil.year), width: 4)
        lexeme += "-" + twoDigits(civil.month) + "-" + twoDigits(civil.day)
        lexeme += "T" + twoDigits(civil.hour) + ":" + twoDigits(civil.minute) + ":" + twoDigits(civil.second)
        if millisecond != 0 {
            lexeme += "." + ExchangeInstant.padded(millisecond, width: 3)
        }
        guard offset != 0 else {
            return lexeme + "Z"
        }
        let magnitude = Int(offset.magnitude)
        return lexeme + (offset < 0 ? "-" : "+") + twoDigits(magnitude / 3_600) + ":" + twoDigits(magnitude % 3_600 / 60)
    }

    /// A field of at most two digits, zero-padded to two.
    private static func twoDigits(_ value: Int) -> String {
        ExchangeInstant.padded(Int64(value), width: 2)
    }

    /// The proleptic Gregorian wall-clock fields of a UTC second count at `offset` seconds from UTC, or
    /// `nil` when the local year is not statable.
    private static func civilTime(seconds: Int64, offset: Int) -> CivilTime? {
        let (local, overflow) = seconds.addingReportingOverflow(Int64(offset))
        guard !overflow else {
            return nil
        }
        let (days, secondOfDay) = ExchangeInstant.floorDivide(local, by: 86_400)
        let date = ExchangeInstant.civilDate(fromDays: days)
        guard let year = Int(exactly: date.year), statableYears.contains(year) else {
            return nil
        }
        return CivilTime(
            year: year,
            month: Int(date.month),
            day: Int(date.day),
            hour: Int(secondOfDay / 3_600),
            minute: Int(secondOfDay / 60 % 60),
            second: Int(secondOfDay % 60)
        )
    }
}

#endif
