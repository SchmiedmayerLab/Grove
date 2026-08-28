//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension FHIRPathEvaluator {
    /// FHIRPath singleton boolean conversion: empty → `.empty`, boolean singleton → its
    /// value, any other singleton → `.true`; multi-item collections are an error.
    static func singletonBoolean(of collection: [FHIRPathValue]) throws -> FHIRPathBoolean {
        switch collection.count {
        case 0:
            return .empty
        case 1:
            if case .boolean(let value) = collection[0] {
                return FHIRPathBoolean(value)
            }
            return .true
        default:
            throw FHIRPathEvaluationError.typeMismatch("Expected a singleton in boolean context, got \(collection.count) items")
        }
    }

    static func matchesType(_ value: FHIRPathValue, name: String) throws -> Bool {
        let bare = name.hasPrefix("System.") ? String(name.dropFirst("System.".count)) : name
        // FHIR spells its primitive types lowercase, FHIRPath's system types capitalized.
        switch bare {
        case "Boolean", "boolean":
            return value.systemTypeName == "Boolean"
        case "Integer", "integer":
            return value.systemTypeName == "Integer"
        case "Decimal", "decimal":
            return value.systemTypeName == "Decimal"
        case "String", "string":
            return value.systemTypeName == "String"
        case "Date", "date":
            return value.systemTypeName == "Date"
        case "DateTime", "dateTime":
            return value.systemTypeName == "DateTime"
        case "Time", "time":
            return value.systemTypeName == "Time"
        case "Quantity":
            return value.quantityValue != nil
        default:
            throw FHIRPathEvaluationError.unsupported("type '\(name)' in is/as/ofType")
        }
    }

    static func stringify(_ value: FHIRPathValue) -> String {
        switch value {
        case .boolean(let bool):
            return bool ? "true" : "false"
        case .integer(let integer):
            return String(integer)
        case .decimal(let decimal):
            return "\(decimal)"
        case .string(let string):
            return string
        case let .quantity(quantity, unit):
            return "\(quantity) '\(unit)'"
        case .date(let components):
            return Self.dateString(components)
        case .time(let components):
            return Self.timeString(components)
        case .dateTime(let components):
            return Self.dateTimeString(components)
        case .object:
            return "[object]"
        }
    }

    static func addCalendarQuantity(to temporal: FHIRPathValue, amount: Decimal, unit: String) throws -> FHIRPathValue {
        guard let count = Int(exactly: NSDecimalNumber(decimal: amount)) else {
            throw FHIRPathEvaluationError.typeMismatch("Calendar arithmetic requires a whole number of units")
        }
        let delta = try Self.calendarDelta(count: count, unit: unit)
        let components: DateComponents
        switch temporal {
        case .date(let value), .dateTime(let value), .time(let value):
            components = value
        case .boolean, .integer, .decimal, .string, .quantity, .object:
            throw FHIRPathEvaluationError.typeMismatch("Calendar arithmetic on a non-temporal value")
        }
        let calendar = FHIRPathCalendar.gregorian(
            timeZone: components.timeZone ?? FHIRPathCalendar.utc
        )
        guard let result = calendar.components(byAdding: delta, to: components) else {
            throw FHIRPathEvaluationError.typeMismatch("Date arithmetic failed")
        }
        return Self.narrowed(result, like: temporal, timeZone: components.timeZone)
    }

    private static func calendarDelta(count: Int, unit: String) throws -> DateComponents {
        var delta = DateComponents()
        switch unit {
        case "year", "years", "a":
            delta.year = count
        case "month", "months", "mo":
            delta.month = count
        case "week", "weeks", "wk":
            delta.day = count * 7
        case "day", "days", "d":
            delta.day = count
        case "hour", "hours", "h":
            delta.hour = count
        case "minute", "minutes", "min":
            delta.minute = count
        case "second", "seconds", "s":
            delta.second = count
        default:
            throw FHIRPathEvaluationError.typeMismatch("Unsupported calendar unit '\(unit)'")
        }
        return delta
    }

    /// Calendar math returns fully-populated components (weekday, quarter, ...);
    /// strip back to the temporal fields so values stay comparable and equatable.
    private static func narrowed(_ components: DateComponents, like temporal: FHIRPathValue, timeZone: TimeZone?) -> FHIRPathValue {
        switch temporal {
        case .date:
            var narrowed = DateComponents(year: components.year, month: components.month, day: components.day)
            narrowed.timeZone = timeZone
            return .date(narrowed)
        case .time:
            return .time(DateComponents(hour: components.hour, minute: components.minute, second: components.second))
        default:
            var narrowed = DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: components.hour,
                minute: components.minute,
                second: components.second
            )
            narrowed.timeZone = timeZone
            return .dateTime(narrowed)
        }
    }

    private static func dateString(_ components: DateComponents) -> String {
        var result = Self.pad(components.year, width: 4)
        if let month = components.month {
            result += "-\(Self.pad(month))"
            if let day = components.day {
                result += "-\(Self.pad(day))"
            }
        }
        return result
    }

    private static func timeString(_ components: DateComponents) -> String {
        "\(Self.pad(components.hour)):\(Self.pad(components.minute)):\(Self.pad(components.second))"
    }

    private static func dateTimeString(_ components: DateComponents) -> String {
        var result = Self.dateString(components)
        if components.hour != nil {
            result += "T\(Self.timeString(components))"
        }
        return result
    }

    private static func pad(_ number: Int?, width: Int = 2) -> String {
        String(format: "%0\(width)d", number ?? 0)
    }
}
