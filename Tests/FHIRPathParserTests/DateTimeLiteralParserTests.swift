//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRPathParser
import Foundation
import Testing

@Suite
struct DateTimeLiteralParserTests {
    @Test
    func parseSimple() throws {
        do {
            let (result, timeZone) = try DateTimeLiteralParser.parse("@1998-06-02T13:15:00-05:00")
            #expect(result == .dateTime(.init(
                date: .init(year: 1998, month: 6, day: 2),
                time: DateTimeLiteralParser.Time(hour: 13, minute: 15, second: 0)
            )))
            #expect(timeZone == .init(secondsFromGMT: -18000))
        }
        do {
            let (result, timeZone) = try DateTimeLiteralParser.parse("@1998-06-03T02:15:00+08:00")
            #expect(result == .dateTime(.init(
                date: .init(year: 1998, month: 6, day: 3),
                time: DateTimeLiteralParser.Time(hour: 2, minute: 15, second: 0)
            )))
            #expect(timeZone == .init(secondsFromGMT: 28800))
        }
        do {
            let (result, timeZone) = try DateTimeLiteralParser.parse("@1998-06-02T18:15:00Z")
            #expect(result == .dateTime(.init(
                date: .init(year: 1998, month: 6, day: 2),
                time: DateTimeLiteralParser.Time(hour: 18, minute: 15, second: 0)
            )))
            #expect(timeZone == .init(secondsFromGMT: 0))
        }
        do {
            let (result, timeZone) = try DateTimeLiteralParser.parse("@2017-11-05T01:30:00-04:00")
            #expect(result == .dateTime(.init(
                date: .init(year: 2017, month: 11, day: 5),
                time: DateTimeLiteralParser.Time(hour: 1, minute: 30, second: 0)
            )))
            #expect(timeZone == .init(secondsFromGMT: -14400))
        }
    }
    
    @Test
    func timeOnly() throws {
        let inputs: [String: DateComponents] = [
            "@T10:30:00": .init(hour: 10, minute: 30, second: 0),
            "@T11:21:09": .init(hour: 11, minute: 21, second: 9),
            "@T14:34:28": .init(hour: 14, minute: 34, second: 28)
        ]
        for (input, expected) in inputs {
            let (result, timeZone) = try DateTimeLiteralParser.parse(input)
            #expect(timeZone == nil)
            switch result {
            case .time(let time):
                #expect(time.hour == expected.hour)
                #expect(time.minute == expected.minute)
                #expect(time.second == expected.second)
            case .date, .dateTime:
                Issue.record("Invalid result: expected a time, got \(result)")
            }
        }
    }

    @Test
    func partialPrecisionIsKept() throws {
        #expect(try DateTimeLiteralParser.parse("@2026").0 == .date(.init(year: 2026)))
        #expect(try DateTimeLiteralParser.parse("@2026-01").0 == .date(.init(year: 2026, month: 1)))
        #expect(try DateTimeLiteralParser.parse("@2026-01-15T").0 == .dateTime(.init(date: .init(year: 2026, month: 1, day: 15), time: nil)))
        #expect(try DateTimeLiteralParser.parse("@T10").0 == .time(try #require(DateTimeLiteralParser<String>.Time(hour: 10))))
        #expect(try DateTimeLiteralParser.parse("@T10:30").0 == .time(try #require(DateTimeLiteralParser<String>.Time(hour: 10, minute: 30))))
    }

    @Test(arguments: ["@0000", "@2026-00", "@2026-13", "@2026-02-29", "@2026-04-31", "@T24:00", "@T10:60", "@2026-01-01T10:00+14:30", "@2026-01-01T10:00-15:00"])
    func outOfRangeLiteralsFail(_ literal: String) {
        #expect(throws: DateTimeLiteralParser<String>.ParseError.self) {
            try DateTimeLiteralParser.parse(literal)
        }
    }

    @Test
    func leapDayIsADate() throws {
        #expect(try DateTimeLiteralParser.parse("@2024-02-29").0 == .date(.init(year: 2024, month: 2, day: 29)))
        #expect(try DateTimeLiteralParser.parse("@2026-01-01T10:00+14:00").1 == TimeZone(secondsFromGMT: 14 * 3600))
    }

    @Test
    func oversizedNumericComponentFailsInsteadOfOverflowing() {
        let oversizedYear = "@" + String(repeating: "9", count: 100)
        #expect(throws: DateTimeLiteralParser<String>.ParseError.self) {
            try DateTimeLiteralParser.parse(oversizedYear)
        }
    }
}
