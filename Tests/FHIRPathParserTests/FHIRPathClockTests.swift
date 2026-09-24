//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRPathParser
import Foundation
import Testing


@Suite(.serialized)
struct FHIRPathClockTests {
    /// 2026-01-01T07:30Z: still New Year's Eve in California, already New Year's Day in Tokyo.
    private static let instant = Date(timeIntervalSince1970: 1_767_252_600)

    private static func clock(offsetHours: Int) throws -> FHIRPathClock {
        FHIRPathClock(instant: instant, timeZone: try #require(TimeZone(secondsFromGMT: offsetHours * 3600)))
    }

    private static func today(_ clock: FHIRPathClock) throws -> (evaluated: [FHIRPathValue], legacy: DateComponents) {
        let evaluated = try FHIRPathExpression.evaluate(expression: "today()", context: .init(clock: clock))
        let legacy = try FHIRPathExpression.evaluate(expression: "today()", clock: clock, as: DateComponents.self)
        return (evaluated, legacy)
    }

    @Test
    func clockZoneDecidesToday() throws {
        let cases: [(offsetHours: Int, day: DateComponents)] = [
            (-8, DateComponents(year: 2025, month: 12, day: 31)),
            (9, DateComponents(year: 2026, month: 1, day: 1)),
            (0, DateComponents(year: 2026, month: 1, day: 1))
        ]
        for (offsetHours, day) in cases {
            let (evaluated, legacy) = try Self.today(Self.clock(offsetHours: offsetHours))
            #expect(evaluated == [.date(day)], "\(offsetHours)")
            #expect(legacy.year == day.year && legacy.month == day.month && legacy.day == day.day, "\(offsetHours)")
        }
    }

    @Test
    func evaluationIgnoresTheDeviceZone() throws {
        let clock = try Self.clock(offsetHours: -8)
        let expected = try Self.today(clock)
        let now = try FHIRPathExpression.evaluate(expression: "now()", context: .init(clock: clock))
        let deviceZone = NSTimeZone.default
        defer {
            NSTimeZone.default = deviceZone
        }
        for offsetHours in [14, -11] {
            NSTimeZone.default = try #require(TimeZone(secondsFromGMT: offsetHours * 3600))
            let today = try Self.today(clock)
            #expect(today.evaluated == expected.evaluated, "\(offsetHours)")
            #expect(today.legacy == expected.legacy, "\(offsetHours)")
            #expect(try FHIRPathExpression.evaluate(expression: "now()", context: .init(clock: clock)) == now, "\(offsetHours)")
        }
    }

    @Test
    func legacyAndContextEvaluatorsAgree() throws {
        let clock = try Self.clock(offsetHours: 9)
        for expression in ["today()", "today() + 3 months", "today() - 18 years", "now()"] {
            let evaluated = try FHIRPathExpression.evaluate(expression: expression, context: .init(clock: clock))
            let legacy = try FHIRPathExpression.evaluate(expression: expression, clock: clock, as: Date.self)
            let components: DateComponents
            switch try #require(evaluated.first) {
            case .date(let value), .dateTime(let value):
                components = value
            default:
                Issue.record("\(expression) is not temporal: \(evaluated)")
                continue
            }
            let calendar = FHIRPathCalendar.gregorian(timeZone: clock.timeZone)
            let legacyComponents = calendar.dateComponents([.year, .month, .day], from: legacy)
            #expect(legacyComponents.year == components.year, "\(expression)")
            #expect(legacyComponents.month == components.month, "\(expression)")
            #expect(legacyComponents.day == components.day, "\(expression)")
        }
    }

    @Test
    func nowStatesTheClockOffset() throws {
        let clock = try Self.clock(offsetHours: -8)
        let now = try FHIRPathExpression.evaluate(expression: "now()", context: .init(clock: clock))
        #expect(now == [.dateTime(DateComponents(timeZone: clock.timeZone, year: 2025, month: 12, day: 31, hour: 23, minute: 30, second: 0))])
    }
}
