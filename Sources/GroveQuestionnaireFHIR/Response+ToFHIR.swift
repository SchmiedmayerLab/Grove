//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses.Response {
    struct FHIRConversionContext { // maybe also use this for the CustomResponseValue conversion?
        let task: GroveQuestionnaire.Questionnaire.Task
    }

    func toFHIR( // swiftlint:disable:this function_body_length cyclomatic_complexity
        using context: FHIRConversionContext
    ) throws -> QuestionnaireResponseItem? {
        // QUESTION do we need to place responses to tasks contained in a FHIR group in an empty QuestionnaireResponseItem?
        // (RKoF currently doesn't)
        let task = context.task
        if !nestedResponses.isEmpty, task.kind.followUpTasks.isEmpty {
            throw FHIRResponseConversionError("Unexpectedly found nested responses in task without nested tasks")
        }
        var responseItem = QuestionnaireResponseItem(
            linkId: context.task.id.asFHIRStringPrimitive()
        )
        if !task.title.isEmpty {
            // Carry the question text so consumers can review answers without
            // resolving the questionnaire.
            responseItem.text = task.title.asFHIRStringPrimitive()
        }
        switch task.kind.variant {
        case let .custom(questionKind, config: _):
            if let questionKind = questionKind as? any QuestionKindDefinitionWithFHIREncodingSupport.Type {
                // Swallowing an encoding error here would emit a contentless item for an
                // answered question — silent data loss. Let the conversion fail instead.
                responseItem.answer = try questionKind.toFHIR(self, for: task)
                return responseItem
            }
        default:
            break
        }
        switch self.value {
        case .none:
            guard nestedResponses.isEmpty else {
                throw FHIRResponseConversionError("Found empty response with nested responses")
            }
            return nil
        case .string(let response):
            if case .freeText(let config) = task.kind.variant, config.expectsURL {
                // FHIR pairs item type `url` with valueUri.
                guard let url = URL(string: response) else {
                    throw FHIRResponseConversionError("Response to url item '\(task.id)' is not a valid URI")
                }
                responseItem.answer = [.init(value: .uri(FHIRPrimitive(ModelsR4.FHIRURI(url))))]
            } else {
                responseItem.answer = [
                    .init(value: .string(response.asFHIRStringPrimitive()))
                ]
            }
        case .bool(let response):
            responseItem.answer = [
                .init(value: .boolean(response.asPrimitive()))
            ]
        case .date(let response):
            let value = try dateAnswerValue(response, for: task)
            responseItem.answer = [.init(value: value)]
        case .number(let response):
            guard case .numeric(let config) = task.kind.variant else {
                throw FHIRResponseConversionError("Invalid Input")
            }
            let value: QuestionnaireResponseItemAnswer.ValueX
            switch config.valueKind {
            case .integer:
                // FHIR pairs item type `integer` with valueInteger.
                guard let integer = Int32(exactly: response) else {
                    throw FHIRResponseConversionError("Response to integer item '\(task.id)' is not an integer")
                }
                value = .integer(FHIRPrimitive(FHIRInteger(integer)))
            case .quantity:
                value = .quantity(Quantity(
                    code: config.unitCode?.asFHIRStringPrimitive(),
                    system: config.unitSystem?.asFHIRURIPrimitive(),
                    unit: (config.unit.isEmpty ? config.unitCode : config.unit)?.asFHIRStringPrimitive(),
                    value: response.asFHIRDecimalPrimitive()
                ))
            case .decimal:
                value = .decimal(response.asFHIRDecimalPrimitive())
            }
            responseItem.answer = [.init(value: value)]
        case let .quantity(response, unitCode):
            guard case .numeric(let config) = task.kind.variant else {
                throw FHIRResponseConversionError("Invalid Input")
            }
            // The participant chose the unit (questionnaire-unitOption).
            let unitOption = config.unitOptions.first { $0.code == unitCode }
            responseItem.answer = [
                .init(value: .quantity(Quantity(
                code: unitCode.asFHIRStringPrimitive(),
                system: (unitOption?.system ?? config.unitSystem)?.asFHIRURIPrimitive(),
                unit: (unitOption?.display ?? (config.unit.isEmpty ? unitCode : config.unit)).asFHIRStringPrimitive(),
                value: response.asFHIRDecimalPrimitive()
            )))
            ]
        case .choice(let response):
            guard case .choice(let config) = task.kind.variant else {
                throw FHIRResponseConversionError("Invalid Input")
            }
            responseItem.answer = try response.selectedOptions.map { optionId in
                // Option ids are `system|code` tokens; a bare code matches on the code alone,
                // as conditions do.
                guard let option = config.options.first(where: { $0.id == optionId })
                    ?? config.options.first(where: { !optionId.contains("|") && $0.id.hasSuffix("|\(optionId)") }) else {
                    throw FHIRResponseConversionError("Unable to find option for '\(optionId)'")
                }
                return QuestionnaireResponseItemAnswer(value: try option.toFHIRAnswerValue())
            }
            if let otherText = response.freeTextOtherResponse {
                // SAFETY: we just assigned a non-nil value above
                responseItem.answer!.append(.init(value: .string(otherText.asFHIRStringPrimitive()))) // swiftlint:disable:this force_unwrapping
            }
        case .attachments(let responses):
            responseItem.answer = try responses.map { attachment in
                try .init(attachment)
            }
        case .custom(let value):
            typealias CustomFHIRSupportingValue = any QuestionnaireResponses.CustomResponseValueProtocolWithFHIRSupport
            guard let value = value as? CustomFHIRSupportingValue else {
                throw FHIRResponseConversionError(
                    """
                    Encountered custom response value of type '\(type(of: value))', which is missing FHIR support.
                    (Add FHIR support by conforming to '\(CustomFHIRSupportingValue.self)'.)
                    """
                )
            }
            if !value.isEmpty {
                responseItem.answer = try value.toFHIR(for: context.task)
            } else {
                responseItem.answer = nil
            }
        }
        guard !nestedResponses.isEmpty else {
            return responseItem
        }
        switch task.kind.variant {
        case .choice(let taskConfig):
            for (nestingId, responses) in nestedResponses {
                switch nestingId {
                case .choiceOption(let optionId):
                    guard let option = taskConfig.options.first(where: { $0.id == optionId }) else {
                        throw FHIRResponseConversionError("Unable to find choice option '\(optionId)'")
                    }
                    guard self.value.choiceValue.selectedOptions.contains(option.id) else {
                        throw FHIRResponseConversionError("Found a nested answer for a choice option that isn't selected ('\(option.id)')")
                    }
                    guard let answerIdx = responseItem.answer?.firstIndex(where: { $0.value == .coding(option.toFHIRCoding()) }) else {
                        throw FHIRResponseConversionError("Unable to find answer for choice option")
                    }
                    // SAFETY: the guard above proved `answer` is non-nil
                    responseItem.answer![answerIdx].item = try responses.toFHIR(using: .init(allTasks: task.kind.followUpTasks))
                    // swiftlint:disable:previous force_unwrapping
                }
            }
        default:
            // Question: how to best handle this?
            throw FHIRResponseConversionError("Invalid Input")
        }
        return responseItem
    }

    /// The FHIR answer value for a date answer, typed to match the item's date/time style.
    private func dateAnswerValue(
        _ response: DateComponents,
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> QuestionnaireResponseItemAnswer.ValueX {
        guard case .dateTime(let config) = task.kind.variant else {
            throw FHIRResponseConversionError("Invalid Input")
        }
        switch config.style {
        case .dateOnly:
            guard let year = response.year else {
                throw FHIRResponseConversionError("Date answer is missing a year")
            }
            return .date(FHIRPrimitive(FHIRDate(
                year: year,
                month: response.month.map(numericCast),
                day: response.day.map(numericCast)
            )))
        case .timeOnly:
            return .time(FHIRPrimitive(FHIRTime(
                hour: response.hour.map(numericCast) ?? 0,
                minute: response.minute.map(numericCast) ?? 0,
                second: response.second.map { Decimal($0) } ?? 0
            )))
        case .dateAndTime:
            guard let year = response.year else {
                throw FHIRResponseConversionError("Date answer is missing a year")
            }
            // Without a zone, FHIRModels serializes a DateTime as date-only,
            // silently dropping the collected time of day; R4 also requires an
            // offset whenever a time is present.
            return .dateTime(FHIRPrimitive(DateTime(
                date: FHIRDate(
                    year: year,
                    month: response.month.map(numericCast),
                    day: response.day.map(numericCast)
                ),
                time: FHIRTime(
                    hour: response.hour.map(numericCast) ?? 0,
                    minute: response.minute.map(numericCast) ?? 0,
                    second: response.second.map { Decimal($0) } ?? 0
                ),
                timezone: .current
            )))
        }
    }
}
