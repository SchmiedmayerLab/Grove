//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


// MARK: Boolean

/// A Yes/No question (FHIR item type `boolean`).
@available(iOS 18, macOS 15, watchOS 11, *)
public struct BooleanQuestion: TypedQuestion {
    public typealias Answer = Bool

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    let title: String

    /// A condition that holds while this question is answered Yes.
    public var isTrue: Questionnaire.Condition {
        self == true
    }

    /// A condition that holds while this question is answered No.
    public var isFalse: Questionnaire.Condition {
        self == false
    }

    /// Creates a Yes/No question.
    /// - parameter id: The question's linkId.
    /// - parameter title: The question text.
    public init(_ id: Questionnaire.Task.ID, _ title: String) {
        self.id = id
        self.title = title
    }

    // `Answer?` is the TypedQuestion contract: nil means the participant has not answered.
    // swiftlint:disable:next identifier_name discouraged_optional_boolean
    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> Bool? {
        value.boolValue
    }

    /// A condition comparing this question's answer to a value.
    public static func == (question: Self, value: Bool) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .equal, value: .bool(value))
    }

    public func _storeAnswer(_ answer: Bool) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        .bool(answer)
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: title, kind: .boolean)
        _core.apply(to: &task)
        return [task]
    }
}


// MARK: Text

/// A free-text question (FHIR item type `string`/`text`).
@available(iOS 18, macOS 15, watchOS 11, *)
public struct TextQuestion: TypedQuestion {
    public typealias Answer = String

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    let title: String
    var config = Questionnaire.Task.Kind.FreeTextConfig()

    /// Creates a free-text question.
    public init(_ id: Questionnaire.Task.ID, _ title: String) {
        self.id = id
        self.title = title
    }

    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> String? { // swiftlint:disable:this identifier_name
        value.stringValue
    }

    /// A condition comparing this question's answer to a value.
    public static func == (question: Self, value: String) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .equal, value: .string(value))
    }

    /// Bounds the response length (FHIR `maxLength` / `minLength`).
    public func length(_ range: ClosedRange<Int>) -> Self {
        var copy = self
        copy.config.minLength = range.lowerBound
        copy.config.maxLength = range.upperBound
        return copy
    }

    /// Validates the response against a regular expression (FHIR `regex`).
    public func matching(_ regex: NSRegularExpression) -> Self {
        var copy = self
        copy.config.regex = regex
        return copy
    }

    /// Hints the on-screen keyboard suited to the expected entry (SDC `keyboard`).
    public func keyboard(_ keyboard: Questionnaire.Task.Kind.FreeTextConfig.KeyboardHint) -> Self {
        var copy = self
        copy.config.keyboard = keyboard
        return copy
    }

    /// Asks for an answer of several lines rather than a few words (FHIR item type `text`).
    public func multiline(_ isMultiline: Bool = true) -> Self {
        var copy = self
        copy.config.isMultiline = isMultiline
        return copy
    }

    public func _storeAnswer(_ answer: String) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        .string(answer)
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: title, kind: .freeText(config))
        _core.apply(to: &task)
        return [task]
    }
}


// MARK: Dates

/// A date, time, or date-and-time question (FHIR item types `date`, `time`, `dateTime`).
@available(iOS 18, macOS 15, watchOS 11, *)
public struct DateQuestion: TypedQuestion {
    public typealias Answer = DateComponents

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    let title: String
    var style: Questionnaire.Task.Kind.DateTimeConfig.Style = .dateOnly
    var minValue: DateComponents?
    var maxValue: DateComponents?

    /// Creates a date question (`valueDate` answers).
    public init(_ id: Questionnaire.Task.ID, _ title: String) {
        self.id = id
        self.title = title
    }

    /// Creates a time-of-day question (`valueTime` answers).
    public static func time(_ id: Questionnaire.Task.ID, _ title: String) -> Self {
        var question = Self(id, title)
        question.style = .timeOnly
        return question
    }

    /// Creates a date-and-time question (`valueDateTime` answers).
    public static func dateTime(_ id: Questionnaire.Task.ID, _ title: String) -> Self {
        var question = Self(id, title)
        question.style = .dateAndTime
        return question
    }

    // swiftlint:disable:next identifier_name
    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> DateComponents? {
        value.dateValue
    }

    /// Bounds the accepted dates (FHIR `minValue`/`maxValue`).
    public func range(from minValue: DateComponents? = nil, to maxValue: DateComponents? = nil) -> Self {
        var copy = self
        copy.minValue = minValue
        copy.maxValue = maxValue
        return copy
    }

    public func _storeAnswer(_ answer: DateComponents) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        .date(answer)
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: title, kind: .dateTime(.init(
            style: style,
            minValue: minValue,
            maxValue: maxValue
        )))
        _core.apply(to: &task)
        return [task]
    }
}


// MARK: Numbers

/// A numeric question (FHIR item types `integer`, `decimal`, and `quantity`).
@available(iOS 18, macOS 15, watchOS 11, *)
public struct NumberQuestion: TypedQuestion {
    public typealias Answer = Double

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    let title: String
    var valueKind: Questionnaire.Task.Kind.NumericTaskConfig.ValueKind
    var minimum: Double?
    var maximum: Double?
    var slider: Double?
    var unit: Questionnaire.Task.Kind.NumericTaskConfig.UnitOption?
    var unitOptions: [Questionnaire.Task.Kind.NumericTaskConfig.UnitOption] = []

    /// Creates a decimal question (`valueDecimal` answers).
    public init(_ id: Questionnaire.Task.ID, _ title: String) {
        self.id = id
        self.title = title
        self.valueKind = .decimal
    }

    /// Creates an integer question (`valueInteger` answers).
    public static func integer(_ id: Questionnaire.Task.ID, _ title: String) -> Self {
        var question = Self(id, title)
        question.valueKind = .integer
        return question
    }

    /// Creates a quantity question with a coded unit (`valueQuantity` answers).
    /// - parameter id: The question's stable link identifier.
    /// - parameter title: The question displayed to the participant.
    /// - parameter unit: The unit's UCUM code (e.g. `"kg"`).
    /// - parameter system: The unit's coding system; defaults to UCUM.
    /// - parameter display: The user-displayed unit label; defaults to the code.
    public static func quantity(
        _ id: Questionnaire.Task.ID,
        _ title: String,
        unit: String,
        system: URL? = URL(string: "http://unitsofmeasure.org"),
        display: String? = nil
    ) -> Self {
        var question = Self(id, title)
        question.valueKind = .quantity
        question.unit = .init(display: display ?? unit, system: system, code: unit)
        return question
    }

    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> Double? { // swiftlint:disable:this identifier_name
        value.numberValue
    }

    public static func == (question: Self, value: Double) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .equal, value: .decimal(value))
    }

    public static func > (question: Self, value: Double) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .greaterThan, value: .decimal(value))
    }

    public static func >= (question: Self, value: Double) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .greaterThanOrEqual, value: .decimal(value))
    }

    public static func < (question: Self, value: Double) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .lessThan, value: .decimal(value))
    }

    public static func <= (question: Self, value: Double) -> Questionnaire.Condition {
        .responseValueComparison(taskId: question.id, operator: .lessThanOrEqual, value: .decimal(value))
    }

    /// Bounds the accepted values (FHIR `minValue`/`maxValue`).
    public func range(_ range: ClosedRange<Double>) -> Self {
        var copy = self
        copy.minimum = range.lowerBound
        copy.maximum = range.upperBound
        return copy
    }

    /// Renders the question as a slider with the given step (`slider` itemControl).
    public func slider(step: Double) -> Self {
        var copy = self
        copy.slider = step
        return copy
    }

    /// Lets the participant choose among units (FHIR `questionnaire-unitOption`).
    public func unitOptions(_ options: [Questionnaire.Task.Kind.NumericTaskConfig.UnitOption]) -> Self {
        var copy = self
        copy.unitOptions = options
        return copy
    }

    public func _storeAnswer(_ answer: Double) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        .number(answer)
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        let inputMode: Questionnaire.Task.Kind.NumericTaskConfig.InputMode = if let slider {
            .slider(stepValue: slider)
        } else {
            .numberPad(valueKind == .integer ? .integer : .decimal)
        }
        var task = Questionnaire.Task(id: id, title: title, kind: .numeric(.init(
            inputMode: inputMode,
            minimum: minimum,
            maximum: maximum,
            unit: unit?.display ?? "",
            unitSystem: unit?.system,
            unitCode: unit?.code,
            valueKind: valueKind,
            unitOptions: unitOptions
        )))
        _core.apply(to: &task)
        return [task]
    }
}
