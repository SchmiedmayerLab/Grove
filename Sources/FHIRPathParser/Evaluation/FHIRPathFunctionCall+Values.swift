//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension FHIRPathFunctionCall {
    // MARK: Conversion

    func evaluateConversion() throws -> [FHIRPathValue] {
        switch name {
        case "toInteger":
            return try convertToInteger()
        case "toDecimal":
            return try convertToDecimal()
        case "toBoolean":
            return try convertToBoolean()
        case "toString":
            guard let value = try input.singleton else {
                return []
            }
            return [.string(FHIRPathEvaluator.stringify(value))]
        default:
            return try evaluateUtility()
        }
    }

    private func convertToInteger() throws -> [FHIRPathValue] {
        switch try input.singleton {
        case .integer(let value):
            return [.integer(value)]
        case .string(let string):
            return Int(string).map { [.integer($0)] } ?? []
        case .boolean(let value):
            return [.integer(value ? 1 : 0)]
        case .decimal(let value):
            return Int(exactly: NSDecimalNumber(decimal: value)).map { [.integer($0)] } ?? []
        default:
            return []
        }
    }

    private func convertToDecimal() throws -> [FHIRPathValue] {
        switch try input.singleton {
        case .integer(let value):
            return [.decimal(Decimal(value))]
        case .decimal(let value):
            return [.decimal(value)]
        case .string(let string):
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")).map { [.decimal($0)] } ?? []
        case .boolean(let value):
            return [.decimal(value ? 1 : 0)]
        default:
            return []
        }
    }

    private func convertToBoolean() throws -> [FHIRPathValue] {
        switch try input.singleton {
        case .boolean(let value):
            return [.boolean(value)]
        case .string(let string):
            switch string.lowercased() {
            case "true", "t", "yes", "1":
                return [.boolean(true)]
            case "false", "f", "no", "0":
                return [.boolean(false)]
            default:
                return []
            }
        case .integer(1):
            return [.boolean(true)]
        case .integer(0):
            return [.boolean(false)]
        default:
            return []
        }
    }

    // MARK: Utility

    private func evaluateUtility() throws -> [FHIRPathValue] {
        switch name {
        case "iif":
            try requireParams(2...3)
            let condition = try FHIRPathEvaluator.singletonBoolean(of: param(0))
            if condition == .true {
                return try param(1)
            }
            return params.count == 3 ? try param(2) : []
        case "not":
            switch try FHIRPathEvaluator.singletonBoolean(of: input) {
            case .true:
                return [.boolean(false)]
            case .false:
                return [.boolean(true)]
            case .empty:
                return []
            }
        case "trace":
            return input
        default:
            return try evaluateString()
        }
    }

    // MARK: Strings

    private func evaluateString() throws -> [FHIRPathValue] {
        switch name {
        case "length":
            guard case .string(let value)? = try input.singleton else {
                return []
            }
            return [.integer(value.count)]
        case "upper":
            return try mapString { $0.uppercased() }
        case "lower":
            return try mapString { $0.lowercased() }
        case "trim":
            return try mapString { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "startsWith", "endsWith", "contains", "indexOf":
            return try evaluateStringSearch()
        default:
            return try evaluateStringEditing()
        }
    }

    private func mapString(_ transform: (String) -> String) throws -> [FHIRPathValue] {
        guard case .string(let value)? = try input.singleton else {
            return []
        }
        return [.string(transform(value))]
    }

    private func evaluateStringSearch() throws -> [FHIRPathValue] {
        try requireParams(1...1)
        guard case .string(let value)? = try input.singleton,
              case .string(let argument)? = try param(0).singleton else {
            return []
        }
        switch name {
        case "startsWith":
            return [.boolean(value.hasPrefix(argument))]
        case "endsWith":
            return [.boolean(value.hasSuffix(argument))]
        case "contains":
            return [.boolean(argument.isEmpty || value.contains(argument))]
        default:
            if let range = value.range(of: argument) {
                return [.integer(value.distance(from: value.startIndex, to: range.lowerBound))]
            }
            return [.integer(-1)]
        }
    }

    private func evaluateStringEditing() throws -> [FHIRPathValue] {
        switch name {
        case "substring":
            return try evaluateSubstring()
        case "replace":
            try requireParams(2...2)
            guard case .string(let value)? = try input.singleton,
                  case .string(let pattern)? = try param(0).singleton,
                  case .string(let substitution)? = try param(1).singleton else {
                return []
            }
            return [.string(value.replacingOccurrences(of: pattern, with: substitution))]
        case "matches":
            try requireParams(1...1)
            guard case .string(let value)? = try input.singleton,
                  case .string(let pattern)? = try param(0).singleton,
                  let regex = try? NSRegularExpression(pattern: pattern) else {
                return []
            }
            let range = NSRange(value.startIndex..., in: value)
            return [.boolean(regex.firstMatch(in: value, range: range) != nil)]
        case "join":
            return try evaluateJoin()
        default:
            return try evaluateMath()
        }
    }

    private func evaluateSubstring() throws -> [FHIRPathValue] {
        try requireParams(1...2)
        guard case .string(let value)? = try input.singleton,
              case .integer(let start)? = try param(0).singleton,
              start >= 0, start < value.count else {
            return []
        }
        let from = value.index(value.startIndex, offsetBy: start)
        if params.count == 2 {
            guard case .integer(let length)? = try param(1).singleton, length >= 0 else {
                return []
            }
            let to = value.index(from, offsetBy: length, limitedBy: value.endIndex) ?? value.endIndex
            return [.string(String(value[from..<to]))]
        }
        return [.string(String(value[from...]))]
    }

    private func evaluateJoin() throws -> [FHIRPathValue] {
        try requireParams(0...1)
        let separator: String
        if params.isEmpty {
            separator = ""
        } else if case .string(let value)? = try param(0).singleton {
            separator = value
        } else {
            separator = ""
        }
        let strings = input.compactMap(\.stringValue)
        return [.string(strings.joined(separator: separator))]
    }

    // MARK: Math & Aggregates

    private func evaluateMath() throws -> [FHIRPathValue] {
        switch name {
        case "abs":
            switch try input.singleton {
            case .integer(let value):
                return [.integer(Swift.abs(value))]
            case .decimal(let value):
                return [.decimal(Swift.abs(value))]
            case let .quantity(value, unit):
                return [.quantity(value: Swift.abs(value), unit: unit)]
            default:
                return []
            }
        case "round":
            return try evaluateRound()
        case "sum", "min", "max", "avg":
            return try evaluateAggregate()
        default:
            return try evaluateEnvironment()
        }
    }

    private func evaluateRound() throws -> [FHIRPathValue] {
        try requireParams(0...1)
        guard let value = try input.singleton?.decimalValue else {
            return []
        }
        var precision = 0
        if params.count == 1, case .integer(let digits)? = try param(0).singleton {
            precision = digits
        }
        var operand = value
        var result = Decimal()
        NSDecimalRound(&result, &operand, precision, .plain)
        return [.decimal(result)]
    }

    private func evaluateAggregate() throws -> [FHIRPathValue] {
        let decimals = try input.map { value throws -> Decimal in
            guard let decimal = value.decimalValue else {
                throw FHIRPathEvaluationError.typeMismatch("\(name)() over non-numeric value \(value)")
            }
            return decimal
        }
        guard !decimals.isEmpty else {
            // Deliberate divergence: FHIRPath defines sum() over an empty collection as empty,
            // but questionnaire scoring expects an unanswered questionnaire to total zero.
            return name == "sum" ? [.integer(0)] : []
        }
        let allIntegers = input.allSatisfy { if case .integer = $0 { true } else { false } }
        let result: Decimal
        switch name {
        case "sum":
            result = decimals.reduce(0, +)
        case "min":
            result = decimals.min() ?? 0
        case "max":
            result = decimals.max() ?? 0
        default:
            result = decimals.reduce(0, +) / Decimal(decimals.count)
        }
        if allIntegers && name != "avg", let integer = Int(exactly: NSDecimalNumber(decimal: result)) {
            return [.integer(integer)]
        }
        return [.decimal(result)]
    }

    // MARK: Date, Time & SDC

    private func evaluateEnvironment() throws -> [FHIRPathValue] {
        switch name {
        case "today":
            let calendar = FHIRPathCalendar.gregorian(timeZone: evaluator.context.evaluationTimeZone)
            var components = calendar.dateComponents([.year, .month, .day], from: evaluator.context.evaluationInstant)
            components.timeZone = nil
            return [.date(components)]
        case "now":
            let calendar = FHIRPathCalendar.gregorian(timeZone: evaluator.context.evaluationTimeZone)
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: evaluator.context.evaluationInstant
            )
            components.timeZone = evaluator.context.evaluationTimeZone
            return [.dateTime(components)]
        case "timeOfDay":
            let calendar = FHIRPathCalendar.gregorian(timeZone: evaluator.context.evaluationTimeZone)
            let components = calendar.dateComponents([.hour, .minute, .second], from: evaluator.context.evaluationInstant)
            return [.time(components)]
        case "weight":
            return weights()
        default:
            throw FHIRPathEvaluationError.unsupportedFunction(name)
        }
    }

    /// SDC: the scoring weight of a QR answer — read from the itemWeight
    /// (or retired ordinalValue) extension carried on the answer's coding.
    private func weights() -> [FHIRPathValue] {
        input.compactMap { value -> FHIRPathValue? in
            guard case .object(let node) = value else {
                return nil
            }
            // Accept an answer object (look through to its coding) or a coding directly.
            let coding = node.children(named: "valueCoding").first ?? node
            let urls = ["http://hl7.org/fhir/StructureDefinition/itemWeight", "http://hl7.org/fhir/StructureDefinition/ordinalValue"]
            for url in urls {
                if let ext = coding.children(named: "extension").first(where: { $0.stringMember("url") == url }),
                   case .number(let weight) = ext.children(named: "valueDecimal").first {
                    return .decimal(weight)
                }
            }
            return nil
        }
    }
}
