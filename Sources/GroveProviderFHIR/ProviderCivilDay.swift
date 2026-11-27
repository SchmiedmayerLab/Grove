//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// An exact source calendar day in its time zone. A day across a clock change need not last twenty-four hours.
public struct ProviderCivilDay: Sendable {
    /// The year.
    public let year: Int
    /// The month, from 1 through 12.
    public let month: Int
    /// The day of the month.
    public let day: Int
    /// The time zone of the day.
    public let timeZone: TimeZone
    /// The day from its midnight to the next midnight in its time zone.
    public let interval: DateInterval

    /// Creates a day, refusing a date that doesn't exist in the time zone.
    public init(year: Int, month: Int, day: Int, timeZone: TimeZone) throws(ProviderConversionError) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw .invalidCivilDay
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day)
        guard let candidate = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day], from: candidate) == components,
            let interval = calendar.dateInterval(of: .day, for: candidate)
        else {
            throw .invalidCivilDay
        }
        self.year = year
        self.month = month
        self.day = day
        self.timeZone = timeZone
        self.interval = interval
    }

    /// A source-defined day whose boundary is a local wall-clock hour on this date and the following date.
    /// Nonexistent boundary times are refused rather than shifted, and daylight-saving transitions retain their duration.
    public func interval(startingAt hour: Int) throws(ProviderConversionError) -> DateInterval {
        guard (0...23).contains(hour) else { throw .invalidCivilDay }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func boundary(on date: Date) throws(ProviderConversionError) -> Date {
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = 0
            components.second = 0
            guard let result = calendar.date(from: components),
                calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result) == components else {
                throw .invalidCivilDay
            }
            return result
        }
        let start = try boundary(on: interval.start)
        let end = try boundary(on: interval.end)
        guard start < end else { throw .invalidCivilDay }
        return DateInterval(start: start, end: end)
    }
}
