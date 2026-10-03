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
import ModelsR4
import Testing


/// The civil-arithmetic effective-time kernel against Foundation's Gregorian calendar where that calendar is
/// proleptic, its proleptic dates before the 1582 reform, and the behaviour each builder keeps.
@Suite
struct HealthKitEffectiveTimeTests {
    /// SplitMix64, so a failing sweep replays exactly.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    /// Seeded instants per zone; `TEST_RUNNER_GROVE_EFFECTIVE_TIME_SWEEP=1000000` runs a million. They are drawn and
    /// checked one at a time, each in its own pool, so a large sweep does not grow the heap concurrent suites measure.
    private static let sweepCount = ProcessInfo.processInfo.environment["GROVE_EFFECTIVE_TIME_SWEEP"].flatMap { Int($0) } ?? 3_000

    /// Named zones with odd, LMT, non-hour and DST offsets, plus both ±18 h extremes.
    private static let namedZones: [TimeZone] = [
        "America/Los_Angeles", "Asia/Kolkata", "Asia/Kathmandu", "America/St_Johns", "Europe/Amsterdam",
        "Africa/Monrovia", "Australia/Lord_Howe", "Pacific/Chatham", "Pacific/Kiritimati"
    ].compactMap { TimeZone(identifier: $0) } + [64_800, -64_800, 37].compactMap { TimeZone(secondsFromGMT: $0) }

    /// Twelve sweep zones: none (UTC) and every named or fixed zone above.
    private static let zones: [TimeZone?] = [nil] + namedZones

    /// Ties, fractions, a repeated DST hour, the year 0 and 9999 boundaries, the 1582 reform, Foundation's
    /// far-future clamp, and instants with no millisecond count.
    private static let edges: [Date] = {
        let instants: [TimeInterval] = [
            0.0005, 0.0015, -0.0005, -0.0015, 0.9995, 1.0005, 1_787_148_600.251, 1_787_148_600.25,
            1_793_521_800, 1_793_525_400, 253_402_300_799, 253_402_300_799.9995, 253_402_300_800, 253_402_290_000,
            -62_135_596_800, -62_135_596_801, -62_167_219_200, -62_200_000_000, -2_208_988_800,
            1e13, 1e15, 9.2e15, 1e21, -1e21, .nan, .infinity, -.infinity
        ]
        let aroundReform: [TimeInterval] = [0, 1, -1, 3_600, -3_600, 50_400, -50_400, 64_800, -64_800, 86_400, -86_400, 172_800]
        return (instants + aroundReform.map { $0 - 12_219_292_800 }).map { Date(timeIntervalSince1970: $0) } + [.distantPast, .distantFuture]
    }()

    /// Local seconds since 1970 from 1582-10-15T00:00 through 9999-12-31T23:59:59: the only local times at which
    /// Foundation's Gregorian calendar is proleptic Gregorian, so the only ones it can check the kernel at.
    private static let foundationWindow: Swift.Range<Int64> = -12_219_292_800 ..< 253_402_300_800

    /// A third each: years −90 through 10200, the decades around the 1582 reform, and 1970 through 2039;
    /// a ±0.5 ms jitter puts exact and near half-millisecond ties in every range.
    private static func sweepInstant(_ generator: inout SeededGenerator) -> Date {
        let range: ClosedRange<Int64> = switch generator.next() % 3 {
        case 0: -65_000_000_000_000...260_000_000_000_000
        case 1: -13_000_000_000_000 ... -11_000_000_000_000
        default: 0...2_200_000_000_000
        }
        let milliseconds = Int64.random(in: range, using: &generator)
        let jitter = Double(Int.random(in: -500...500, using: &generator)) / 1_000_000
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000 + jitter)
    }

    /// Foundation's `[year, month, day, hour, minute, second, offset]` for a whole UTC second at a fixed offset,
    /// or none when the local time lies outside ``foundationWindow``.
    private static func foundationFields(seconds: Int64, offset: Int) -> [Int] {
        guard foundationWindow.contains(seconds + Int64(offset)), let zone = TimeZone(secondsFromGMT: offset) else {
            return []
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(seconds))
        )
        return [parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second].compactMap(\.self) + [offset]
    }

    /// The same fields of a built date-time, its seconds truncated to the whole second, or none without one.
    private static func fields(_ dateTime: DateTime?) -> [Int] {
        guard let dateTime, let time = dateTime.time, let zone = dateTime.timeZone else {
            return []
        }
        // `NSDecimalNumber.intValue` misreads long mantissas, so the seconds are rounded as a Decimal first.
        var second = time.second
        var wholeSecond = Decimal()
        NSDecimalRound(&wholeSecond, &second, 0, .down)
        let date = dateTime.date
        return [date.year, Int(date.month ?? 0), Int(date.day ?? 0), Int(time.hour), Int(time.minute)]
            + [NSDecimalNumber(decimal: wholeSecond).intValue, zone.secondsFromGMT()]
    }

    /// `nil` when a Mobile instant whose local time Foundation can check has Foundation's fields; refusals, among
    /// them offsets beyond the ±14 h a FHIR date-time states, and pre-reform dates are pinned separately.
    private static func mobileMismatch(_ date: Date, zone: TimeZone?) -> String? {
        let offset = zone?.secondsFromGMT(for: date) ?? 0
        guard let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1_000).rounded(.toNearestOrEven)),
              offset.isMultiple(of: 60),
              abs(offset) <= 50_400 else {
            return nil
        }
        let expected = foundationFields(seconds: ExchangeInstant.floorDivide(milliseconds, by: 1_000).quotient, offset: offset)
        guard !expected.isEmpty else {
            return nil
        }
        let actual = fields((try? HealthKitEffectiveTime.dateTime(date, zone: zone))?.value)
        return actual == expected ? nil : "\(date.timeIntervalSince1970) \(zone?.identifier ?? "none"): \(actual) != \(expected)"
    }

    /// `nil` when an ECG instant a whole number of seconds after `date` has Foundation's fields at the zone's
    /// fixed offset, wherever Foundation can check it.
    private static func ecgMismatch(_ date: Date, offset: Int, zone: TimeZone) -> String? {
        guard let since1970 = Int64(exactly: date.timeIntervalSince1970.rounded(.down)) else {
            return nil
        }
        let wholeSeconds = since1970 + Int64(offset)
        let zoneOffset = zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(wholeSeconds)))
        let expected = foundationFields(seconds: wholeSeconds, offset: zoneOffset)
        guard !expected.isEmpty else {
            return nil
        }
        let actual = fields(try? HealthKitEffectiveTime.exactDateTime(date, offset: Decimal(offset), zone: zone))
        return actual == expected ? nil : "\(date.timeIntervalSince1970)+\(offset) \(zone.identifier): \(actual) != \(expected)"
    }

    @Test("Every sweep zone resolves")
    func sweepZones() {
        #expect(Self.zones.count == 13)
        #expect(Self.namedZones.count == 12)
    }

    @Test("Mobile instants have Foundation's fields over the seeded sweep and the edge list")
    func mobileSweep() {
        var generator = SeededGenerator(state: 0x4D32_4D6F_6269_6C65)
        var mismatches: [String] = []
        for zone in Self.zones {
            for index in 0..<(Self.edges.count + Self.sweepCount) {
                let date = index < Self.edges.count ? Self.edges[index] : Self.sweepInstant(&generator)
                if let mismatch = autoreleasepool(invoking: { Self.mobileMismatch(date, zone: zone) }) {
                    mismatches.append(mismatch)
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches: \(mismatches.prefix(20))")
    }

    @Test("ECG instants have Foundation's fields over the seeded sweep and the edge list")
    func ecgSweep() {
        var generator = SeededGenerator(state: 0x4D32_4543_4721_2121)
        var mismatches: [String] = []
        for zone in Self.zones {
            for index in 0..<(Self.edges.count + Self.sweepCount) {
                let date = index < Self.edges.count ? Self.edges[index] : Self.sweepInstant(&generator)
                let offset = Int.random(in: 0...40, using: &generator)
                if let mismatch = autoreleasepool(invoking: { Self.ecgMismatch(date, offset: offset, zone: zone ?? .gmt) }) {
                    mismatches.append(mismatch)
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches: \(mismatches.prefix(20))")
    }

    /// `ExchangeInstant` counts milliseconds from 2001, so this half-millisecond tie rounds up there and down here.
    @Test("Mobile milliseconds round half to even from 1970, never through ExchangeInstant")
    func roundingGuard() throws {
        let date = Date(timeIntervalSinceReferenceDate: 713_073_860.2815)
        #expect(try HealthKitEffectiveTime.dateTime(date, zone: nil).value?.description == "2023-08-07T04:04:20.281Z")
        #expect(ExchangeInstant.utcLexeme(date) == "2023-08-07T04:04:20.282Z")
    }

    @Test("A named zone states its offset at the instant and travels as the timezone extension")
    func zoneOffsetAndExtension() throws {
        let kathmandu = try #require(TimeZone(identifier: "Asia/Kathmandu"))
        let dateTime = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: 1_787_148_600.25), zone: kathmandu)
        #expect(dateTime.value?.description == "2026-08-19T19:55:00.250+05:45")
        #expect(dateTime.extension == [Extension(url: Canonicals.timezone, value: .code("Asia/Kathmandu"))])
        let utc = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: 1_787_148_600), zone: nil)
        #expect(utc.value?.description == "2026-08-19T14:10:00Z")
        #expect(utc.extension == nil)
    }

    @Test("Both occurrences of a repeated DST hour keep their own offset")
    func repeatedHour() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let first = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: 1_793_521_800), zone: losAngeles)
        let second = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: 1_793_525_400), zone: losAngeles)
        #expect(first.value?.description == "2026-11-01T01:30:00-07:00")
        #expect(second.value?.description == "2026-11-01T01:30:00-08:00")
    }

    @Test("Instants with no Mobile lexeme are refused")
    func refusals() throws {
        let seconds = try #require(TimeZone(secondsFromGMT: 37))
        let kiritimati = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let refused: [(TimeInterval, TimeZone?)] = [
            (.infinity, nil), (.nan, nil), (1e21, nil), (1_787_148_600, seconds),
            (253_402_300_799.9995, nil), (253_402_290_000, kiritimati), (1_787_148_600, TimeZone(secondsFromGMT: 64_800))
        ]
        for (since1970, zone) in refused {
            #expect(throws: HealthKitValueFailure.shapeInvalid) {
                try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: since1970), zone: zone)
            }
        }
    }

    /// Foundation's Gregorian calendar is Julian before 1582-10-15 and counts years by era; FHIR dates are proleptic
    /// Gregorian from 0001 (owner decision D2).
    @Test("Local times before the 1582 reform take proleptic Gregorian dates, and year 0 is refused")
    func preReformDatesAreProleptic() throws {
        let mobile: [(TimeInterval, String)] = [
            (-12_219_292_801, "1582-10-14T23:59:59Z"), (-12_219_292_800, "1582-10-15T00:00:00Z"),
            (-14_831_769_600, "1500-01-01T00:00:00Z"), (-62_135_596_800, "0001-01-01T00:00:00Z")
        ]
        for (since1970, expected) in mobile {
            #expect(try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: since1970), zone: nil).value?.description == expected)
        }
        let lastJulianSecond = Date(timeIntervalSince1970: -12_219_292_801)
        #expect(try HealthKitEffectiveTime.exactDateTime(lastJulianSecond, offset: 0.25, zone: .gmt).description == "1582-10-14T23:59:59.25Z")
        let yearZero = Date(timeIntervalSince1970: -62_135_596_801)
        #expect(throws: HealthKitValueFailure.shapeInvalid) {
            try HealthKitEffectiveTime.dateTime(yearZero, zone: nil)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)) {
            try HealthKitEffectiveTime.exactDateTime(yearZero, offset: 0, zone: .gmt)
        }
    }

    @Test("An instant rule takes the start; an interval rule takes start and end and refuses what no Period states")
    func effectiveRules() throws {
        let start = Date(timeIntervalSince1970: 1_787_148_600)
        let end = start.addingTimeInterval(45)
        #expect(try EffectiveRule.instant.value(start: start, end: end, zone: nil)
            == .dateTime(HealthKitEffectiveTime.dateTime(start, zone: nil)))
        #expect(try EffectiveRule.interval(nonZero: true).value(start: start, end: end, zone: nil)
            == .period(HealthKitEffectiveTime.period(start: start, end: end, zone: nil)))
        #expect(try EffectiveRule.interval(nonZero: false).value(start: start, end: start, zone: nil)
            == .period(HealthKitEffectiveTime.period(start: start, end: start, zone: nil)))
        #expect(throws: HealthKitValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.interval(nonZero: true).value(start: start, end: start, zone: nil)
        }
        #expect(throws: HealthKitValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.interval(nonZero: false).value(start: end, end: start, zone: nil)
        }
    }

    @Test("ECG instants keep exact Decimal seconds at the zone's fixed offset, without a timezone extension")
    func ecgExactSeconds() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let dateTime = try HealthKitEffectiveTime.exactDateTime(
            Date(timeIntervalSince1970: 1_793_525_400),
            offset: 0.25,
            zone: losAngeles
        )
        #expect(dateTime.description == "2026-11-01T01:30:00.25-08:00")
        #expect(throws: HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)) {
            try HealthKitEffectiveTime.exactDateTime(Date(timeIntervalSince1970: .nan), offset: 0, zone: losAngeles)
        }
    }
}

#endif
