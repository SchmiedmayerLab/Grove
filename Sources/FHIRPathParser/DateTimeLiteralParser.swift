//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


private let asciiDigits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]


/// Parser for ISO8601 DateTime literals as used in FHIRPath.
/// Implemented in conformance with the `DATE`, `DATETIME`, and `TIME` rules
/// [in the FHIRPath grammar](https://hl7.org/fhirpath/N1/grammar.html)
struct DateTimeLiteralParser<Input: StringProtocol>: ~Copyable {
    enum ParseError: Error {
        case unexpectedToken(expected: [Character], found: Character?)
        case invalidInput(reason: String)
        case unsupportedLiteral
    }
    
    /// A `Date` as defined by FHIRPath.
    struct Date: Equatable {
        var year: Int
        var month: Int?
        var day: Int?
        
        var components: DateComponents {
            DateComponents(year: year, month: month, day: day)
        }
    }
    
    /// A `Time` as defined by FHIRPath.
    struct Time: Equatable {
        var hour: Int
        var minute: Int?
        var second: Int?
        
        var components: DateComponents {
            DateComponents(hour: hour, minute: minute, second: second)
        }
        
        init?(hour: Int, minute: Int? = nil, second: Int? = nil) {
            guard (0..<24).contains(hour),
                  minute.map({ (0..<60).contains($0) }) ?? true,
                  second.map({ (0..<60).contains($0) }) ?? true,
                  second == nil || minute != nil else {
                return nil
            }
            self.hour = hour
            self.minute = minute
            self.second = second
        }
    }
    
    /// A `DateTime` as defined by FHIRPath.
    struct DateTime: Equatable {
        var date: Date
        var time: Time?
        
        var components: DateComponents {
            DateComponents(
                year: date.year,
                month: date.month,
                day: date.day,
                hour: time?.hour,
                minute: time?.minute,
                second: time?.second
            )
        }
    }
    
    enum Result: Equatable {
        case date(Date)
        case time(Time)
        case dateTime(DateTime)
    }
    
    private let input: Input
    private var position: Input.Index
    
    private var current: Character? {
        input[safe: position]
    }
    private var isAtEnd: Bool {
        position >= input.endIndex
    }
    
    
    private mutating func consume(_ count: Int = 1) {
        input.formIndex(&position, offsetBy: count)
    }
    
    /// Checks that the current token is equal to the specified expected value.
    /// If yes, the token is consumed (i.e., the position is advanced by 1).
    /// - Throws: if the current token is not equal to the specified expected value.
    private mutating func expectAndConsume(_ expected: Character) throws(ParseError) {
        if current == expected {
            consume()
        } else {
            throw .unexpectedToken(expected: [expected], found: current)
        }
    }
    
    /// Checks that the current token is equal to one of the specified expected values.
    /// If yes, the token is consumed (i.e., the position is advanced by 1).
    /// - parameter expected: Non-empty list of tokens we allow to appear at the current position.
    /// - Throws: if the current token is not equal to the specified expected value.
    /// - Returns: the token that matched.
    private mutating func expectAnyOfAndConsume(_ expected: [Character]) throws(ParseError) -> Character {
        if let current, expected.contains(current) {
            consume()
            return current
        } else {
            throw .unexpectedToken(expected: expected, found: current)
        }
    }
    
    
    /// Parses a decimal `Int`, consuming its digits and returning the resulting value.
    /// - Note: This function will consume tokens until it reaches the first which is not an ASCII decimal digit character.
    /// - Throws: if, when the function is called, the first token is not a decimal digit.
    private mutating func parseInt() throws(ParseError) -> Int {
        guard !isAtEnd else {
            throw .unexpectedToken(expected: asciiDigits, found: nil)
        }
        if let current, !asciiDigits.contains(current) {
            throw .unexpectedToken(expected: asciiDigits, found: current)
        }
        var value = 0
        while let current, asciiDigits.contains(current) {
            guard let asciiValue = current.asciiValue else {
                throw .unexpectedToken(expected: asciiDigits, found: current)
            }
            let (multiplied, multiplyOverflow) = value.multipliedReportingOverflow(by: 10)
            let (nextValue, additionOverflow) = multiplied.addingReportingOverflow(Int(asciiValue - 0x30))
            guard !multiplyOverflow, !additionOverflow else {
                throw .invalidInput(reason: "Numeric component is too large")
            }
            value = nextValue
            consume()
        }
        return value
    }
}


extension DateTimeLiteralParser {
    // MARK: Date/Time Literal Parsing
    
    /// Parses the provided string into a FHIRPath `Date` or `DateTime` type.
    /// - Returns: A tuple of a `Date` object representing the parse result, and the `TimeZone`
    ///     in which the date should be interpreted, if specified.
    /// - Throws: if the input cannot be parsed, e.g. because it is in an invalid format.
    static func parse(_ input: Input) throws(ParseError) -> (Result, TimeZone?) {
        let parser = Self(input: input, position: input.startIndex)
        return try parser.run()
    }
    
    
    /// Implements parsing of the `DATE` and `TIME` rules defined in the grammar.
    consuming private func run() throws(ParseError) -> (Result, TimeZone?) {
        try expectAndConsume("@")
        if current == "T" {
            consume()
            let time = try parseTimeFormat()
            return (.time(time), nil)
        } else {
            let date = try parseDateFormat()
            if isAtEnd {
                // A Date, without any time information.
                return (.date(date), nil)
            } else if current == "T" {
                // Not just a Date, but a DateTime...
                consume()
                var dateTime = DateTime(date: date, time: nil)
                if isAtEnd {
                    // ...which is partial, and does not have any time information.
                    return (.dateTime(dateTime), nil)
                } else {
                    // ...which has time information following the date...
                    dateTime.time = try parseTimeFormat()
                    if isAtEnd {
                        // ...but does not specify a time zone offset.
                        return (.dateTime(dateTime), nil)
                    } else {
                        // ...and also specifies a time zone.
                        let timeZone = try parseTimeZoneOffsetFormat()
                        return (.dateTime(dateTime), timeZone)
                    }
                }
            } else {
                // we're not at the end, but the next token after the DATEFORMAT is something other than a 'T'.
                // -> this is invalid
                throw .unexpectedToken(expected: ["T"], found: current)
            }
        }
    }
    
    
    /// Implements parsing of the `TIMEFORMAT` rule defined in the grammar.
    private mutating func parseTimeFormat() throws(ParseError) -> Time {
        // [0-9][0-9] (':'[0-9][0-9] (':'[0-9][0-9] ('.'[0-9]+)?)?)?
        let hour = try parseInt()
        guard current == ":" else {
            if let time = Time(hour: hour) {
                return time
            } else {
                throw .invalidInput(reason: "Invalid hour value '\(hour)'")
            }
        }
        try expectAndConsume(":")
        let minute = try parseInt()
        guard current == ":" else {
            if let time = Time(hour: hour, minute: minute) {
                return time
            } else {
                throw .invalidInput(reason: "Invalid time value '\(hour):\(minute)'")
            }
        }
        try expectAndConsume(":")
        let second = try parseInt()
        switch current {
        case ".":
            // The time value can optionally have a fractional suffix.
            // (In ISO8601, for the last-specified component; in FHIR for the seconds component).
            // We currently do not support this.
            throw .unsupportedLiteral
        default:
            if let time = Time(hour: hour, minute: minute, second: second) {
                return time
            } else {
                throw .invalidInput(reason: "Invalid time value '\(hour):\(minute):\(second)'")
            }
        }
    }
    
    
    /// Implements parsing of the `DATEFORMAT` rule defined in the grammar.
    private mutating func parseDateFormat() throws(ParseError) -> Date {
        // [0-9][0-9][0-9][0-9] ('-'[0-9][0-9] ('-'[0-9][0-9])?)?
        let year = try parseInt()
        guard (1...9999).contains(year) else {
            throw .invalidInput(reason: "Invalid year value '\(year)'")
        }
        guard current == "-" else {
            return .init(year: year)
        }
        try expectAndConsume("-")
        let month = try parseInt()
        guard (1...12).contains(month) else {
            throw .invalidInput(reason: "Invalid month value '\(month)'")
        }
        guard current == "-" else {
            return .init(year: year, month: month)
        }
        try expectAndConsume("-")
        let day = try parseInt()
        var components = DateComponents(year: year, month: month, day: day)
        components.timeZone = FHIRPathCalendar.utc
        guard FHIRPathCalendar.gregorian().date(from: components) != nil else {
            throw .invalidInput(reason: "Invalid date value '\(year)-\(month)-\(day)'")
        }
        return .init(year: year, month: month, day: day)
    }
    
    
    /// Implements parsing of the `TIMEZONEOFFSETFORMAT` rule defined in the grammar.
    /// - Throws: if the input tokens are invalid.
    /// - Returns: a `TimeZone` matching the specified offset.
    ///     May return `nil` if the input string specified a valid (w.r.t. the grammar) offset, which however cannot be represented by the `TimeZone` type.
    private mutating func parseTimeZoneOffsetFormat() throws(ParseError) -> TimeZone? {
        // ('Z' | ('+' | '-') [0-9][0-9]':'[0-9][0-9])
        if current == "Z" {
            // if the time zone is 'Z', it is interpreted UTC.
            consume()
            return FHIRPathCalendar.utc
        } else {
            let `operator` = try expectAnyOfAndConsume(["+", "-"])
            let hours = try parseInt()
            try expectAndConsume(":")
            let minutes = try parseInt()
            var offsetInSeconds = 0
            offsetInSeconds += hours * 60 * 60
            offsetInSeconds += minutes * 60
            offsetInSeconds *= `operator` == "-" ? -1 : 1
            guard hours <= 14, minutes < 60,
                  !(hours == 14 && minutes != 0),
                  let timeZone = TimeZone(secondsFromGMT: offsetInSeconds) else {
                throw .invalidInput(reason: "Invalid time-zone offset")
            }
            return timeZone
        }
    }
}


// MARK: Utilities

extension Collection {
    subscript(safe idx: Index) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}


extension Calendar {
    func dateBySetting(timeZone: TimeZone, of date: Date) -> Date? {
        var components = dateComponents(in: self.timeZone, from: date)
        components.timeZone = timeZone
        return self.date(from: components)
    }
    
    func convert(
        components: DateComponents,
        bySettingTimeZoneTo newTimeZone: TimeZone,
        componentsToReturn: Set<Component>
    ) -> DateComponents? {
        guard let date = date(from: components),
              let adjDate = dateBySetting(timeZone: newTimeZone, of: date) else {
            return nil
        }
        return dateComponents(componentsToReturn, from: adjDate)
    }
}
