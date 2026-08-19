//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A value produced by evaluating a FHIRPath expression.
///
/// FHIRPath evaluation always yields a *collection* of values (`[FHIRPathValue]`);
/// an empty collection represents the FHIRPath `{}` ("empty").
public enum FHIRPathValue: Hashable, Sendable {
    case boolean(Bool)
    case integer(Int)
    case decimal(Decimal)
    case string(String)
    /// A date with year and optional month/day precision.
    case date(DateComponents)
    /// A date-and-time; `timeZone` is carried in the components when present.
    case dateTime(DateComponents)
    /// A time of day.
    case time(DateComponents)
    case quantity(value: Decimal, unit: String)
    /// A complex (object) value, kept as its JSON-shaped node.
    case object(FHIRPathNode)

    // MARK: Accessors

    var decimalValue: Decimal? {
        switch self {
        case .integer(let value):
            Decimal(value)
        case .decimal(let value):
            value
        case .quantity(let value, _):
            value
        case .boolean, .string, .date, .dateTime, .time, .object:
            nil
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// The FHIRPath system type the value belongs to; `nil` for a complex (object) value.
    var systemTypeName: String? {
        switch self {
        case .boolean:
            "Boolean"
        case .integer:
            "Integer"
        case .decimal:
            "Decimal"
        case .string:
            "String"
        case .date:
            "Date"
        case .dateTime:
            "DateTime"
        case .time:
            "Time"
        case .quantity:
            "Quantity"
        case .object:
            nil
        }
    }

    /// The value reinterpreted as a date/dateTime/time, parsing FHIR-formatted strings.
    var temporalValue: FHIRPathValue? {
        switch self {
        case .date, .dateTime, .time:
            return self
        case .string(let string):
            return Self.parseTemporal(string)
        case .boolean, .integer, .decimal, .quantity, .object:
            return nil
        }
    }

    /// The value reinterpreted as a quantity: quantity values pass through, and
    /// Quantity-shaped object nodes (`value` + `code`/`unit`) are unwrapped.
    var quantityValue: (value: Decimal, unit: String)? {
        switch self {
        case let .quantity(value, unit):
            return (value, unit)
        case .object(let node):
            guard case .number(let value) = node.children(named: "value").first else {
                return nil
            }
            let unit = node.stringMember("code") ?? node.stringMember("unit") ?? "1"
            return (value, unit)
        case .boolean, .integer, .decimal, .string, .date, .dateTime, .time:
            return nil
        }
    }

    // MARK: Conversion

    /// Promotes a node to a value: leaves become primitive values, objects stay nodes.
    init(node: FHIRPathNode) {
        switch node {
        case .bool(let value):
            self = .boolean(value)
        case .number(let value):
            if value.exponent >= 0, let integer = Int(exactly: NSDecimalNumber(decimal: value)) {
                self = .integer(integer)
            } else {
                self = .decimal(value)
            }
        case .string(let value):
            self = .string(value)
        case .object, .array, .null:
            self = .object(node)
        }
    }

    /// Parses a FHIR-formatted date, dateTime, or time string.
    public static func parseTemporal(_ string: String) -> FHIRPathValue? {
        let literal = string.hasPrefix("@") ? string : "@\(string)"
        // A bare time of day ("13:30") only parses with the @T prefix.
        guard let (result, timeZone) = (try? DateTimeLiteralParser.parse(literal)) ?? (try? DateTimeLiteralParser.parse("@T\(string)")) else {
            return nil
        }
        switch result {
        case .date(let date):
            var components = date.components
            components.timeZone = timeZone
            return .date(components)
        case .time(let time):
            var components = time.components
            components.timeZone = timeZone
            return .time(components)
        case .dateTime(let dateTime):
            var components = dateTime.components
            components.timeZone = timeZone
            return .dateTime(components)
        }
    }
}


// MARK: Comparison Semantics

extension FHIRPathValue {
    /// Component-wise temporal comparison to the values' shared precision;
    /// `nil` when they agree up to the lower precision but differ in precision.
    ///
    /// Two offset-carrying `dateTime`s are compared as absolute instants instead; the component
    /// path stays for `date`, `time`, and offset-less values, whose partial precision has no instant.
    private static func temporalCompare(_ lhs: FHIRPathValue, _ rhs: FHIRPathValue) -> ComparisonResult? {
        if case .dateTime(let lhsComponents) = lhs, case .dateTime(let rhsComponents) = rhs,
           let lhsInstant = instant(from: lhsComponents), let rhsInstant = instant(from: rhsComponents) {
            return lhsInstant.compare(rhsInstant)
        }
        let lhsFields = temporalFields(of: lhs)
        let rhsFields = temporalFields(of: rhs)
        guard !lhsFields.isEmpty, lhsFields.count == rhsFields.count else {
            return nil
        }
        for (lhsField, rhsField) in zip(lhsFields, rhsFields) {
            switch (lhsField, rhsField) {
            case (nil, nil):
                return .orderedSame
            case (nil, .some), (.some, nil):
                // Shared components agree, but precision differs: empty per FHIRPath.
                return nil
            case let (.some(lhsValue), .some(rhsValue)):
                if lhsValue != rhsValue {
                    return lhsValue < rhsValue ? .orderedAscending : .orderedDescending
                }
            }
        }
        return .orderedSame
    }

    /// The value's temporal components, most significant first, or empty for a non-temporal value.
    private static func temporalFields(of value: FHIRPathValue) -> [Int?] {
        switch value {
        case .date(let components), .dateTime(let components):
            [components.year, components.month, components.day, components.hour, components.minute, components.second]
        case .time(let components):
            [components.hour, components.minute, components.second]
        case .boolean, .integer, .decimal, .string, .quantity, .object:
            []
        }
    }

    /// The absolute instant the components denote, or `nil` if they carry no time zone offset.
    private static func instant(from components: DateComponents) -> Date? {
        guard components.timeZone != nil else {
            return nil
        }
        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// FHIRPath equality (`=`); `.empty` where the spec makes the comparison empty
    /// (e.g. dates of differing precision that agree on their shared components).
    func fhirEquals(_ other: FHIRPathValue) -> FHIRPathBoolean {
        switch (self, other) {
        case let (.boolean(lhs), .boolean(rhs)):
            return FHIRPathBoolean(lhs == rhs)
        case let (.string(lhs), .string(rhs)):
            return FHIRPathBoolean(lhs == rhs)
        case let (.object(lhs), .object(rhs)):
            return FHIRPathBoolean(lhs == rhs)
        case (.date, _), (.dateTime, _), (.time, _), (_, .date), (_, .dateTime), (_, .time):
            return temporalEquals(other)
        case (.quantity, _), (_, .quantity):
            return quantityEquals(other)
        default:
            if let lhs = decimalValue, let rhs = other.decimalValue {
                return FHIRPathBoolean(lhs == rhs)
            }
            return .false
        }
    }

    /// `.empty` when both values are temporal and agree up to the lower precision but differ in precision.
    private func temporalEquals(_ other: FHIRPathValue) -> FHIRPathBoolean {
        guard let lhs = temporalValue, let rhs = other.temporalValue else {
            return .false
        }
        guard let comparison = Self.temporalCompare(lhs, rhs) else {
            return .empty
        }
        return FHIRPathBoolean(comparison == .orderedSame)
    }

    /// `.empty` for quantities in differing units, which this evaluator does not convert.
    private func quantityEquals(_ other: FHIRPathValue) -> FHIRPathBoolean {
        guard let lhs = quantityValue, let rhs = other.quantityValue else {
            return .false
        }
        guard lhs.unit == rhs.unit else {
            return .empty
        }
        return FHIRPathBoolean(lhs.value == rhs.value)
    }

    /// FHIRPath ordering comparison; `nil` means empty (incomparable precision or units).
    func fhirCompare(_ other: FHIRPathValue) throws -> ComparisonResult? {
        if let lhs = decimalValue, let rhs = other.decimalValue, quantityValue == nil, other.quantityValue == nil {
            return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
        }
        if case .string(let lhs) = self, case .string(let rhs) = other {
            return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
        }
        if let lhs = quantityValue, let rhs = other.quantityValue {
            guard lhs.unit == rhs.unit else {
                return nil
            }
            return lhs.value == rhs.value ? .orderedSame : (lhs.value < rhs.value ? .orderedAscending : .orderedDescending)
        }
        if let lhs = temporalValue, let rhs = other.temporalValue {
            return Self.temporalCompare(lhs, rhs)
        }
        throw FHIRPathEvaluationError.typeMismatch("Cannot compare \(self) with \(other)")
    }
}


extension [FHIRPathValue] {
    /// The collection's single value; `nil` when empty, throwing on multiple items.
    var singleton: FHIRPathValue? {
        get throws {
            switch count {
            case 0:
                return nil
            case 1:
                return self[0]
            default:
                throw FHIRPathEvaluationError.typeMismatch("Expected a single value, got \(count)")
            }
        }
    }
}
