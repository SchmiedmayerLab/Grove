//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import RuntimeAssertions


@usableFromInline
func tryUnwrap<T>(_ value: T?, _ message: String) -> T {
    if let value {
        return value
    } else {
        preconditionFailure(message)
    }
}


extension Calendar {
    /// Returns a `Date` which represents the start of the hour into which `date` falls.
    public func startOfHour(for date: Date) -> Date {
        var retval = date
        for component in [Calendar.Component.minute, .second, .nanosecond] {
            retval = tryUnwrap(
                self.date(bySettingComponentToZero: component, of: retval, adjustOtherComponents: false),
                "Unable to compute start of hour"
            )
        }
        return retval
    }
    
    /// Returns a `Date` which represents the start of the next hour, relative to `date`.
    public func startOfNextHour(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .hour, value: 1, to: startOfHour(for: date)),
            "Unable to compute start of next hour"
        )
    }
    
    /// Returns a `Range<Date>` representing the range of the hour into which `date` falls.
    @inlinable
    public func rangeOfHour(for date: Date) -> Range<Date> {
        startOfHour(for: date)..<startOfNextHour(for: date)
    }

    
    /// Returns a `Date` which represents the start of the next day, relative to `date`.
    @inlinable
    public func startOfNextDay(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .day, value: 1, to: startOfDay(for: date)),
            "Unable to compute start of next day"
        )
    }
    
    /// Returns a `Date` which represents the start of the previous day, relative to `date`.
    @inlinable
    public func startOfPrevDay(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .day, value: -1, to: startOfDay(for: date)),
            "Unable to compute start of previous day"
        )
    }
    
    /// Returns a `Range<Date>` representing the range of the day into which `date` falls.
    @inlinable
    public func rangeOfDay(for date: Date) -> Range<Date> {
        startOfDay(for: date)..<startOfNextDay(for: date)
    }
    
    
    /// Returns a `Date` which represents the start of the week into which `date` falls.
    public func startOfWeek(for date: Date) -> Date {
        let date = self.startOfDay(for: date)
        var weekday = self.component(.weekday, from: date)
        // We have to adjust the weekday to avoid going into the next week instead.
        // The issue here is that firstWeekday can be larger than the current weekday,
        // in which case `weekdayDiff` is a) negative and b) incorrect, even if we look at the absolute value.
        // Example: We're in the german locale (firstWeekday = Monday) and the day represents a Sunday.
        // Since `Calendar`'s weekday numbers start at Sunday=1, we'd calculate diff = sunday - firstWeekday = sunday - monday = 1 - 2 = -1.
        // But what we actually want is diff = sunday - monday = 6
        if weekday < self.firstWeekday {
            weekday += self.weekdaySymbols.count
        }
        let weekdayDiff = weekday - self.firstWeekday
        return tryUnwrap(
            self.date(byAdding: .weekday, value: -weekdayDiff, to: date),
            "Unable to compute start of next week"
        )
    }
    
    /// Returns a `Date` which represents the start of the next week, relative to `date`.
    @inlinable
    public func startOfNextWeek(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .weekOfYear, value: 1, to: startOfWeek(for: date)),
            "Unable to compute start of next week"
        )
    }
    
    /// Returns a `Range<Date>` representing the range of the week into which `date` falls.
    @inlinable
    public func rangeOfWeek(for date: Date) -> Range<Date> {
        startOfWeek(for: date)..<startOfNextWeek(for: date)
    }
    
    
    /// Returns a `Date` which represents the start of the month into which `date` falls.
    public func startOfMonth(for date: Date) -> Date {
        var adjustedDate = self.startOfDay(for: date)
        adjustedDate = tryUnwrap(
            self.date(bySetting: .day, value: 1, of: adjustedDate),
            "Unable to compute start of month"
        )
        if adjustedDate > date {
            // Setting the day to 1 made the date larger, i.e. moved it one month ahead :/
            return tryUnwrap(
                self.date(byAdding: .month, value: -1, to: adjustedDate),
                "Unable to compute start of month"
            )
        } else {
            // we were able to set the day to 1, and can simply return the date.
            return adjustedDate
        }
    }
    
    /// Returns a `Date` which represents the start of the next month, relative to `date`.
    @inlinable
    public func startOfNextMonth(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .month, value: 1, to: startOfMonth(for: date)),
            "Unable to compute start of next month"
        )
    }
    
    
    /// Returns the exclusive range from the beginning of the month into which `date` falls, to the beginning of the next
    @inlinable
    public func rangeOfMonth(for date: Date) -> Range<Date> {
        startOfMonth(for: date)..<startOfNextMonth(for: date)
    }
    
    
    /// Returns a `Date` which represents the start of the year into which `date` falls.
    public func startOfYear(for date: Date) -> Date {
        var adjustedDate = startOfMonth(for: date)
        adjustedDate = tryUnwrap(
            self.date(bySetting: .month, value: 1, of: adjustedDate),
            "Unable to compute start of year"
        )
        if adjustedDate > date {
            // Setting the month to 1 made the date larger, i.e. moved it one year ahead :/
            return tryUnwrap(
                self.date(byAdding: .year, value: -1, to: adjustedDate),
                "Unable to compute start of year"
            )
        } else {
            // we were able to set the month to 1, and can simply return the date.
            return adjustedDate
        }
    }
    
    
    /// Returns a `Date` which represents the start of the previous year, relative to `date`.
    @inlinable
    public func startOfPrevYear(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .year, value: -1, to: startOfYear(for: date)),
            "Unable to compute start of previous year"
        )
    }
    
    /// Returns a `Date` which represents the start of the next year, relative to `date`.
    @inlinable
    public func startOfNextYear(for date: Date) -> Date {
        tryUnwrap(
            self.date(byAdding: .year, value: 1, to: startOfYear(for: date)),
            "Unable to compute start of next year"
        )
    }
    
    /// Returns a `Range<Date>` representing the range of the year into which `date` falls.
    @inlinable
    public func rangeOfYear(for date: Date) -> Range<Date> {
        startOfYear(for: date)..<startOfNextYear(for: date)
    }
}


// MARK: Date Distances

extension Calendar {
    private func _countDistinctNumberOfComponentUnits(
        from startDate: Date,
        to endDate: Date,
        for component: Calendar.Component,
        startOfComponentFn: (Date) -> Date
    ) -> Int {
        guard startDate <= endDate else {
            return _countDistinctNumberOfComponentUnits(
                from: endDate,
                to: startDate,
                for: component,
                startOfComponentFn: startOfComponentFn
            )
        }
        if startDate == endDate {
            return 1
        } else if self.isDate(startDate, equalTo: endDate, toGranularity: component) {
            return 1
        } else {
            let diff = self.dateComponents(
                [component],
                from: startOfComponentFn(startDate),
                to: startOfComponentFn(endDate)
            )
            return tryUnwrap(diff.value(for: component), "Unable to get component '\(component)'") + 1
        }
    }
    
    
    /// Returns the number of distinct weeks between the two dates.
    ///
    /// E.g., if the first date is `2021-02-02 07:20` and the second is `2021-02-02 08:05`, this would return 2.
    public func countDistinctHours(from startDate: Date, to endDate: Date) -> Int {
        _countDistinctNumberOfComponentUnits(
            from: startDate,
            to: endDate,
            for: .hour,
            startOfComponentFn: startOfHour
        )
    }
    
    /// Returns the number of distinct weeks between the two dates.
    ///
    /// E.g., if the first date is `2021-02-02 09:00` and the second is `2021-02-03 07:00`, this would return 2.
    public func countDistinctDays(from startDate: Date, to endDate: Date) -> Int {
        _countDistinctNumberOfComponentUnits(
            from: startDate,
            to: endDate,
            for: .day,
            startOfComponentFn: startOfDay
        )
    }
    
    /// Returns the number of distinct weeks between the two dates.
    ///
    /// E.g., if the first date is `2021-02-07` and the second is `2021-02-09`, this would return 2.
    public func countDistinctWeeks(from startDate: Date, to endDate: Date) -> Int {
        _countDistinctNumberOfComponentUnits(
            from: startDate,
            to: endDate,
            for: .weekOfYear,
            startOfComponentFn: startOfWeek
        )
    }
    
    /// Returns the number of distinct months between the two dates.
    ///
    /// E.g., if the first date is `2021-02-25` and the second is `2021-04-12`, this would return 3.
    public func countDistinctMonths(from startDate: Date, to endDate: Date) -> Int {
        _countDistinctNumberOfComponentUnits(
            from: startDate,
            to: endDate,
            for: .month,
            startOfComponentFn: startOfMonth
        )
    }
    
    /// Returns the number of distinct years between the two dates.
    ///
    /// E.g., if the first date is `2021-02-25` and the second is `2022-02-25`, this would return 2.
    public func countDistinctYears(from startDate: Date, to endDate: Date) -> Int {
        _countDistinctNumberOfComponentUnits(
            from: startDate,
            to: endDate,
            for: .year,
            startOfComponentFn: startOfYear
        )
    }
    
    /// Returns the number of days `endDate` is offset from `startDate`.
    public func offsetInDays(from startDate: Date, to endDate: Date) -> Int {
        guard !isDate(startDate, inSameDayAs: endDate) else {
            return 0
        }
        if startDate < endDate {
            return countDistinctDays(from: startDate, to: endDate) - 1
        } else {
            return -(countDistinctDays(from: endDate, to: startDate) - 1)
        }
    }
    
    /// Returns the number of days in the month into which `date` falls.
    public func numberOfDaysInMonth(for date: Date) -> Int {
        tryUnwrap(
            self.range(of: .day, in: .month, for: date),
            "Unable to get range of month"
        ).count
    }
}


extension Calendar {
    /// Computes a new `Date` by setting a component to zero.
    /// - parameter component: The component to set to zero.
    /// - parameter adjustOtherComponents: Determines whether the other components in the date should be adjusted when changing the component.
    private func date(bySettingComponentToZero component: Component, of date: Date, adjustOtherComponents: Bool) -> Date? {
        if adjustOtherComponents {
            // If we're asked to adjust the other components, we can use Calendar's -date(bySetting...) function.
            return self.date(bySetting: component, value: 0, of: date)
        } else {
            // Otherwise, we perform the adjustment manually, by subtracting the component's value from the date.
            let componentValue = self.component(component, from: date)
            return self.date(byAdding: component, value: -componentValue, to: date, wrappingComponents: true)
        }
    }
}


// MARK: DST

extension TimeZone {
    /// Information about a daylight saving time transition.
    public struct DSTTransition {
        /// The instant when the transition happens
        public let date: Date
        /// The amount of seconds by which this transition changes clocks
        public let change: TimeInterval
    }
    
    /// The time zone's next DST transition.
    /// - parameter date: The reference date for the DST transition check.
    /// - returns: A ``DSTTransition`` object with information about the first DST transition that will occur after `date`, in the current time zone.
    ///     `nil` if the time zone was unable to determine the next transition.
    public func nextDSTTransition(after date: Date = .now) -> DSTTransition? {
        guard let nextDST = nextDaylightSavingTimeTransition(after: date) else {
            return nil
        }
        let before = nextDST.addingTimeInterval(-1)
        let after = nextDST.addingTimeInterval(1)
        return DSTTransition(
            date: nextDST,
            change: daylightSavingTimeOffset(for: after) - daylightSavingTimeOffset(for: before)
        )
    }
    
    
    /// Returns the next `maxCount` daylight saving time transitions.
    public func nextDSTTransitions(maxCount: Int) -> [DSTTransition] {
        var transitions: [DSTTransition] = []
        while transitions.count < maxCount, let next = self.nextDSTTransition(after: transitions.last?.date ?? Date()) {
            transitions.append(next)
        }
        return transitions
    }
}


// MARK: Time Zones

extension TimeZone {
    // swiftlint:disable force_unwrapping
    /// The time zone for LA.
    public static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    /// The time zone for Berlin.
    public static let berlin = TimeZone(identifier: "Europe/Berlin")!
    // swiftlint:enable force_unwrapping
}
