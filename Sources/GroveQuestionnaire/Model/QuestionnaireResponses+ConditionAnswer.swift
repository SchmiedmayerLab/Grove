//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// One answer of a question, in the form a ``Questionnaire/Condition/responseValueComparison(taskId:operator:value:)`` compares it.
@available(iOS 18, macOS 15, watchOS 11, *)
enum ConditionAnswer {
    case bool(Bool)
    case string(String)
    /// An integer or decimal answer, compared exactly.
    case number(Decimal)
    /// A quantity answer, compared exactly, in the unit its exported `Quantity` records.
    case quantity(Decimal, unit: RecordedQuantityUnit)
    /// The integer value of a choice option, which compares only with an integer.
    case integerOption(Int)
    case date(DateComponents, style: Questionnaire.Task.Kind.DateTimeConfig.Style)
    /// A selected choice option, together with the value it stands for.
    indirect case option(id: String, value: ConditionAnswer?)

    /// How the answer compares with an enableWhen value.
    enum Comparison {
        /// The values are ordered.
        case ordered(ComparisonResult)
        /// The values have no order, and are equal or not.
        case equal(Bool)
        /// The values could be ordered, but their precision or unit leaves the order open.
        case unknown
        /// The values are of different kinds: not equal, and without an order.
        case incomparable

        /// Whether the values are equal; `nil` if that is unknown.
        var isEqual: Bool? { // swiftlint:disable:this discouraged_optional_boolean
            switch self {
            case .ordered(let order): order == .orderedSame
            case .equal(let equal): equal
            case .unknown: nil
            case .incomparable: false
            }
        }
    }

    /// Whether `operator` can compare with `value`: the ordered operators need a value with an order.
    static func compares(_ operator: Questionnaire.Condition.ComparisonOperator, with value: Questionnaire.Condition.Value) -> Bool {
        switch (`operator`, value) {
        case (.equal, _), (.notEqual, _), (_, .integer), (_, .decimal), (_, .date), (_, .quantity):
            true
        default:
            false
        }
    }

    /// Whether a condition with `value` can be evaluated on the answers of `task`.
    ///
    /// These are the `answer[x]` types the pair rules compare with each item type; a custom kind compares its own.
    static func compares( // swiftlint:disable:this cyclomatic_complexity
        _ value: Questionnaire.Condition.Value,
        withAnswersOf task: Questionnaire.Task
    ) -> Bool {
        func isDate(_ components: DateComponents) -> Bool {
            components.year != nil && components.hour == nil
        }
        func isTime(_ components: DateComponents) -> Bool {
            components.year == nil && components.hour != nil
        }
        switch (task.kind.variant, value) {
        case (.boolean, .bool), (.freeText, .string), (.custom, _):
            return true
        case let (.numeric(config), value):
            switch value {
            case .integer, .decimal: return config.valueKind != .quantity
            case .quantity: return config.valueKind == .quantity
            default: return false
            }
        case let (.dateTime(config), .date(components)):
            switch config.style {
            case .dateOnly: return isDate(components)
            case .timeOnly: return isTime(components)
            case .dateAndTime: return components.year != nil
            }
        case (.choice, .SCMCOption), (.choice, .string), (.choice, .integer):
            return true
        case let (.choice, .date(components)):
            return isDate(components) || isTime(components)
        default:
            return false
        }
    }

    /// `value` as the exported condition records it for the answers of `task`: a quantity's unit code takes the
    /// system the question gives it, or counts as unit text without one.
    static func recorded(_ value: Questionnaire.Condition.Value, for task: Questionnaire.Task) -> Questionnaire.Condition.Value {
        guard case let .quantity(number, system, code, text) = value, case .numeric(let config) = task.kind.variant else {
            return value
        }
        let unit = config.recordedUnit(ofConditionWith: system, code: code, text: text)
        return .quantity(value: number, system: unit.system, code: unit.code, unit: unit.text)
    }

    /// The answers a response holds for the task.
    static func answers( // swiftlint:disable:this cyclomatic_complexity
        of response: QuestionnaireResponses.Response.Value,
        for task: Questionnaire.Task
    ) -> [Self] {
        switch task.kind.variant {
        case .boolean:
            return response.boolValue.map { [.bool($0)] } ?? []
        case .freeText:
            return response.stringValue.map { [.string($0)] } ?? []
        case .dateTime(let config):
            return response.dateValue.map { [.date($0, style: config.style)] } ?? []
        case .numeric(let config):
            guard let number = response.numberValue.flatMap({ Decimal(shortestDigitsOf: $0) }) else {
                return []
            }
            // A unit the participant chose (unitOption) takes precedence over the fixed unit.
            let unit = config.recordedUnit(ofAnswerIn: response.quantityValue?.unitCode)
            return [config.valueKind == .quantity ? .quantity(number, unit: unit) : .number(number)]
        case .choice(let config):
            let choice = response.choiceValue
            let selected: [Self] = config.options.filter { choice.selectedOptions.contains($0.id) }.map { option in
                let value: Self? = switch option.answerValue {
                case .string(let string): .string(string)
                case .integer(let integer): .integerOption(integer)
                case .date(let date): .date(date, style: .dateOnly)
                case .time(let time): .date(time, style: .timeOnly)
                case nil: nil
                }
                return .option(id: option.id, value: value)
            }
            // The open-choice free-text answer.
            return selected + (choice.freeTextOtherResponse.map { [.string($0)] } ?? [])
        case .instructional, .fileAttachment, .custom:
            return []
        }
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }

    private static func compare(
        _ answer: DateComponents,
        _ value: DateComponents,
        style: Questionnaire.Task.Kind.DateTimeConfig.Style
    ) -> ComparisonResult? {
        switch style {
        case .timeOnly:
            let answer = [answer.hour ?? 0, answer.minute ?? 0, answer.second ?? 0, answer.nanosecond ?? 0]
            let value = [value.hour ?? 0, value.minute ?? 0, value.second ?? 0, value.nanosecond ?? 0]
            return answer == value ? .orderedSame : answer.lexicographicallyPrecedes(value) ? .orderedAscending : .orderedDescending
        case .dateOnly:
            // Dates compare as far as both state them; when they agree that far and one is more precise,
            // the order is unknown, as in FHIR (`2024-03-05` neither equals nor follows `2024`).
            let answer = [answer.year, answer.month, answer.day].prefix { $0 != nil }.compactMap(\.self)
            let value = [value.year, value.month, value.day].prefix { $0 != nil }.compactMap(\.self)
            let common = min(answer.count, value.count)
            guard common > 0 else {
                return nil
            }
            if answer.prefix(common) == value.prefix(common) {
                return answer.count == value.count ? .orderedSame : nil
            }
            return answer.prefix(common).lexicographicallyPrecedes(value.prefix(common)) ? .orderedAscending : .orderedDescending
        case .dateAndTime where value.hour == nil:
            // A condition without a time compares with the answer's date; on the same day, the answer's time
            // leaves the order open.
            let order = compare(answer, value, style: .dateOnly)
            return order == .orderedSame && answer.hour != nil ? nil : order
        case .dateAndTime:
            // A component without a time zone is in the current one, as the exported answer is; a condition
            // imported from FHIR keeps the offset it was given in.
            let calendar = Calendar.current
            guard let answer = calendar.date(from: answer), let value = calendar.date(from: value) else {
                return nil
            }
            return compare(answer, value)
        }
    }

    /// How the answer compares with `expected`, by the rules of the pair validation.
    func comparison(with expected: Questionnaire.Condition.Value) -> Comparison {
        switch (self, expected) {
        case let (.bool(answer), .bool(value)):
            return .equal(answer == value)
        case let (.string(answer), .string(value)):
            // FHIR strings compare by their characters as written, without Unicode normalization.
            return .equal(answer.utf8.elementsEqual(value.utf8))
        case let (.option(id, _), .SCMCOption(conditionId)):
            // Option ids created from FHIR codings are `system|code` tokens, or the bare code for a
            // coding without a system, so a coding matches only when system and code are both equal.
            return .equal(id == conditionId)
        case let (.option(_, value?), _):
            return value.comparison(with: expected)
        case let (.number(answer), .integer(value)):
            return .ordered(Self.compare(answer, Decimal(value)))
        case let (.number(answer), .decimal(value)):
            return .ordered(Self.compare(answer, value))
        case let (.integerOption(answer), .integer(value)):
            return .ordered(Self.compare(answer, value))
        case let (.quantity(answer, unit), .quantity(value, system, code, text)):
            // `expected` is recorded for the question (see `recorded(for:)`), as the exported condition is.
            let threshold = RecordedQuantityUnit(system: system, code: code, text: text)
            return unit.orders(with: threshold) ? .ordered(Self.compare(answer, value)) : .unknown
        case let (.date(answer, style), .date(value)):
            return Self.compare(answer, value, style: style).map { .ordered($0) } ?? .unknown
        default:
            return .incomparable
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension [ConditionAnswer] {
    /// FHIR enableWhen: `!=` holds when no answer equals the value, so also without an answer;
    /// every other operator holds when at least one answer satisfies it. `nil` if the outcome is open.
    func satisfy(
        _ operator: Questionnaire.Condition.ComparisonOperator,
        _ value: Questionnaire.Condition.Value
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        let comparisons = map { $0.comparison(with: value) }
        // An answer whose comparison is open decides nothing, so the outcome is open unless another answer decides it.
        let isOpen = comparisons.contains {
            guard case .unknown = $0 else {
                return false
            }
            return true
        }
        func ordered(_ accepted: Set<ComparisonResult>) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
            let holds = comparisons.contains {
                guard case .ordered(let order) = $0 else {
                    return false
                }
                return accepted.contains(order)
            }
            return holds ? true : isOpen ? nil : false
        }
        switch `operator` {
        case .equal:
            return comparisons.contains { $0.isEqual == true } ? true : isOpen ? nil : false
        case .notEqual:
            return comparisons.contains { $0.isEqual == true } ? false : isOpen ? nil : true
        case .lessThan:
            return ordered([.orderedAscending])
        case .greaterThan:
            return ordered([.orderedDescending])
        case .lessThanOrEqual:
            return ordered([.orderedAscending, .orderedSame])
        case .greaterThanOrEqual:
            return ordered([.orderedDescending, .orderedSame])
        }
    }
}
