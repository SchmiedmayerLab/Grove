//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    public enum ResponseValidationResult: Sendable {
        /// The response provided for the task is ok.
        case ok
        /// The response provided for the task is invalid, with the text to show the participant.
        ///
        /// Already resolved: a caller off-Apple has no catalogue to resolve against, and the only
        /// consumer is the questionnaire UI, which displays it as-is.
        case invalid(message: String)
        
        package var isOk: Bool {
            switch self {
            case .ok:
                true
            case .invalid:
                false
            }
        }
        
        var isInvalid: Bool {
            switch self {
            case .ok:
                false
            case .invalid:
                true
            }
        }
        
        /// Creates a ``invalid(message:)`` localized to the specified bundle.
        ///
        /// - Important: Use this function when creating `invalid` results within the package, to ensure that the localization is picked up correctly.
        #if canImport(Darwin)
        static func invalid(message: String.LocalizationValue, bundle: Bundle) -> Self {
            .invalid(message: String(localized: message, bundle: bundle))
        }
        #else
        // No string catalogues off-Apple: the key is the message.
        static func invalid(message: String, bundle: Bundle) -> Self {
            .invalid(message: message)
        }
        #endif
    }
    
    
    /// Renders an hour/minute/second bound like "9:30 AM" for a validation message.
    ///
    /// The components are anchored to the fixed reference date, not today: `date(bySettingHour:)`
    /// on a daylight-saving transition day can shift or skip the requested wall time.
    private static func formattedTime(hour: Int, minute: Int, second: Int) -> String? {
        Calendar.current
            .date(bySettingHour: hour, minute: minute, second: second, of: Date(timeIntervalSinceReferenceDate: 0))?
            .formatted(date: .omitted, time: .shortened)
    }

    package func validateResponse( // swiftlint:disable:this function_body_length cyclomatic_complexity
        for task: Questionnaire.Task
    ) -> ResponseValidationResult {
        guard hasResponse(for: task) else {
            // if no response exists, there is nothing that could be invalid.
            // were we to report this as being invalid, every questionnaire would,
            // the instant it's opened, turn bright red bc every question would complain about an invalid response
            return .ok
        }
        // Authored rules (FHIR targetConstraint): the expression must hold for the answer.
        if let engine = questionnaire.expressionEngine {
            for constraint in task.constraints where constraint.severity == .error {
                do {
                    if try engine.evaluateBoolean(constraint.expression, scope: .answer(task.id), in: self) == .false {
                        return .invalid(message: constraint.humanDescription)
                    }
                } catch {
                    // A rule that cannot be evaluated proves nothing, so the answer stands;
                    // the failure is recorded so the instrument's author learns about it.
                    recordExpressionFailure(constraint.expression, for: task.id, error: error)
                }
            }
        }
        switch task.kind.variant {
        case .instructional:
            // instructional tasks never can have a response, so they're always ok
            return .ok
        case .boolean:
            // the user cannot provide an invalid response for boolean tasks
            return .ok
        case .choice(let config):
            // questionnaire-minOccurs/maxOccurs bound the selection count of multi-selects.
            let selectionCount = responses[task.id].value.choiceValue.selectedOptions.count
            if let minSelections = config.minSelections, selectionCount < minSelections {
                return .invalid(message: "Select at least \(minSelections) options", bundle: .module)
            }
            if let maxSelections = config.maxSelections, selectionCount > maxSelections {
                return .invalid(message: "Select at most \(maxSelections) options", bundle: .module)
            }
            if config.hasFreeTextOtherOption {
                guard let response = responses[task.id].value.choiceValue.freeTextOtherResponse else {
                    // this option isn't selected, so we're good
                    return .ok
                }
                guard !response.isEmpty else {
                    return .invalid(message: "Missing response text for \"Other\" option", bundle: .module)
                }
                return .ok
            } else {
                // NOTE that we intentionally don't validate nested responses here.
                // it should only be possible to leave the nested response answering sheet,
                // if either all responses there are valid, or by canceling, in which case the responses there are discarded.
                return .ok
            }
        case .freeText(let config):
            guard let response = responses[task.id].value.stringValue else {
                return .ok
            }
            func isLengthValid(_ allowed: some RangeExpression<Int>) -> Bool {
                allowed.contains(response.count)
            }
            switch (config.minLength, config.maxLength) {
            case (.none, .none):
                break
            case (.some(let minLength), .none):
                if !isLengthValid(minLength...) {
                    return .invalid(message: "Too short: must be at least \(minLength) characters", bundle: .module)
                }
            case (.none, .some(let maxLength)):
                if !isLengthValid(...maxLength) {
                    return .invalid(message: "Too long: can be at most \(maxLength) characters", bundle: .module)
                }
            case let (.some(minLength), .some(maxLength)):
                guard maxLength >= minLength else {
                    break
                }
                if !isLengthValid(minLength...maxLength) {
                    return .invalid(message: "Length must be between \(minLength) and \(maxLength)", bundle: .module)
                }
            }
            let responseNSString = response as NSString
            let wholeStringRange = NSRange(location: 0, length: responseNSString.length)
            // FHIR regexes are anchored: the answer as a whole has to match, not some part of it.
            if let regex = config.regex, regex.rangeOfFirstMatch(in: response, range: wholeStringRange) != wholeStringRange {
                return config.expectedFormat
            }
            if config.expectsURL {
                guard let url = URL(string: response), url.scheme != nil else {
                    return config.expectedFormat
                }
            }
            return .ok
        case .dateTime(let config):
            let cal = Calendar.current
            guard let response = responses[task.id].value.dateValue else {
                return .ok
            }
            switch config.style {
            case .timeOnly:
                let response = (response.hour ?? 0, response.minute ?? 0, response.second ?? 0)
                if let minValue = config.minValue.map({ ($0.hour ?? 0, $0.minute ?? 0, $0.second ?? 0) }), !(response >= minValue) {
                    return .invalid(
                        message: "Must be after \(Self.formattedTime(hour: minValue.0, minute: minValue.1, second: minValue.2) ?? (config.minValue ?? .init()).description)",
                        bundle: .module
                    )
                }
                if let maxValue = config.maxValue.map({ ($0.hour ?? 0, $0.minute ?? 0, $0.second ?? 0) }), !(response <= maxValue) {
                    return .invalid(
                        message: "Must be before \(Self.formattedTime(hour: maxValue.0, minute: maxValue.1, second: maxValue.2) ?? (config.maxValue ?? .init()).description)",
                        bundle: .module
                    )
                }
                return .ok
            case .dateOnly, .dateAndTime:
                guard let responseDate = cal.date(from: response) else {
                    // very likely unreachable
                    return .invalid(message: "Invalid Input", bundle: .module)
                }
                if let minDate = config.minValue.flatMap({ cal.date(from: $0) }), responseDate < minDate {
                    return .invalid(message: "Must be after \(minDate.formatted(.dateTime))", bundle: .module)
                }
                if let maxDate = config.maxValue.flatMap({ cal.date(from: $0) }), responseDate > maxDate {
                    return .invalid(message: "Must be before \(maxDate.formatted(.dateTime))", bundle: .module)
                }
                return .ok
            }
        case .numeric(let config):
            guard let response = responses[task.id].value.numberValue else {
                return .ok
            }
            // Formatted, not interpolated: a bound of 100 is stored as a Double and reads back as
            // "100.0", and one that came from a division drags a dozen decimals in with it.
            if let minimum = config.minimum, response < minimum {
                return .invalid(message: "Must be at least \(minimum.formatted(.number))", bundle: .module)
            }
            if let maximum = config.maximum, response > maximum {
                return .invalid(message: "Must be at most \(maximum.formatted(.number))", bundle: .module)
            }
            if let maxDecimalPlaces = config.maxDecimalPlaces {
                let fmtNormal = response.formatted(.number)
                let fmtLimit = response.formatted(.number.precision(.fractionLength(Int(maxDecimalPlaces))))
                return fmtNormal == fmtLimit
                    ? .ok
                    : .invalid(message: "Limited to \(maxDecimalPlaces) decimal places", bundle: .module)
            }
            return .ok
        case .fileAttachment(let config):
            if let maxSize = config.maxSize,
               let attachments = responses[task.id].value.attachmentsValue,
               let oversized = attachments.first(where: { ($0.size ?? 0) > maxSize }) {
                let limit = ByteCountFormatStyle().format(Int64(maxSize))
                return .invalid(message: "'\(oversized.filename)' exceeds the maximum file size of \(limit)", bundle: .module)
            }
            return .ok
        case let .custom(questionKind, config):
            return questionKind.validate(response: responses[task.id], for: config)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task.Kind.FreeTextConfig {
    /// What the answer is supposed to look like, said in terms of the answer.
    ///
    /// The rule that rejected it is a regular expression or a URL parse, and neither tells the
    /// participant anything. What the question is asking for does, and the keyboard the question
    /// asks for is the authored declaration of that.
    fileprivate var expectedFormat: QuestionnaireResponses.ResponseValidationResult {
        if expectsURL || keyboard == .url {
            return .invalid(message: "Enter a web address, like https://example.org", bundle: .module)
        }
        switch keyboard {
        case .email:
            return .invalid(message: "Enter an email address, like name@example.org", bundle: .module)
        case .phone:
            return .invalid(message: "Enter a phone number", bundle: .module)
        case .number:
            return .invalid(message: "Enter a number", bundle: .module)
        case .url, .none:
            return .invalid(message: "This isn't in the format this question expects", bundle: .module)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionKindDefinition {
    fileprivate static func validate(
        response: QuestionnaireResponses.Response,
        for config: any QuestionKindConfig
    ) -> QuestionnaireResponses.ResponseValidationResult {
        guard let config = config as? Config else {
            return .invalid(message: "Internal Error", bundle: .module)
        }
        return self.validate(response: response, for: config)
    }
}
