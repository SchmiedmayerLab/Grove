//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreFoundation
import Foundation


extension PairRules {
    static func expressionString(from extensionObject: FHIRJSONObject) -> String? {
        guard let expression = extensionObject["valueExpression"] as? FHIRJSONObject else {
            return nil
        }
        return expression["expression"] as? String
    }

    static func answerValue(_ answer: FHIRJSONObject) -> (key: String, value: Any)? {
        let values = answer.filter { key, _ in
            key.hasPrefix("value") && answerTypes.values.contains { $0.contains(key) }
        }
        guard values.count == 1, let value = values.first else {
            return nil
        }
        return value
    }

    static func questionnaireAnswerValues(_ response: FHIRJSONObject) -> [String: [Any]] {
        var values: [String: [Any]] = [:]
        collectResponseValues(
            response["item"] as? [FHIRJSONObject] ?? [],
            into: &values
        )
        return values
    }

    static func collectResponseValues(
        _ items: [FHIRJSONObject],
        into values: inout [String: [Any]]
    ) {
        for item in items {
            let linkID = item["linkId"] as? String ?? ""
            if values[linkID] == nil {
                values[linkID] = []
            }
            for answer in item["answer"] as? [FHIRJSONObject] ?? [] {
                if let value = answerValue(answer)?.value {
                    values[linkID, default: []].append(value)
                }
                collectResponseValues(
                    answer["item"] as? [FHIRJSONObject] ?? [],
                    into: &values
                )
            }
            collectResponseValues(item["item"] as? [FHIRJSONObject] ?? [], into: &values)
        }
    }

    static func selectedInlineOption(
        _ item: FHIRJSONObject,
        value: Any
    ) -> FHIRJSONObject? {
        (item["answerOption"] as? [FHIRJSONObject] ?? []).first { option in
            guard let candidate = extensionValue(option)?.value else {
                return false
            }
            return valuesEqual(value, candidate)
        }
    }

    static func valuesEqual(_ left: Any, _ right: Any) -> Bool {
        if let leftQuantity = comparableQuantity(left),
           let rightQuantity = comparableQuantity(right) {
            return leftQuantity == rightQuantity
        }
        if let leftCoding = codingKey(left),
           let rightCoding = codingKey(right) {
            return leftCoding == rightCoding
        }
        if let leftDecimal = decimal(left), let rightDecimal = decimal(right) {
            return leftDecimal == rightDecimal
        }
        if let left = left as? String, let right = right as? String {
            return left == right
        }
        if let left = boolean(left), let right = boolean(right) {
            return left == right
        }
        guard JSONSerialization.isValidJSONObject(["value": left]),
              JSONSerialization.isValidJSONObject(["value": right]) else {
            return false
        }
        do {
            let leftData = try JSONSerialization.data(withJSONObject: ["value": left], options: [.sortedKeys])
            let rightData = try JSONSerialization.data(withJSONObject: ["value": right], options: [.sortedKeys])
            return leftData == rightData
        } catch {
            return false
        }
    }

    // Tri-state: nil means the answer families or quantity units are incomparable.
    // swiftlint:disable:next discouraged_optional_boolean
    static func lessThanOrEqual(_ left: Any, _ right: Any) -> Bool? {
        if let left = decimal(left), let right = decimal(right) {
            return left <= right
        }
        if let left = left as? String, let right = right as? String {
            return left <= right
        }
        if let left = comparableQuantity(left), let right = comparableQuantity(right) {
            guard left.system == right.system, left.code == right.code else {
                return nil
            }
            return left.value <= right.value
        }
        return nil
    }

    static func compare(_ left: Any, _ right: Any) -> ComparisonResult? {
        if let left = decimal(left), let right = decimal(right) {
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
            return .orderedSame
        }
        if let left = left as? String, let right = right as? String {
            return left.compare(right)
        }
        return nil
    }

    // Tri-state: nil means the JSON value is not a FHIR boolean.
    // swiftlint:disable:next discouraged_optional_boolean
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return value as? Bool
        }
        return number.boolValue
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return value as? Int
        }
        let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        let integer = number.intValue
        guard decimal == Decimal(integer) else {
            return nil
        }
        return integer
    }

    static func decimal(_ value: Any?) -> Decimal? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
                return nil
            }
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let string = value as? String {
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    static func decimalPlaces(_ value: Any) -> Int? {
        guard let decimal = decimal(value) else {
            return nil
        }
        let string = NSDecimalNumber(decimal: decimal).stringValue
        guard let separator = string.firstIndex(of: ".") else {
            return 0
        }
        return string.distance(from: string.index(after: separator), to: string.endIndex)
    }

    static func codingKey(_ value: Any) -> CodingIdentity? {
        guard let coding = value as? FHIRJSONObject,
              let code = coding["code"] as? String,
              !code.isEmpty else {
            return nil
        }
        return CodingIdentity(system: coding["system"] as? String, code: code)
    }

    static func comparableQuantity(_ value: Any) -> QuantityIdentity? {
        guard let quantity = value as? FHIRJSONObject,
              let value = decimal(quantity["value"]),
              let system = quantity["system"] as? String,
              let code = quantity["code"] as? String else {
            return nil
        }
        return QuantityIdentity(value: value, system: system, code: code)
    }
}
