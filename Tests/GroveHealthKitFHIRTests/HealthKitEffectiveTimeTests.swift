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


/// An ECG instant: its wall-clock fields to the minute, its exact seconds, and its offset from UTC in seconds.
private struct ExactInstant: Equatable, CustomStringConvertible {
    /// Year, month, day, hour and minute.
    let fields: [Int]
    /// The seconds, exact.
    let second: Decimal
    /// The offset from UTC.
    let offset: Int

    var description: String {
        "\(fields) \(second)s \(offset)"
    }
}


/// The civil-arithmetic effective-time kernel against Foundation's Gregorian calendar where that calendar is
/// proleptic, its proleptic dates before the 1582 reform, the behaviour each builder keeps, and the date-times it
/// reads back to the instants they state.
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

    /// Named zones with odd, LMT, non-hour and DST offsets, plus both ±18 h extremes and a 37-second offset.
    private static let namedZones: [TimeZone] = [
        "America/Los_Angeles", "Asia/Kolkata", "Asia/Kathmandu", "America/St_Johns", "Europe/Amsterdam",
        "Africa/Monrovia", "Australia/Lord_Howe", "Pacific/Chatham", "Pacific/Kiritimati"
    ].compactMap { TimeZone(identifier: $0) } + [64_800, -64_800, 37].compactMap { TimeZone(secondsFromGMT: $0) }

    /// Thirteen sweep zones: none (UTC) and every named or fixed zone above.
    private static let zones: [TimeZone?] = [nil] + namedZones

    /// Ties, near ties whose binary64 product rounds the other way, fractions, a repeated DST hour, instants that
    /// round onto Los Angeles's 2026 transitions, the year 0 and 9999 boundaries, the 1582 reform, Foundation's
    /// far-future clamp, and instants with no millisecond count.
    private static let edges: [Date] = {
        let instants: [TimeInterval] = [
            0.0005, 0.0015, -0.0005, -0.0015, 0.9995, 1.0005, 1_787_148_600.251, 1_787_148_600.25,
            1_790_638_382.1925, 1_795_885_209.9215, 1_772_963_999.9997, 1_793_523_599.9997,
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

    /// Local mean times no FHIR date-time states: Sitka's +14:58:47 and Guam's −14:21 in 1800, and Los Angeles's
    /// −07:52:58 in 1500.
    private static let unstatableLocalMeanTimes: [(instant: TimeInterval, zone: TimeZone?)] = [
        (-5_364_662_400, TimeZone(identifier: "America/Sitka")), (-5_364_662_400, TimeZone(identifier: "Pacific/Guam")),
        (-14_831_769_600, TimeZone(identifier: "America/Los_Angeles"))
    ]

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

    /// An ECG voltage offset of up to 40 seconds: a whole number of them plus a fraction that completes an edge's
    /// second (0.0005, 0.9995), a quarter or half second, or any microsecond.
    private static func ecgOffset(_ generator: inout SeededGenerator) -> Decimal {
        let microseconds = [0, 500, 250_000, 500_000, 999_500, Int.random(in: 0..<1_000_000, using: &generator)]
        let fraction = microseconds[Int.random(in: microseconds.indices, using: &generator)]
        return Decimal(Int.random(in: 0...40, using: &generator)) + Decimal(sign: .plus, exponent: -6, significand: Decimal(fraction))
    }

    /// Foundation's `[year, month, day, hour, minute, second]` for a whole UTC second at a fixed offset, or none when
    /// the local time lies outside ``foundationWindow``.
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
        return [parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second].compactMap(\.self)
    }

    /// The exact instant's milliseconds since 1970, rounded half to even: `Date`'s binary64 seconds since 2001 taken
    /// apart into an integer significand and a power of two and rounded in integers, a route independent of the
    /// kernel's fused multiply-add. `nil` from 2^40 seconds on, which no statable year reaches.
    private static func exactMilliseconds(_ date: Date) -> Int64? {
        let seconds = date.timeIntervalSinceReferenceDate
        guard seconds.isFinite, seconds.magnitude < 0x1p40 else {
            return nil
        }
        // The magnitude is significand / 2^shift; a shift past 64 leaves less than a quarter millisecond.
        let shift = seconds == 0 ? 65 : 52 - Int(seconds.exponent)
        guard shift <= 64 else {
            return 978_307_200_000
        }
        let scaled = UInt64(seconds.significand * 0x1p52) * 1_000
        let quotient = scaled >> shift
        let remainder = scaled - (quotient << shift)
        let half = UInt64(1) << (shift - 1)
        let rounded = Int64(remainder > half || (remainder == half && !quotient.isMultiple(of: 2)) ? quotient + 1 : quotient)
        return (seconds < 0 ? -rounded : rounded) + 978_307_200_000
    }

    /// The Mobile lexeme of `date` in `zone` that Foundation's fields state: the exact instant rounded to the
    /// millisecond, ties to even; the fields of its whole second at the offset the zone has at that rounded instant;
    /// `.mmm` when a millisecond remains; the offset, `Z` for none. `nil` where Foundation cannot check the kernel:
    /// an offset the kernel refuses (not whole minutes, or beyond the ±14 h a FHIR date-time states) or a local time
    /// outside ``foundationWindow``; those refusals and the proleptic dates before the reform are pinned separately.
    private static func foundationLexeme(_ date: Date, zone: TimeZone?) -> String? {
        guard let milliseconds = exactMilliseconds(date) else {
            return nil
        }
        let offset = zone?.secondsFromGMT(for: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)) ?? 0
        guard offset.isMultiple(of: 60), abs(offset) <= 50_400 else {
            return nil
        }
        let millisecond = (milliseconds % 1_000 + 1_000) % 1_000
        let fields = foundationFields(seconds: (milliseconds - millisecond) / 1_000, offset: offset)
        guard fields.count == 6 else {
            return nil
        }
        let wallClock = String(format: "%04ld-%02ld-%02ldT%02ld:%02ld:%02ld", arguments: fields.map { $0 as CVarArg })
        let fraction = millisecond == 0 ? "" : String(format: ".%03lld", millisecond)
        let hoursAndMinutes = String(format: "%02ld:%02ld", abs(offset) / 3_600, abs(offset) % 3_600 / 60)
        return wallClock + fraction + (offset == 0 ? "Z" : (offset < 0 ? "-" : "+") + hoursAndMinutes)
    }

    /// `date` plus `offset` as Foundation's fields state it: the exact sum of the decimal `date`'s shortest text
    /// states and the offset, floored in Decimal to its whole second; the fields Foundation reads for that second at
    /// the offset the zone has then, with the remainder added to the second. `nil` where Foundation cannot check it,
    /// and for an offset no FHIR date-time states, whose refusal is pinned separately.
    private static func foundationInstant(_ date: Date, offset: Decimal, zone: TimeZone) -> ExactInstant? {
        let since1970 = date.timeIntervalSince1970
        guard since1970.isFinite, var exact = Decimal(string: since1970.description, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        exact += offset
        var whole = Decimal()
        NSDecimalRound(&whole, &exact, 0, .down)
        guard let seconds = Int64(whole.description) else {
            return nil
        }
        let zoneOffset = zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds)))
        let fields = foundationFields(seconds: seconds, offset: zoneOffset)
        guard fields.count == 6, zoneOffset.isMultiple(of: 60), abs(zoneOffset) <= 50_400 else {
            return nil
        }
        return ExactInstant(fields: Array(fields.prefix(5)), second: Decimal(fields[5]) + (exact - whole), offset: zoneOffset)
    }

    /// `nil` when a Mobile instant whose local time Foundation can check prints the lexeme Foundation's fields state.
    private static func mobileMismatch(_ date: Date, zone: TimeZone?) -> String? {
        guard let expected = foundationLexeme(date, zone: zone) else {
            return nil
        }
        let actual = (try? HealthKitEffectiveTime.dateTime(date, zone: zone))?.value?.description
        return actual == expected ? nil : "\(date.timeIntervalSince1970) \(zone?.identifier ?? "none"): \(actual ?? "refused") != \(expected)"
    }

    /// `nil` when an ECG instant, `date` plus `offset`, has Foundation's fields and exact seconds at the zone's fixed
    /// offset, wherever Foundation can check it.
    private static func ecgMismatch(_ date: Date, offset: Decimal, zone: TimeZone) -> String? {
        guard let expected = foundationInstant(date, offset: offset, zone: zone) else {
            return nil
        }
        let actual = (try? HealthKitEffectiveTime.exactDateTime(date, offset: offset, zone: zone)).flatMap { ExactInstant($0) }
        let stated = actual?.description ?? "refused"
        return actual == expected ? nil : "\(date.timeIntervalSince1970)+\(offset) \(zone.identifier): \(stated) != \(expected)"
    }

    @Test("Every sweep zone resolves")
    func sweepZones() {
        #expect(Self.zones.count == 13)
        #expect(Self.namedZones.count == 12)
    }

    @Test("Mobile instants print the lexeme of Foundation's fields, their milliseconds and their offset over the seeded sweep and the edge list")
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

    @Test("ECG instants offset by fractional seconds have Foundation's fields and exact seconds over the seeded sweep and the edge list")
    func ecgSweep() {
        var generator = SeededGenerator(state: 0x4D32_4543_4721_2121)
        var mismatches: [String] = []
        for zone in Self.zones {
            for index in 0..<(Self.edges.count + Self.sweepCount) {
                let date = index < Self.edges.count ? Self.edges[index] : Self.sweepInstant(&generator)
                let offset = Self.ecgOffset(&generator)
                if let mismatch = autoreleasepool(invoking: { Self.ecgMismatch(date, offset: offset, zone: zone ?? .gmt) }) {
                    mismatches.append(mismatch)
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches: \(mismatches.prefix(20))")
    }

    /// The IG rounds the exact instant. This one lies just below a half millisecond, but its binary64 product since 2001
    /// is the tie itself, which `ExchangeInstant` rounds up to even.
    @Test("Mobile milliseconds round the exact instant half to even, never through ExchangeInstant")
    func roundingGuard() throws {
        let date = Date(timeIntervalSinceReferenceDate: 713_073_860.2815)
        #expect(try HealthKitEffectiveTime.dateTime(date, zone: nil).value?.description == "2023-08-07T04:04:20.281Z")
        #expect(ExchangeInstant.utcLexeme(date) == "2023-08-07T04:04:20.282Z")
    }

    /// The first three lie beside a half millisecond, where their binary64 product since 1970 rounds the other way
    /// (`….192`, `….922` and `….404`). The second's and third's products since 2001, which the kernel takes, are
    /// themselves ties, which their rounding error breaks down and up, away from the even neighbour. The last two
    /// are exact ties.
    @Test("Mobile milliseconds round the exact instant, not its binary64 product, and break exact ties to even")
    func exactInstantRounding() throws {
        let instants: [(TimeInterval, String)] = [
            (1_790_638_382.1925, "2026-09-28T23:33:02.193Z"), (1_795_885_209.9215, "2026-11-28T17:00:09.921Z"),
            (1_792_530_829.4045, "2026-10-20T21:13:49.405Z"),
            (1_787_148_600.0625, "2026-08-19T14:10:00.062Z"), (1_787_148_600.1875, "2026-08-19T14:10:00.188Z")
        ]
        for (since1970, expected) in instants {
            #expect(try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: since1970), zone: nil).value?.description == expected)
        }
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

    /// The IG: the zone's name must agree with the offset at the instant, which is the rounded one.
    @Test("An instant that rounds onto a DST transition states the offset the zone has from then on")
    func offsetAtTheRoundedInstant() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let instants: [(TimeInterval, String)] = [
            (1_772_963_999.9997, "2026-03-08T03:00:00-07:00"), (1_772_963_999.9994, "2026-03-08T01:59:59.999-08:00"),
            (1_793_523_599.9997, "2026-11-01T01:00:00-08:00"), (1_793_523_599.9994, "2026-11-01T01:59:59.999-07:00")
        ]
        for (since1970, expected) in instants {
            #expect(try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: since1970), zone: losAngeles).value?.description == expected)
        }
    }

    @Test("Both occurrences of a repeated DST hour keep their own offset")
    func repeatedHour() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let first = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: 1_793_521_800), zone: losAngeles)
        let second = try HealthKitEffectiveTime.dateTime(Date(timeIntervalSince1970: 1_793_525_400), zone: losAngeles)
        #expect(first.value?.description == "2026-11-01T01:30:00-07:00")
        #expect(second.value?.description == "2026-11-01T01:30:00-08:00")
    }

    /// FHIR states an offset in whole minutes only, and the source's own must not be replaced: Monrovia kept -0:44:30
    /// until 1972, so its 1960 instants have no FHIR date-time.
    @Test("Instants with no Mobile lexeme are refused as no valid FHIR date-time")
    func refusals() throws {
        let seconds = try #require(TimeZone(secondsFromGMT: 37))
        let kiritimati = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let monrovia = try #require(TimeZone(identifier: "Africa/Monrovia"))
        let refused: [(TimeInterval, TimeZone?)] = [
            (.infinity, nil), (.nan, nil), (1e21, nil), (1_787_148_600, seconds), (1_787_148_600, TimeZone(secondsFromGMT: 1_172)),
            (-315_619_200, monrovia), (253_402_300_799.9995, nil), (253_402_300_800, nil), (253_402_290_000, kiritimati),
            (1_787_148_600, TimeZone(secondsFromGMT: 64_800)), (1_787_148_600, TimeZone(secondsFromGMT: 50_460))
        ] + Self.unstatableLocalMeanTimes.map { ($0.instant, $0.zone) }
        #expect(monrovia.secondsFromGMT(for: Date(timeIntervalSince1970: -315_619_200)) == -2_670)
        for (since1970, zone) in refused {
            #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
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
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try HealthKitEffectiveTime.dateTime(yearZero, zone: nil)
        }
        #expect(throws: HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)) {
            try HealthKitEffectiveTime.exactDateTime(yearZero, offset: 0, zone: .gmt)
        }
    }

    /// HealthKit cannot produce such an instant (`HKSample` refuses an end at or after 4001), but no FHIR date-time
    /// states a five-digit year.
    @Test("ECG instants whose local year passes 9999 are refused")
    func ecgYearTenThousandIsRefused() throws {
        let lastSecond = Date(timeIntervalSince1970: 253_402_300_799)
        #expect(try HealthKitEffectiveTime.exactDateTime(lastSecond, offset: 0.999, zone: .gmt).description == "9999-12-31T23:59:59.999Z")
        #expect(throws: HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)) {
            try HealthKitEffectiveTime.exactDateTime(lastSecond, offset: 1, zone: .gmt)
        }
        let oneHourEast = try #require(TimeZone(secondsFromGMT: 3_600))
        #expect(throws: HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)) {
            try HealthKitEffectiveTime.exactDateTime(Date(timeIntervalSince1970: 253_402_297_200), offset: 0, zone: oneHourEast)
        }
    }

    @Test("Mobile date-times read back to the millisecond they state over the seeded sweep and the edge list, also before the reform")
    func mobileRoundTrips() {
        // A read-back instant is within a binary64 rounding of the millisecond it states; the kernel states the exact
        // instant's millisecond, rounded half to even.
        let milliseconds = { (instant: Date) in Int64((instant.timeIntervalSince1970 * 1_000).rounded(.toNearestOrEven)) }
        var generator = SeededGenerator(state: 0x4D32_5265_7665_7273)
        var mismatches: [String] = []
        for zone in Self.zones {
            for index in 0..<(Self.edges.count + Self.sweepCount) {
                let date = index < Self.edges.count ? Self.edges[index] : Self.sweepInstant(&generator)
                guard let stated = try? HealthKitEffectiveTime.dateTime(date, zone: zone).value else {
                    continue
                }
                let read = HealthKitEffectiveTime.instant(of: stated)
                if read.map(milliseconds) != Self.exactMilliseconds(date) {
                    mismatches.append("\(date.timeIntervalSince1970) \(zone?.identifier ?? "none"): \(stated) reads \(read.map { "\($0.timeIntervalSince1970)" } ?? "nothing")")
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches: \(mismatches.prefix(20))")
    }

    /// A 512 Hz voltage sample lies 1/512 s (0.001953125 s) after its predecessor, so ECG seconds carry fractions finer
    /// than a millisecond.
    @Test("ECG date-times read back to their instant within one unit in the last place, sub-millisecond seconds included")
    func ecgRoundTrips() throws {
        func stated(_ since1970: TimeInterval, plus offset: Decimal, in zone: TimeZone = .gmt) throws -> DateTime {
            try HealthKitEffectiveTime.exactDateTime(Date(timeIntervalSince1970: since1970), offset: offset, zone: zone)
        }
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let indiaStandardTime = try #require(TimeZone(secondsFromGMT: 19_800))
        let instants: [(DateTime, TimeInterval)] = [
            (try stated(1_793_525_400, plus: 0.25, in: losAngeles), 1_793_525_400.25),
            (try stated(1_787_005_800, plus: 0.001_953_125, in: losAngeles), 1_787_005_800.001_953_125),
            (try stated(-12_219_292_801, plus: 0.25), -12_219_292_800.75),
            (try stated(-14_831_769_600, plus: 1.5, in: indiaStandardTime), -14_831_769_598.5),
            (try stated(-14_831_769_600, plus: 0.000_976_562_5, in: indiaStandardTime), -14_831_769_599.999_023_437_5),
            (try stated(-62_135_596_800, plus: 0.004), -62_135_596_799.996),
            (try stated(253_402_300_799, plus: 0.999), 253_402_300_799.999)
        ]
        for (dateTime, since1970) in instants {
            let read = try #require(HealthKitEffectiveTime.instant(of: dateTime))
            #expect(abs(read.timeIntervalSince1970 - since1970) <= since1970.ulp, "\(dateTime)")
        }
    }

    /// Foundation's calendar is proleptic from 1582-10-15 on, so there FHIRModels' `asNSDate()` checks every bit.
    @Test("From the reform on, a date-time reads exactly as asNSDate() does, fractions finer than a millisecond included")
    func readsAsFoundationAfterTheReform() throws {
        let lexemes = [
            "2026-08-17T22:30:00.2514Z", "2026-08-17T22:30:00.001953125Z", "2026-08-17T15:30:00.000001-07:00",
            "1582-10-15T00:00:00.0001Z", "9999-12-31T23:59:59.999999+05:45", "2026-08-17T22:30:59.9995+14:00"
        ]
        for lexeme in lexemes {
            let dateTime = try DateTime(lexeme)
            #expect(HealthKitEffectiveTime.instant(of: dateTime) == (try dateTime.asNSDate()), "\(lexeme)")
        }
    }

    @Test("A date-time reads back in the proleptic Gregorian calendar: a partial date at its first instant, no offset as UTC")
    func readsProlepticInstants() throws {
        let pinned: [(String, TimeInterval)] = [
            ("1582-10-14T23:59:59Z", -12_219_292_801), ("1582-10-15T00:00:00Z", -12_219_292_800),
            ("1582-10-04T23:59:59.250+01:00", -12_220_160_400.75), ("1500-01-01T00:00:00Z", -14_831_769_600),
            ("0001-01-01T00:00:00Z", -62_135_596_800), ("2026-08-17T15:30:00.250-07:00", 1_787_005_800.25),
            ("9999-12-31T23:59:59Z", 253_402_300_799), ("2026", 1_767_225_600), ("2026-08", 1_785_542_400),
            ("2026-08-17", 1_786_924_800), ("1500-01-01", -14_831_769_600)
        ]
        for (lexeme, since1970) in pinned {
            #expect(HealthKitEffectiveTime.instant(of: try DateTime(lexeme))?.timeIntervalSince1970 == since1970, "\(lexeme)")
        }
        let withoutOffset = DateTime(date: FHIRDate(year: 2026, month: 8, day: 17), time: FHIRTime(hour: 22, minute: 30, second: 0))
        #expect(HealthKitEffectiveTime.instant(of: withoutOffset)?.timeIntervalSince1970 == 1_787_005_800)
        for year in [0, -1, 10_000] {
            #expect(HealthKitEffectiveTime.instant(of: DateTime(date: FHIRDate(year: year, month: 1, day: 1))) == nil, "\(year)")
        }
    }

    /// Only a date-time built in memory names a zone; Foundation's calendar is proleptic here, so it checks the policy.
    /// The offset a day earlier is the old one, so each transition day is pinned again after its change.
    @Test("A named zone reads a repeated time as its first occurrence, a skipped one at the earlier offset, and a later one at the new offset")
    func namedZonesFollowFoundationAtTransitions() throws {
        func halfPast(_ hour: UInt8, on day: FHIRDate, in identifier: String) throws -> DateTime {
            DateTime(date: day, time: FHIRTime(hour: hour, minute: 30, second: 0), timezone: try #require(TimeZone(identifier: identifier)))
        }
        let pinned: [(DateTime, TimeInterval)] = [
            (try halfPast(1, on: FHIRDate(year: 2026, month: 11, day: 1), in: "America/Los_Angeles"), 1_793_521_800),
            (try halfPast(12, on: FHIRDate(year: 2026, month: 11, day: 1), in: "America/Los_Angeles"), 1_793_565_000),
            (try halfPast(2, on: FHIRDate(year: 2026, month: 3, day: 8), in: "America/Los_Angeles"), 1_772_965_800),
            (try halfPast(12, on: FHIRDate(year: 2026, month: 3, day: 8), in: "America/Los_Angeles"), 1_772_998_200),
            (try halfPast(2, on: FHIRDate(year: 2026, month: 10, day: 25), in: "Europe/Amsterdam"), 1_792_888_200),
            (try halfPast(12, on: FHIRDate(year: 2026, month: 10, day: 25), in: "Europe/Amsterdam"), 1_792_927_800),
            (try halfPast(2, on: FHIRDate(year: 2026, month: 3, day: 29), in: "Europe/Amsterdam"), 1_774_747_800),
            (try halfPast(4, on: FHIRDate(year: 2026, month: 3, day: 29), in: "Europe/Amsterdam"), 1_774_751_400)
        ]
        for (dateTime, since1970) in pinned {
            #expect(HealthKitEffectiveTime.instant(of: dateTime)?.timeIntervalSince1970 == since1970, "\(dateTime)")
            #expect(HealthKitEffectiveTime.instant(of: dateTime) == (try dateTime.asNSDate()), "\(dateTime)")
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
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.interval(nonZero: true).value(start: start, end: start, zone: nil)
        }
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.interval(nonZero: false).value(start: end, end: start, zone: nil)
        }
    }

    /// FHIRModels prints a fixed zone's offset truncated to whole minutes, so stating it would shift the time.
    @Test("ECG instants in a zone whose offset no FHIR date-time states are refused, and ±14:00 is stated")
    func ecgUnstatableOffsets() throws {
        let fixed = [37, 50_460, -50_460, 64_800].map { (instant: TimeInterval(1_787_148_600), zone: TimeZone(secondsFromGMT: $0)) }
        for (instant, zone) in Self.unstatableLocalMeanTimes + fixed {
            let zone = try #require(zone)
            #expect(throws: HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)) {
                try HealthKitEffectiveTime.exactDateTime(Date(timeIntervalSince1970: instant), offset: 0.25, zone: zone)
            }
        }
        for (seconds, expected) in [(50_400, "2026-08-20T04:10:00.25+14:00"), (-50_400, "2026-08-19T00:10:00.25-14:00")] {
            let zone = try #require(TimeZone(secondsFromGMT: seconds))
            #expect(try HealthKitEffectiveTime.exactDateTime(Date(timeIntervalSince1970: 1_787_148_600), offset: 0.25, zone: zone).description == expected)
        }
    }

    @Test("A Period is judged on the wire's half-even milliseconds, and an instant rule admits none")
    func periodsAreJudgedOnWireMilliseconds() throws {
        let start = Date(timeIntervalSince1970: 1_787_148_600)
        let subMillisecond = start.addingTimeInterval(0.0003)
        #expect(try EffectiveRule.interval(nonZero: true).admitsPeriod(from: start, to: subMillisecond) == false)
        #expect(try EffectiveRule.interval(nonZero: false).admitsPeriod(from: start, to: subMillisecond))
        #expect(try EffectiveRule.interval(nonZero: true).admitsPeriod(from: start, to: start.addingTimeInterval(0.0007)))
        #expect(try EffectiveRule.instant.admitsPeriod(from: start, to: start.addingTimeInterval(45)) == false)
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.interval(nonZero: false).admitsPeriod(from: start, to: Date(timeIntervalSince1970: .infinity))
        }
    }

    @Test("An instant-or-interval rule states a point when start and end state one wire millisecond, else a Period")
    func instantOrIntervalRule() throws {
        let start = Date(timeIntervalSince1970: 1_787_148_600)
        let end = start.addingTimeInterval(45)
        #expect(try EffectiveRule.instantOrInterval.value(start: start, end: end, zone: nil)
            == .period(HealthKitEffectiveTime.period(start: start, end: end, zone: nil)))
        #expect(try EffectiveRule.instantOrInterval.value(start: start, end: start.addingTimeInterval(0.0003), zone: nil)
            == .dateTime(HealthKitEffectiveTime.dateTime(start, zone: nil)))
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.instantOrInterval.value(start: end, end: start, zone: nil)
        }
        #expect(throws: HealthKitConversionError.ValueFailure.effectivePeriodInvalid) {
            try EffectiveRule.instantOrInterval.value(start: start, end: Date(timeIntervalSince1970: .infinity), zone: nil)
        }
        #expect(try EffectiveRule.instantOrInterval.admitsPeriod(from: start, to: start))
    }

    @Test("A measurement's rule is the effective datatype its profile fixes")
    func rulesFollowTheProfile() {
        #expect(EffectiveRule(MeasurementCatalog.respiratoryRate) == .instant)
        #expect(EffectiveRule(MeasurementCatalog.heartRate) == .instantOrInterval)
        #expect(EffectiveRule(MeasurementCatalog.stepCount) == .interval(nonZero: true))
        #expect(EffectiveRule(MeasurementCatalog.dietaryEnergy) == .interval(nonZero: false))
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


extension ExactInstant {
    /// The instant a built date-time states, or none without a time and an offset.
    init?(_ dateTime: DateTime) {
        guard let time = dateTime.time, let zone = dateTime.timeZone, let month = dateTime.date.month, let day = dateTime.date.day else {
            return nil
        }
        self.init(
            fields: [dateTime.date.year, Int(month), Int(day), Int(time.hour), Int(time.minute)],
            second: time.second,
            offset: zone.secondsFromGMT()
        )
    }
}

#endif
