//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import ModelsR4
import Testing


/// Pins the wire lexeme of a converter clock instant: UTC, millisecond precision, ASCII, no formatter.
@Suite
struct ExchangeInstantTests {
    /// Instants and their lexemes, from the epoch second (and, where it matters, a fraction) in UTC.
    private static let pinned: [(seconds: TimeInterval, lexeme: String)] = [
        (1_791_023_400, "2026-10-03T10:30:00Z"),
        (1_791_023_400.5, "2026-10-03T10:30:00.5Z"),
        (1_791_023_400.251, "2026-10-03T10:30:00.251Z"),
        (1_791_023_400.25, "2026-10-03T10:30:00.25Z"),
        (1_791_023_400.001, "2026-10-03T10:30:00.001Z"),
        (1_791_023_400.999, "2026-10-03T10:30:00.999Z"),
        (1_791_023_400.0004, "2026-10-03T10:30:00Z"),
        (1_791_023_400.9996, "2026-10-03T10:30:01Z"),
        (0, "1970-01-01T00:00:00Z"),
        (-0.001, "1969-12-31T23:59:59.999Z"),
        (978_307_200, "2001-01-01T00:00:00Z"),
        (946_684_799, "1999-12-31T23:59:59Z"),
        (946_684_800, "2000-01-01T00:00:00Z"),
        (1_798_761_599.9996, "2027-01-01T00:00:00Z"),
        (1_709_164_800, "2024-02-29T00:00:00Z"),
        (951_825_600, "2000-02-29T12:00:00Z"),
        (-2_203_891_200, "1900-03-01T00:00:00Z"),
        (4_107_542_399, "2100-02-28T23:59:59Z"),
        (4_107_542_400, "2100-03-01T00:00:00Z"),
        (-12_219_724_800, "1582-10-10T00:00:00Z"),
        (-62_135_596_800, "0001-01-01T00:00:00Z"),
        (253_402_300_799, "9999-12-31T23:59:59Z")
    ]

    /// Instants and their lexemes at an offset of the given seconds east of UTC.
    private static let pinnedAtOffsets: [(secondsEast: Int, pin: (seconds: TimeInterval, lexeme: String))] = [
        (-25_200, (1_787_931_125.123, "2026-08-28T08:32:05.123-07:00")),
        (19_800, (1_788_010_000.9876, "2026-08-29T18:56:40.988+05:30")),
        (0, (1_787_931_125, "2026-08-28T15:32:05Z")),
        (20_700, (1_787_931_125, "2026-08-28T21:17:05+05:45")),
        (3_600, (1_767_225_599.5, "2026-01-01T00:59:59.5+01:00")),
        (50_400, (0, "1970-01-01T14:00:00+14:00")),
        (-43_200, (0, "1969-12-31T12:00:00-12:00"))
    ]

    @Test("Whole seconds, fractions and boundaries print as pinned", arguments: Self.pinned)
    func pinnedLexemes(_ pin: (seconds: TimeInterval, lexeme: String)) {
        #expect(ExchangeInstant.utcLexeme(Date(timeIntervalSince1970: pin.seconds)) == pin.lexeme)
    }

    /// `Date` stores seconds since 2001, so a half-millisecond tie is exact only against that reference.
    @Test("Half a millisecond rounds to the even millisecond", arguments: [
        (0.0005, "2001-01-01T00:00:00Z"),
        (0.0015, "2001-01-01T00:00:00.002Z"),
        (0.0025, "2001-01-01T00:00:00.002Z"),
        (0.0035, "2001-01-01T00:00:00.004Z"),
        (1.0005, "2001-01-01T00:00:01Z"),
        (1.0015, "2001-01-01T00:00:01.002Z"),
        (-0.0005, "2001-01-01T00:00:00Z"),
        (-0.0015, "2000-12-31T23:59:59.998Z")
    ])
    func tiesToEven(_ pin: (sinceReference: TimeInterval, lexeme: String)) {
        #expect((pin.sinceReference * 1000).remainder(dividingBy: 1) == 0.5 || (pin.sinceReference * 1000).remainder(dividingBy: 1) == -0.5)
        #expect(ExchangeInstant.utcLexeme(Date(timeIntervalSinceReferenceDate: pin.sinceReference)) == pin.lexeme)
    }

    @Test("The binary64 neighbour below a millisecond still prints that millisecond")
    func binaryNeighbourRoundsUp() {
        let date = Date(timeIntervalSince1970: 1_787_009_400.251)
        #expect(date.timeIntervalSince1970 < 1_787_009_400.251 || date.timeIntervalSinceReferenceDate * 1000 < 808_702_200_251)
        #expect(ExchangeInstant.utcLexeme(date) == "2026-08-17T23:30:00.251Z")
    }

    @Test("Whole-second instants equal what FHIRModels builds from the date in UTC", arguments: [
        1_791_023_400, 0, 978_307_200, 946_684_799, 1_709_164_800, 4_107_542_400, 253_402_300_799
    ] as [TimeInterval])
    func matchesFHIRModelsForWholeSeconds(_ seconds: TimeInterval) throws {
        let date = Date(timeIntervalSince1970: seconds)
        let instant = try ExchangeInstant.fhirInstant(date)
        let dateTime = try ExchangeInstant.fhirDateTime(date)
        let modelsInstant = try Instant(utc: date)
        let modelsDateTime = try DateTime(utc: date)
        #expect(instant == modelsInstant)
        #expect(instant.description == modelsInstant.description)
        #expect(dateTime == modelsDateTime)
        #expect(dateTime.description == modelsDateTime.description)
        #expect(instant.description == ExchangeInstant.utcLexeme(date))
        #expect(dateTime.description == ExchangeInstant.utcLexeme(date))
    }

    @Test("FHIRModels keeps the parsed fraction verbatim")
    func fhirTypesKeepTheLexeme() throws {
        for seconds in [1_791_023_400.251, 1_791_023_400.5, 1_791_023_400.001, 1_791_023_400.25] as [TimeInterval] {
            let date = Date(timeIntervalSince1970: seconds)
            let lexeme = ExchangeInstant.utcLexeme(date)
            #expect(try ExchangeInstant.fhirInstant(date).description == lexeme)
            #expect(try ExchangeInstant.fhirDateTime(date).description == lexeme)
            let instant = try ExchangeInstant.fhirInstant(date)
            #expect(instant.timeZone == TimeZone(secondsFromGMT: 0))
            #expect(try Instant(lexeme) == instant)
        }
    }

    @Test("An instant at an offset states the wall time there, to the millisecond, and the offset", arguments: Self.pinnedAtOffsets)
    func offsetLexemes(_ pinned: (secondsEast: Int, pin: (seconds: TimeInterval, lexeme: String))) throws {
        let zone = try #require(TimeZone(secondsFromGMT: pinned.secondsEast))
        let dateTime = try ExchangeInstant.fhirDateTime(Date(timeIntervalSince1970: pinned.pin.seconds), offsetIn: zone)
        #expect(dateTime.description == pinned.pin.lexeme)
        #expect(abs(try dateTime.asNSDate().timeIntervalSince1970 - pinned.pin.seconds) < 0.000_5)
    }

    /// Questionnaire's `Provenance.occurred` was built by FHIRModels at the authored offset; whole seconds keep its bytes.
    @Test("Whole-second offset instants equal what FHIRModels builds from the date in the zone", arguments: [
        -25_200, 19_800, 20_700, 0, -12_600, 50_400
    ])
    func offsetMatchesFHIRModelsForWholeSeconds(_ offset: Int) throws {
        let zone = try #require(TimeZone(secondsFromGMT: offset))
        for seconds in [1_787_931_125, 1_767_225_599, 0, 951_825_600] as [TimeInterval] {
            let date = Date(timeIntervalSince1970: seconds)
            #expect(try ExchangeInstant.fhirDateTime(date, offsetIn: zone).description == DateTime(date: date, timeZone: zone).description)
        }
    }

    @Test("A named zone states its offset at that instant, and a sub-minute offset is dropped with the wall time following")
    func zoneOffsetsAtTheInstant() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(try ExchangeInstant.fhirDateTime(Date(timeIntervalSince1970: 1_787_931_125), offsetIn: losAngeles).description
            == "2026-08-28T08:32:05-07:00")
        #expect(try ExchangeInstant.fhirDateTime(Date(timeIntervalSince1970: 1_767_225_600), offsetIn: losAngeles).description
            == "2025-12-31T16:00:00-08:00")
        let subMinute = try #require(TimeZone(secondsFromGMT: 3_630))
        let dateTime = try ExchangeInstant.fhirDateTime(Date(timeIntervalSince1970: 1_787_931_125), offsetIn: subMinute)
        #expect(dateTime.description == "2026-08-28T16:32:05+01:00")
        #expect(try dateTime.asNSDate() == Date(timeIntervalSince1970: 1_787_931_125))
    }

    @Test("A year outside four digits is not a FHIR instant")
    func outOfRangeYearsAreRefused() {
        let tenThousand = Date(timeIntervalSince1970: 253_402_300_800)
        #expect(ExchangeInstant.utcLexeme(tenThousand) == "10000-01-01T00:00:00Z")
        #expect(throws: (any Error).self) { try ExchangeInstant.fhirInstant(tenThousand) }
        #expect(throws: (any Error).self) { try ExchangeInstant.fhirDateTime(tenThousand) }
        #expect(ExchangeInstant.utcLexeme(Date(timeIntervalSince1970: -62_135_596_801)) == "0000-12-31T23:59:59Z")
    }

    @Test("Millisecond counts round-trip through the instant they name")
    func millisecondCountsRoundTrip() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<5000 {
            let milliseconds = Int64.random(in: -62_135_596_800_000...253_402_300_799_999, using: &generator)
            let date = ExchangeInstant.date(millisecondsSinceEpoch: milliseconds)
            #expect(ExchangeInstant.millisecondsSinceEpoch(date) == milliseconds)
        }
        #expect(ExchangeInstant.millisecondsSinceEpoch(Date(timeIntervalSince1970: 1_791_023_400.251)) == 1_791_023_400_251)
        let named = ExchangeInstant.date(millisecondsSinceEpoch: 1_791_023_400_251)
        #expect(abs(named.timeIntervalSince1970 - 1_791_023_400.251) < 0.000_001)
        #expect(ExchangeInstant.utcLexeme(named) == "2026-10-03T10:30:00.251Z")
    }

    /// The 400-year era from -0400-03-01 through 0000-02-29 counts -1, which the inverse must floor, not truncate, to.
    @Test("Days from a civil date invert the civil date of every day from year -400 through 9999")
    func daysFromCivilDatesInvertCivilDates() {
        var mismatches: [Int64] = []
        for days in Int64(-865_625)...2_932_896 {
            let civil = ExchangeInstant.civilDate(fromDays: days)
            if ExchangeInstant.days(fromYear: civil.year, month: civil.month, day: civil.day) != days {
                mismatches.append(days)
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) days do not round-trip: \(mismatches.prefix(10))")
        #expect(ExchangeInstant.days(fromYear: 1970, month: 1, day: 1) == 0)
        #expect(ExchangeInstant.days(fromYear: -400, month: 1, day: 1) == -865_625)
        #expect(ExchangeInstant.days(fromYear: 0, month: 1, day: 1) == -719_528)
        #expect(ExchangeInstant.days(fromYear: 1, month: 1, day: 1) == -719_162)
        #expect(ExchangeInstant.days(fromYear: 1582, month: 10, day: 15) == -141_427)
        #expect(ExchangeInstant.days(fromYear: 1582, month: 10, day: 4) == -141_438)
        #expect(ExchangeInstant.days(fromYear: 9999, month: 12, day: 31) == 2_932_896)
    }

    @Test("A day past its month, or month 0, carries over as a calendar's does")
    func daysFromCivilDatesCarryOver() {
        #expect(ExchangeInstant.days(fromYear: 2026, month: 2, day: 31) == ExchangeInstant.days(fromYear: 2026, month: 3, day: 3))
        #expect(ExchangeInstant.days(fromYear: 2024, month: 2, day: 31) == ExchangeInstant.days(fromYear: 2024, month: 3, day: 2))
        #expect(ExchangeInstant.days(fromYear: 2026, month: 3, day: 0) == ExchangeInstant.days(fromYear: 2026, month: 2, day: 28))
        #expect(ExchangeInstant.days(fromYear: 2026, month: 0, day: 31) == ExchangeInstant.days(fromYear: 2025, month: 12, day: 31))
        #expect(ExchangeInstant.days(fromYear: 2026, month: 12, day: 32) == ExchangeInstant.days(fromYear: 2027, month: 1, day: 1))
    }

    /// Foundation's calendar is proleptic Gregorian from 1582-10-15 on, so it can check the arithmetic there.
    @Test("Matches Foundation's UTC calendar for millisecond instants after the Gregorian reform")
    func matchesFoundationCalendar() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let milliseconds = Int64.random(in: -12_219_292_800_000...253_402_300_799_999, using: &generator)
            let date = ExchangeInstant.date(millisecondsSinceEpoch: milliseconds)
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
            let millisecond = Int((Double(try #require(parts.nanosecond)) / 1_000_000).rounded())
            var fraction = millisecond == 0 ? "" : "." + String(format: "%03d", millisecond)
            while fraction.hasSuffix("0") {
                fraction.removeLast()
            }
            let expected = String(
                format: "%04d-%02d-%02dT%02d:%02d:%02d",
                try #require(parts.year),
                try #require(parts.month),
                try #require(parts.day),
                try #require(parts.hour),
                try #require(parts.minute),
                try #require(parts.second)
            ) + fraction + "Z"
            #expect(ExchangeInstant.utcLexeme(date) == expected, "\(milliseconds)")
        }
    }

    /// The lexeme never consults a locale, so it cannot pick up a locale's digits; the test shows what
    /// those digits would look like and that none of them appear, as the process locale cannot be swapped here.
    @Test("Digits stay ASCII where a locale-aware formatter would not")
    func digitsStayASCII() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ar_EG")
        let localized = formatter.string(from: 2026) ?? ""
        #expect(!localized.utf8.allSatisfy { $0 < 0x80 }, "ar_EG formats digits outside ASCII; the contrast below is meaningful")
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let milliseconds = Int64.random(in: -62_135_596_800_000...253_402_300_799_999, using: &generator)
            let lexeme = ExchangeInstant.utcLexeme(ExchangeInstant.date(millisecondsSinceEpoch: milliseconds))
            #expect(lexeme.utf8.allSatisfy { $0 < 0x80 })
            #expect(lexeme.utf8.allSatisfy { (0x30...0x39).contains($0) || "-T:.Z".utf8.contains($0) })
            #expect(lexeme.hasSuffix("Z") && lexeme.count >= 20 && lexeme.count <= 24)
        }
    }

    @Test("Non-finite instants saturate instead of trapping")
    func nonFiniteInstantsSaturate() {
        #expect(ExchangeInstant.utcLexeme(Date(timeIntervalSince1970: .infinity)) == ExchangeInstant.utcLexeme(Date(timeIntervalSince1970: .nan)))
        #expect(ExchangeInstant.utcLexeme(Date(timeIntervalSince1970: -.infinity)).hasPrefix("-"))
        #expect(throws: (any Error).self) { try ExchangeInstant.fhirInstant(Date(timeIntervalSince1970: .infinity)) }
        #expect(ExchangeInstant.utcLexeme(.distantFuture) == "4001-01-01T00:00:00Z")
        #expect(ExchangeInstant.utcLexeme(.distantPast) == "0000-12-30T00:00:00Z")
    }
}
