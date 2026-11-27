//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A FHIR `date`, `dateTime` or `time` value with the precision its text states.
@available(iOS 18, macOS 15, watchOS 11, *)
struct PairTemporal: Equatable {
    /// Year, month and day, as far as the value states them. Empty for a time.
    let date: [Int]
    /// Seconds since 1970-01-01T00:00:00Z for a date-time with a time, or seconds since midnight for a time.
    let seconds: Int?
    /// Digits after the decimal point, without trailing zeros.
    let fraction: String

    /// `YYYY`, `YYYY-MM` or `YYYY-MM-DD`.
    static func date(_ text: String) -> Self? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count),
              parts[0].count == 4,
              parts.dropFirst().allSatisfy({ $0.count == 2 }),
              let values = digits(parts),
              isValidDate(values) else {
            return nil
        }
        return Self(date: values, seconds: nil, fraction: "")
    }

    /// A partial date, or a full date with a time of day and a time zone.
    static func dateTime(_ text: String) -> Self? {
        guard let separator = text.firstIndex(of: "T") else {
            return date(text)
        }
        guard let day = date(String(text[..<separator])), day.date.count == 3 else {
            return nil
        }
        let rest = text[text.index(after: separator)...]
        guard let zoneStart = rest.firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }),
              let clock = time(String(rest[..<zoneStart])),
              let clockSeconds = clock.seconds,
              let offset = offset(String(rest[zoneStart...])) else {
            return nil
        }
        let days = daysSinceEpoch(year: day.date[0], month: day.date[1], day: day.date[2])
        return Self(date: day.date, seconds: days * 86_400 + clockSeconds - offset, fraction: clock.fraction)
    }

    /// `hh:mm:ss` with optional fractional seconds.
    static func time(_ text: String) -> Self? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0].count == 2, parts[1].count == 2,
              let clock = digits([parts[0], parts[1]]), clock[0] < 24, clock[1] < 60,
              let seconds = fractionalSeconds(parts[2]) else {
            return nil
        }
        return Self(date: [], seconds: clock[0] * 3_600 + clock[1] * 60 + seconds.whole, fraction: seconds.fraction)
    }

    private static func digits(_ parts: [String]) -> [Int]? { // swiftlint:disable:this discouraged_optional_collection
        let values = parts.compactMap { part in part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil }
        return values.count == parts.count ? values : nil
    }

    private static func fractionalSeconds(_ text: String) -> (whole: Int, fraction: String)? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), parts[0].count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let whole = Int(parts[0]), whole <= 60 else {
            return nil
        }
        let fraction = parts.dropFirst().first ?? ""
        let end = fraction.lastIndex { $0 != "0" }.map { fraction.index(after: $0) } ?? fraction.startIndex
        return (whole, String(fraction[..<end]))
    }

    private static func offset(_ text: String) -> Int? {
        if text == "Z" {
            return 0
        }
        let sign = text.first == "-" ? -1 : 1
        let parts = text.dropFirst().split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard text.first == "+" || text.first == "-", parts.count == 2, parts.allSatisfy({ $0.count == 2 }),
              let values = digits(parts), values[1] < 60, values[0] * 60 + values[1] <= 14 * 60 else {
            return nil
        }
        return sign * (values[0] * 3_600 + values[1] * 60)
    }

    private static func isValidDate(_ values: [Int]) -> Bool {
        guard values[0] >= 1 else {
            return false
        }
        guard values.count > 1 else {
            return true
        }
        guard (1...12).contains(values[1]) else {
            return false
        }
        guard values.count > 2 else {
            return true
        }
        let leap = values[0].isMultiple(of: 4) && (!values[0].isMultiple(of: 100) || values[0].isMultiple(of: 400))
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...lengths[values[1] - 1]).contains(values[2])
    }

    /// Days from 1970-01-01 in the proleptic Gregorian calendar.
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The order of two values; values that agree down to the coarser precision of the two have no order.
    func compare(to other: Self) -> ComparisonResult? {
        if let seconds, let otherSeconds = other.seconds {
            return seconds == otherSeconds ? PairCondition.order(fraction, other.fraction) : PairCondition.order(seconds, otherSeconds)
        }
        for (left, right) in zip(date, other.date) where left != right {
            return PairCondition.order(left, right)
        }
        return date.count == other.date.count && seconds == nil && other.seconds == nil ? .orderedSame : nil
    }
}


/// An answer or enableWhen value, read by its FHIR type, as enableWhen compares it.
@available(iOS 18, macOS 15, watchOS 11, *)
enum PairCondition {
    case boolean(Bool)
    case number(Decimal)
    case string(String)
    case uri(String)
    case coding(system: String?, code: String?)
    case quantity(Quantity)
    case temporal(PairTemporal, isTime: Bool)
    case reference(String?)
    /// A value enableWhen does not compare, such as an attachment.
    case other

    /// The order of an answer relative to an enableWhen value.
    enum Ordering {
        case ordered(ComparisonResult)
        /// The values could have an order, but their precision, unit or comparator leaves it open.
        case unknown
        /// The values are of different kinds and have no order.
        case incomparable
    }

    struct Quantity {
        let value: Decimal?
        let comparator: String?
        let system: String?
        let code: String?
        let unit: String?

        /// The order of the quantity relative to a threshold. Units are not converted: a quantity in another
        /// unit, or a bounded quantity, has no known order.
        func order(comparedTo threshold: Self) -> Ordering {
            let sameUnit: Bool
            if let thresholdCode = threshold.code {
                sameUnit = code == thresholdCode && (threshold.system == nil || system == threshold.system)
            } else if let thresholdUnit = threshold.unit {
                sameUnit = unit == thresholdUnit
            } else {
                // A threshold without a unit orders only quantities without a unit.
                sameUnit = code == nil && unit == nil
            }
            guard sameUnit, comparator == nil, let value, let thresholdValue = threshold.value else {
                return .unknown
            }
            return .ordered(PairCondition.order(value, thresholdValue))
        }
    }

    /// Reads a `value[x]` or `answer[x]` element by the type its key names.
    init?(key: String, value: Any) { // swiftlint:disable:this cyclomatic_complexity
        let type = key.hasPrefix("value") ? key.dropFirst("value".count) : key.dropFirst("answer".count)
        switch type {
        case "Boolean":
            guard let value = PairRules.boolean(value) else {
                return nil
            }
            self = .boolean(value)
        case "Decimal", "Integer":
            guard let value = PairRules.decimal(value) else {
                return nil
            }
            self = .number(value)
        case "String", "Uri":
            guard let value = value as? String else {
                return nil
            }
            self = type == "Uri" ? .uri(value) : .string(value)
        case "Date", "DateTime", "Time":
            guard let text = value as? String,
                  let temporal = type == "Time" ? PairTemporal.time(text) : PairTemporal.dateTime(text) else {
                return nil
            }
            self = .temporal(temporal, isTime: type == "Time")
        case "Coding":
            guard let coding = value as? FHIRJSONObject else {
                return nil
            }
            self = .coding(system: coding["system"] as? String, code: coding["code"] as? String)
        case "Quantity":
            guard let quantity = value as? FHIRJSONObject else {
                return nil
            }
            self = .quantity(Quantity(
                value: PairRules.decimal(quantity["value"]),
                comparator: quantity["comparator"] as? String,
                system: quantity["system"] as? String,
                code: quantity["code"] as? String,
                unit: quantity["unit"] as? String
            ))
        case "Reference":
            self = .reference((value as? FHIRJSONObject)?["reference"] as? String)
        default:
            self = .other
        }
    }

    static func order<Value: Comparable>(_ left: Value, _ right: Value) -> ComparisonResult {
        left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
    }

    /// The outcome of one enableWhen operator over the answers; `nil` when it is unknown.
    ///
    /// `!=` holds when no answer equals the value, so also without an answer; every other operator holds when
    /// at least one answer satisfies it.
    static func test(_ operation: String, expected: Self, answers: [Self]) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        switch operation {
        case "exists":
            guard case .boolean(let value) = expected else {
                return nil
            }
            return answers.isEmpty != value
        case "=":
            return any(answers.map { $0.equals(expected) })
        case "!=":
            return any(answers.map { $0.equals(expected) }).map { !$0 }
        case ">", "<", ">=", "<=":
            // Only numbers, dates and times, and quantities have an order.
            switch expected {
            case .number, .temporal, .quantity:
                return any(answers.map { $0.satisfies(operation, expected) })
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// True if any outcome is true, unknown if none is true and any is unknown, and false otherwise.
    static func any(_ outcomes: [Bool?]) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        outcomes.contains(true) ? true : outcomes.contains(nil) ? nil : false
    }

    /// False if any outcome is false, unknown if none is false and any is unknown, and true otherwise.
    static func all(_ outcomes: [Bool?]) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        outcomes.contains(false) ? false : outcomes.contains(nil) ? nil : true
    }

    /// Whether the answer equals the enableWhen value; `nil` when equality is unknown. Values of different kinds
    /// are not equal, and a coding equals another only when system and code are both equal.
    func equals(_ expected: Self) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        switch (self, expected) {
        case let (.boolean(answer), .boolean(value)):
            return answer == value
        case let (.string(answer), .string(value)), let (.uri(answer), .uri(value)):
            // Strings are equal when their characters are, without Unicode normalization.
            return answer.utf8.elementsEqual(value.utf8)
        case let (.coding(system, code), .coding(expectedSystem, expectedCode)):
            guard let code, let expectedCode else {
                return false
            }
            return code == expectedCode && system == expectedSystem
        case let (.reference(answer), .reference(value)):
            return answer != nil && answer == value
        default:
            switch order(comparedTo: expected) {
            case .ordered(let result): return result == .orderedSame
            case .unknown: return nil
            case .incomparable: return false
            }
        }
    }

    func order(comparedTo expected: Self) -> Ordering {
        switch (self, expected) {
        case let (.number(answer), .number(value)):
            .ordered(Self.order(answer, value))
        case let (.temporal(answer, answerIsTime), .temporal(value, valueIsTime)) where answerIsTime == valueIsTime:
            answer.compare(to: value).map(Ordering.ordered) ?? .unknown
        case let (.quantity(answer), .quantity(threshold)):
            answer.order(comparedTo: threshold)
        default:
            .incomparable
        }
    }

    /// Whether the answer satisfies an ordered operator; `nil` when its order is unknown.
    private func satisfies(_ operation: String, _ expected: Self) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        switch order(comparedTo: expected) {
        case .ordered(let result):
            switch operation {
            case ">": result == .orderedDescending
            case "<": result == .orderedAscending
            case ">=": result != .orderedAscending
            default: result != .orderedDescending
            }
        case .unknown: nil
        case .incomparable: false
        }
    }
}
