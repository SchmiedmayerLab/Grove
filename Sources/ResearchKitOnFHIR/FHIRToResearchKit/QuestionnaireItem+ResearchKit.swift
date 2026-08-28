//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if ResearchKit

import FHIRModelsExtensions
import Foundation
import ModelsR4
import ResearchKit


extension Questionnaire {
    /// Translates a FHIR `Questionnaire` into a series of ResearchKit `ORKSteps`.
    /// - Parameter evaluationInstant: The explicit instant used to resolve relative date bounds.
    /// - Parameter evaluationTimeZone: The explicit time zone used with a proleptic Gregorian calendar.
    /// - throws: if there is an issue with one of the items in the questionnaire,
    ///     or if the questionnaire contains items which cannot be represented using the ResearchKit types.
    func toORKSteps(
        titleOverride: String? = nil,
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone
    ) throws -> [ORKStep] {
        try validateResearchKitItems()
        return try (item ?? []).flatMap {
            try $0.toORKSteps(
                in: self,
                titleOverride: titleOverride,
                evaluationInstant: evaluationInstant,
                evaluationTimeZone: evaluationTimeZone
            )
        }
    }
}


extension QuestionnaireItem {
    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    fileprivate func toORKSteps(
        in questionnaire: Questionnaire,
        titleOverride: String?,
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone
    ) throws -> [ORKStep] {
        guard !self.hidden else {
            return []
        }
        guard let questionType = self.type.value else {
            throw FHIRToResearchKitConversionError.missingItemType(linkID: linkId.value?.string)
        }
        let title = titleOverride ?? questionnaire.title?.value?.string ?? ""
        let valueSets = questionnaire.getContainedValueSets()
        
        var steps: [ORKStep] = []
        var alreadyHandledNestedItems = false
        
        switch questionType {
        case .group:
            // Converts multiple questions in a group into a ResearchKit form step
            let groupStep = try self.groupToORKFormStep(
                title: title,
                valueSets: valueSets,
                evaluationInstant: evaluationInstant,
                evaluationTimeZone: evaluationTimeZone
            )
            steps.append(groupStep)
            // -groupToORKFormStep turns any potential nested items into parts of the form;
            // we need to skip them here since otherwise we'd end up including them twice.
            alreadyHandledNestedItems = true
        case .display:
            // Creates a ResearchKit instruction step with the string to display
            steps.append(try self.displayToORKInstructionStep(title: title))
        case .question, .boolean, .decimal, .integer, .date, .dateTime, .time, .string, .text, .url, .choice, .openChoice, .reference, .quantity:
            // Converts individual questions to ResearchKit Question steps
            let step = try self.toORKQuestionStep(
                title: title,
                valueSets: valueSets,
                evaluationInstant: evaluationInstant,
                evaluationTimeZone: evaluationTimeZone
            )
            if let required = self.required?.value?.bool {
                step.isOptional = !required
            }
            steps.append(step)
        case .attachment:
            // The FHIR Questionnaire attachment type is meant to support binary file upload, including
            // images. ResearchKit does not support arbitrary binary file upload, but does support image
            // capture, so we map this type to an ORKImageCaptureStep.
            steps.append(try self.attachmentToORKImageCaptureStep())
        }
        
        // Also handle any potential nested questions, if necessary.
        if !alreadyHandledNestedItems, let nestedItems = self.item {
            for item in nestedItems {
                steps.append(contentsOf: try item.toORKSteps(
                    in: questionnaire,
                    titleOverride: titleOverride,
                    evaluationInstant: evaluationInstant,
                    evaluationTimeZone: evaluationTimeZone
                ))
            }
        }
        
        return steps
    }
    
    /// Converts a FHIR `QuestionnaireItem` to a ResearchKit `ORKQuestionStep`.
    /// - Parameters:
    ///   - title: A `String` that will be displayed above the question when rendered by ResearchKit.
    ///   - valueSets: An array of `ValueSet` items containing sets of answer choices
    /// - Returns: An `ORKQuestionStep` object (a ResearchKit question step containing the above question).
    fileprivate func toORKQuestionStep(
        title: String,
        valueSets: [ValueSet],
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone
    ) throws -> ORKQuestionStep {
        let identifier = try requiredLinkID()
        let text = try requiredText(linkID: identifier)
        
        let answer = try self.toORKAnswerFormat(
            valueSets: valueSets,
            evaluationInstant: evaluationInstant,
            evaluationTimeZone: evaluationTimeZone
        )

        let prefix = prefix?.value?.string
        let questionText = prefix ?? text

        let step = ORKQuestionStep(identifier: identifier, title: title, question: questionText, answer: answer)

        if prefix != nil {
            step.text = text
        }

        return step
    }
    
    /// Converts a FHIR QuestionnaireItem that contains a group of question items into a ResearchKit form (ORKFormStep).
    /// - Parameters:
    ///   - title: A String that will be displayed at the top of the form when rendered by ResearchKit.
    ///   - valueSets: An array of `ValueSet` items containing sets of answer choices
    /// - Returns: An ORKFormStep object (a ResearchKit form step containing all of the nested questions).
    fileprivate func groupToORKFormStep(
        title: String,
        valueSets: [ValueSet],
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone
    ) throws -> ORKFormStep {
        guard self.type == .group else {
            throw FHIRToResearchKitConversionError.unsupportedItemType(
                type.value ?? .group,
                linkID: linkId.value?.string ?? "<unknown>"
            )
        }
        let id = try requiredLinkID()
        guard let nestedQuestions = item else {
            throw FHIRToResearchKitConversionError.noItems
        }
        let visibleQuestions = nestedQuestions.filter { !$0.hidden }
        guard !visibleQuestions.isEmpty else {
            throw FHIRToResearchKitConversionError.noItems
        }
        
        let formStep = ORKFormStep(identifier: id)
        formStep.title = title
        formStep.text = text?.value?.string ?? ""
        var formItems = [ORKFormItem]()

        var containsRequiredSteps = false

        for question in visibleQuestions {
            let questionId = try question.requiredLinkID()
            let questionText = try question.requiredText(linkID: questionId)

            if question.type.value == .display {
                let formItem = ORKFormItem(sectionTitle: questionText, detailText: question.placeholderText, learnMoreItem: nil, showsProgress: false)
                formItems.append(formItem)
            } else {
                let answerFormat = try question.toORKAnswerFormat(
                    valueSets: valueSets,
                    evaluationInstant: evaluationInstant,
                    evaluationTimeZone: evaluationTimeZone
                )
                let formItem = ORKFormItem(identifier: questionId, text: questionText, answerFormat: answerFormat)
                if let required = question.required?.value?.bool {
                    // if !optional, the `Continue` will stay disabled till the question is answered.
                    formItem.isOptional = !required
                    if required {
                        containsRequiredSteps = true
                    }
                }
                formItem.placeholder = question.placeholderText

                formItems.append(formItem)
            }
        }

        formStep.formItems = formItems
        // if optional, the `Next` button will appear
        formStep.isOptional = !(containsRequiredSteps || required?.value?.bool == true)
        return formStep
    }
    
    /// Converts FHIR `QuestionnaireItem` display type to `ORKInstructionStep`
    /// - Parameters:
    ///   - title: A `String` to display at the top of the view rendered by ResearchKit.
    /// - Returns: A ResearchKit `ORKInstructionStep`.
    fileprivate func displayToORKInstructionStep(title: String) throws -> ORKInstructionStep {
        guard self.type == .display else {
            throw FHIRToResearchKitConversionError.unsupportedItemType(
                type.value ?? .display,
                linkID: linkId.value?.string ?? "<unknown>"
            )
        }
        let id = try requiredLinkID()
        let text = try requiredText(linkID: id)
        
        let instructionStep = ORKInstructionStep(identifier: id)
        instructionStep.title = title
        instructionStep.detailText = text
        return instructionStep
    }

    /// Converts FHIR `QuestionnaireItem` attachment type to `ORKImageCaptureStep`
    /// - Returns: A ResearchKit `ORKImageCaptureStep`
    fileprivate func attachmentToORKImageCaptureStep() throws -> ORKImageCaptureStep {
        let id = try requiredLinkID()
        _ = try requiredText(linkID: id)
        return ORKImageCaptureStep(identifier: id)
    }
    
    /// Converts FHIR QuestionnaireItem answer types to the corresponding ResearchKit answer types (ORKAnswerFormat).
    /// - Parameter valueSets: An array of `ValueSet` items containing sets of answer choices
    /// - Returns: An object of type `ORKAnswerFormat` representing the type of answer this question accepts.
    private func toORKAnswerFormat( // swiftlint:disable:this cyclomatic_complexity function_body_length
        valueSets: [ValueSet],
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone
    ) throws -> ORKAnswerFormat {
        // We have to cover all the switch cases in the following statement driving up the overall complexity.
        switch type.value {
        case .boolean:
            return ORKBooleanAnswerFormat.booleanAnswerFormat()
        case .choice, .openChoice:
            let answerOptions = try toORKTextChoice(valueSets: valueSets, openChoice: type.value == .openChoice)
            guard !answerOptions.isEmpty else {
                throw FHIRToResearchKitConversionError.noOptions
            }
            let choiceAnswerStyle: ORKChoiceAnswerStyle = repeats?.value?.bool == true
                ? .multipleChoice
                : .singleChoice
            return ORKTextChoiceAnswerFormat(style: choiceAnswerStyle, textChoices: answerOptions)
        case .date:
            let calendar = Self.gregorianCalendar(timeZone: evaluationTimeZone)
            return ORKDateAnswerFormat(
                style: .date,
                defaultDate: nil,
                minimumDate: try date(
                    from: try minDateValue(evaluationInstant: evaluationInstant),
                    calendar: calendar
                ),
                maximumDate: try date(
                    from: try maxDateValue(evaluationInstant: evaluationInstant),
                    calendar: calendar
                ),
                calendar: calendar
            )
        case .dateTime:
            let calendar = Self.gregorianCalendar(timeZone: evaluationTimeZone)
            return ORKDateAnswerFormat(
                style: .dateAndTime,
                defaultDate: nil,
                minimumDate: try date(
                    from: try minDateValue(evaluationInstant: evaluationInstant),
                    calendar: calendar
                ),
                maximumDate: try date(
                    from: try maxDateValue(evaluationInstant: evaluationInstant),
                    calendar: calendar
                ),
                calendar: calendar
            )
        case .time:
            return ORKTimeOfDayAnswerFormat()
        case .decimal, .quantity:
            let answerFormat = ORKNumericAnswerFormat.decimalAnswerFormat(withUnit: unit)
            answerFormat.maximumFractionDigits = maximumDecimalPlaces
            answerFormat.minimum = try minValue
            answerFormat.maximum = try maxValue
            return answerFormat
        case .integer:
            if itemControl == "slider" {
                let minimum = try minValue
                let maximum = try maxValue
                let answerFormat = ORKScaleAnswerFormat(
                    maximumValue: maximum?.intValue ?? 0,
                    minimumValue: minimum?.intValue ?? 0,
                    defaultValue: minimum?.intValue ?? 0,
                    step: Int(truncating: sliderStepValue ?? 1)
                )
                return answerFormat
            }

            let answerFormat = ORKNumericAnswerFormat.integerAnswerFormat(withUnit: nil)
            answerFormat.minimum = try minValue
            answerFormat.maximum = try maxValue
            return answerFormat
        case .text, .string:
            let maximumLength = Int(maxLength?.value?.integer ?? 0)
            let answerFormat = ORKTextAnswerFormat(maximumLength: maximumLength)

            answerFormat.multipleLines = type.value == .text
#if os(iOS) || os(visionOS)
            if let keyboardType {
                answerFormat.keyboardType = keyboardType
            }
#endif
#if os(iOS) || os(visionOS) || os(tvOS)
            if let textContentType {
                answerFormat.textContentType = textContentType
            }
            if let autocapitalizationType {
                answerFormat.autocapitalizationType = autocapitalizationType
            }
#endif
            answerFormat.placeholder = self.placeholderText

            // Applies a regular expression for validation, if defined
            if let validationRegularExpression = try validationRegularExpression {
                answerFormat.validationRegularExpression = validationRegularExpression
                answerFormat.invalidMessage = validationMessage ?? "Invalid input"
            }
            
            return answerFormat
        case .url:
            return ORKTextAnswerFormat()
        case .question, .reference, .attachment, .display, .group, nil:
            throw FHIRToResearchKitConversionError.unsupportedItemType(
                type.value ?? .question,
                linkID: linkId.value?.string ?? "<unknown>"
            )
        }
    }
    
    /// Converts FHIR text answer choices to ResearchKit `ORKTextChoice`.
    /// - Parameter - valueSets: An array of `ValueSet` items containing sets of answer choices
    /// - Returns: An array of `ORKTextChoice` objects, each representing a textual answer option.
    private func toORKTextChoice(valueSets: [ValueSet], openChoice: Bool) throws -> [ORKTextChoice] {
        var choices: [ORKTextChoice]

        // If the `QuestionnaireItem` has an `answerValueSet` defined which is a reference to a contained `ValueSet`,
        // search the available `ValueSets`and, if a match is found, convert the options to `ORKTextChoice`
        if let answerValueSetURL = answerValueSet?.value?.url.absoluteString,
           answerValueSetURL.starts(with: "#") {
            choices = try containedChoices(valueSets: valueSets, canonical: answerValueSetURL)
        } else {
            // If the `QuestionnaireItem` has `answerOptions` defined instead, extract these options
            // and convert them to `ORKTextChoice`
            guard let answerOptions = answerOption, !answerOptions.isEmpty else {
                throw FHIRToResearchKitConversionError.noOptions
            }
            choices = try inlineChoices(answerOptions)
        }

        if openChoice {
            let otherChoiceText = NSLocalizedString("Other", comment: "")
            choices.append(ORKTextChoiceOther.choice(
                withText: otherChoiceText,
                detailText: nil,
                value: otherChoiceText as any NSSecureCoding & NSCopying & NSObjectProtocol,
                exclusive: true,
                textViewPlaceholderText: ""
            ))
        }
        return choices
    }

    private func containedChoices(valueSets: [ValueSet], canonical: String) throws -> [ORKTextChoice] {
        let matchingValueSets = valueSets.filter { valueSet in
            guard let id = valueSet.id?.value?.string else {
                return false
            }
            return "#\(id)" == canonical
        }
        guard matchingValueSets.count == 1,
              let valueSet = matchingValueSets.first,
              valueSet.compose?.include.count == 1,
              let include = valueSet.compose?.include.first,
              let answerOptions = include.concept,
              !answerOptions.isEmpty else {
            throw FHIRToResearchKitConversionError.unresolvedContainedValueSet(canonical)
        }
        return try answerOptions.map { option in
            guard let display = option.display?.value?.string,
                  let code = option.code.value?.string,
                  let system = include.system?.value?.url.absoluteString else {
                throw FHIRToResearchKitConversionError.invalidChoiceOption(
                    linkID: linkId.value?.string ?? "<unknown>"
                )
            }
            let value = ValueCoding(code: code, system: system, display: display).rawValue
            return ORKTextChoice(text: display, value: value as any NSSecureCoding & NSCopying & NSObjectProtocol)
        }
    }

    private func inlineChoices(
        _ answerOptions: [QuestionnaireItemAnswerOption]
    ) throws -> [ORKTextChoice] {
        try answerOptions.map { option in
            guard case let .coding(coding) = option.value,
                  let display = coding.display?.value?.string,
                  let code = coding.code?.value?.string,
                  let system = coding.system?.value?.url.absoluteString else {
                throw FHIRToResearchKitConversionError.invalidChoiceOption(
                    linkID: linkId.value?.string ?? "<unknown>"
                )
            }
            let value = ValueCoding(code: code, system: system, display: display).rawValue
            return ORKTextChoice(text: display, value: value as any NSSecureCoding & NSCopying & NSObjectProtocol)
        }
    }

    private func requiredLinkID() throws -> String {
        guard let value = linkId.value?.string,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FHIRToResearchKitConversionError.missingLinkID
        }
        return value
    }

    private func requiredText(linkID: String) throws -> String {
        guard let value = text?.value?.string,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FHIRToResearchKitConversionError.missingText(linkID: linkID)
        }
        return value
    }

    private func date(from components: DateComponents?, calendar: Calendar) throws -> Date? {
        guard let components else {
            return nil
        }
        guard let date = calendar.date(from: components) else {
            throw FHIRToResearchKitConversionError.invalidDateBound(
                linkID: linkId.value?.string ?? "<unknown>"
            )
        }
        return date
    }
}
#endif
