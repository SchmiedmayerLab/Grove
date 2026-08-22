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
extension ModelsR4.QuestionnaireItem {
    /// Writes what is specific to the question kind: its bounds, units, options and attachment limits.
    mutating func applyKindDetails(
        of task: GroveQuestionnaire.Questionnaire.Task,
        using context: FHIRExportContext,
        extensions: inout [Extension]
    ) throws {
        switch task.kind.variant {
        case .freeText(let config):
            if let maxLength = config.maxLength {
                self.maxLength = FHIRPrimitive(FHIRInteger(Int32(clamping: maxLength)))
            }
            extensions += config.fhirExtensions()
        case .numeric(let config):
            extensions += config.fhirExtensions(forTaskWithId: task.id, using: context)
        case .choice(let config):
            try applyChoiceDetails(config, of: task, extensions: &extensions)
        case .fileAttachment(let config):
            self.repeats = config.allowsMultipleSelection ? FHIRPrimitive(FHIRBool(true)) : nil
            if let maxSize = config.maxSize {
                extensions.append(Extension(
                    url: "http://hl7.org/fhir/StructureDefinition/maxSize",
                    value: .decimal(FHIRPrimitive(FHIRDecimal(Decimal(maxSize))))
                ))
            }
        case .instructional, .boolean, .dateTime, .custom:
            break
        }
    }

    private mutating func applyChoiceDetails(
        _ config: GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig,
        of task: GroveQuestionnaire.Questionnaire.Task,
        extensions: inout [Extension]
    ) throws {
        self.repeats = config.allowsMultipleSelection ? FHIRPrimitive(FHIRBool(true)) : nil
        let preSelected: Set<String> = if case .choice(let choice)? = task.initialValue {
            choice.selectedOptions
        } else {
            []
        }
        let answerOptions = try config.answerOptions(preSelected: preSelected, on: task.id)
        self.answerOption = answerOptions.isEmpty ? nil : answerOptions
        extensions += config.presentationExtensions()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Task.Kind.FreeTextConfig {
    /// The length, pattern and keyboard constraints a free-text question exports.
    fileprivate func fhirExtensions() -> [Extension] {
        var extensions: [Extension] = []
        if let minLength {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/minLength",
                value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: minLength))))
            ))
        }
        if let regex {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/regex",
                value: .string(regex.pattern.asFHIRStringPrimitive())
            ))
        }
        if let keyboard {
            // SDC types this extension's value as a Coding, bound to `keyboardType`.
            extensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-keyboard",
                value: .coding(Coding(
                    code: keyboard.rawValue.asFHIRStringPrimitive(),
                    system: "http://hl7.org/fhir/uv/sdc/CodeSystem/keyboardType".asFHIRURIPrimitive()
                ))
            ))
        }
        return extensions
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Task.Kind.NumericTaskConfig {
    /// The precision, bound, slider and unit constraints a numeric question exports.
    fileprivate func fhirExtensions(
        forTaskWithId taskId: GroveQuestionnaire.Questionnaire.Task.ID,
        using context: FHIRExportContext
    ) -> [Extension] {
        var extensions: [Extension] = []
        if valueKind == .decimal, let maxDecimalPlaces {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces",
                value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: maxDecimalPlaces))))
            ))
        }
        extensions += boundExtensions(forTaskWithId: taskId, using: context)
        if case .slider(let step) = inputMode {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                value: .codeableConcept(CodeableConcept(coding: [
                    Coding(
                    code: "slider".asFHIRStringPrimitive(),
                    system: "http://hl7.org/fhir/questionnaire-item-control".asFHIRURIPrimitive()
                )
                ]))
            ))
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-sliderStepValue",
                value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: Int(step)))))
            ))
        }
        return extensions + unitExtensions()
    }

    private func boundExtensions(
        forTaskWithId taskId: GroveQuestionnaire.Questionnaire.Task.ID,
        using context: FHIRExportContext
    ) -> [Extension] {
        // A bound must be typed like the answer it bounds: a decimal bound on an
        // integer item fails validation, and only SDC's min/maxQuantity carries a unit.
        func boundExtension(_ value: Double, core: String, quantity: String) -> Extension {
            switch valueKind {
            case .integer:
                Extension(
                    url: FHIRPrimitive(FHIRURI(stringLiteral: core)),
                    value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: Int(value)))))
                )
            case .decimal:
                Extension(
                    url: FHIRPrimitive(FHIRURI(stringLiteral: core)),
                    value: .decimal(value.asFHIRDecimalPrimitive())
                )
            case .quantity:
                Extension(
                    url: FHIRPrimitive(FHIRURI(stringLiteral: quantity)),
                    value: .quantity(context.quantity(value, unitCode: unitCode, forTaskWithId: taskId))
                )
            }
        }
        var extensions: [Extension] = []
        if let minimum {
            extensions.append(boundExtension(
                minimum,
                core: "http://hl7.org/fhir/StructureDefinition/minValue",
                quantity: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity"
            ))
        }
        if let maximum {
            extensions.append(boundExtension(
                maximum,
                core: "http://hl7.org/fhir/StructureDefinition/maxValue",
                quantity: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity"
            ))
        }
        return extensions
    }

    private func unitExtensions() -> [Extension] {
        var extensions: [Extension] = []
        if let unitCode {
            // `questionnaire-unit` is restricted to integer and decimal items. A
            // quantity item declares its (possibly sole) unit through unitOption.
            let unitExtension = valueKind == .quantity
                ? "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption"
                : "http://hl7.org/fhir/StructureDefinition/questionnaire-unit"
            extensions.append(Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: unitExtension)),
                value: .coding(Coding(
                    code: unitCode.asFHIRStringPrimitive(),
                    display: unit.isEmpty ? nil : unit.asFHIRStringPrimitive(),
                    system: unitSystem?.asFHIRURIPrimitive()
                ))
            ))
        }
        for unitOption in unitOptions {
            if valueKind == .quantity,
               unitOption.code == unitCode,
               unitOption.system == unitSystem {
                continue
            }
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption",
                value: .coding(Coding(
                    code: unitOption.code.asFHIRStringPrimitive(),
                    display: unitOption.display.asFHIRStringPrimitive(),
                    system: unitOption.system?.asFHIRURIPrimitive()
                ))
            ))
        }
        return extensions
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig {
    /// The `answerOption` list, each option carrying its pre-selection, exclusivity and weight.
    fileprivate func answerOptions(
        preSelected: Set<Option.ID>,
        on taskId: GroveQuestionnaire.Questionnaire.Task.ID
    ) throws -> [QuestionnaireItemAnswerOption] {
        try options.map { option in
            var answerOption = QuestionnaireItemAnswerOption(value: try option.answerOptionValue(on: taskId))
            if preSelected.contains(option.id) {
                answerOption.initialSelected = FHIRPrimitive(FHIRBool(true))
            }
            var optionExtensions: [Extension] = []
            if option.isExclusive {
                optionExtensions.append(Extension(
                    url: "http://hl7.org/fhir/StructureDefinition/questionnaire-optionExclusive",
                    value: .boolean(FHIRPrimitive(FHIRBool(true)))
                ))
            }
            if let weight = option.weight, option.fhirCoding == nil {
                // A coded option carries its weight on the coding; a non-coding value has
                // nowhere to put it but the answerOption element.
                optionExtensions.append(Extension(
                    url: "http://hl7.org/fhir/StructureDefinition/itemWeight",
                    value: .decimal(FHIRPrimitive(FHIRDecimal(weight)))
                ))
            }
            answerOption.extension = optionExtensions.isEmpty ? nil : optionExtensions
            return answerOption
        }
    }

    /// How the options are laid out, and how many of them may be selected.
    fileprivate func presentationExtensions() -> [Extension] {
        var extensions: [Extension] = []
        if let label = freeTextOtherOptionLabel {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-openLabel",
                value: .string(label.asFHIRStringPrimitive())
            ))
        }
        if orientation == .horizontal {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-choiceOrientation",
                value: .code(FHIRPrimitive(ModelsR4.FHIRString("horizontal")))
            ))
        }
        switch presentation {
        case .dropDown, .autocomplete:
            let code = presentation == .dropDown ? "drop-down" : "autocomplete"
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                value: .codeableConcept(CodeableConcept(coding: [
                    Coding(
                    code: code.asFHIRStringPrimitive(),
                    system: "http://hl7.org/fhir/questionnaire-item-control".asFHIRURIPrimitive()
                )
                ]))
            ))
        case .list:
            break
        }
        if let minSelections {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-minOccurs",
                value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: minSelections))))
            ))
        }
        if let maxSelections {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs",
                value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: maxSelections))))
            ))
        }
        return extensions
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option {
    /// The `answerOption.value[x]` this option is written as, typed to match the value it was read from.
    fileprivate func answerOptionValue(on taskId: GroveQuestionnaire.Questionnaire.Task.ID) throws -> QuestionnaireItemAnswerOption.ValueX {
        guard fhirCoding == nil else {
            return .coding(toFHIRCoding())
        }
        switch answerValue {
        case .string(let string):
            return .string(string.asFHIRStringPrimitive())
        case .integer(let integer):
            guard let value = Int32(exactly: integer) else {
                throw FHIRExportError("Choice option '\(id)' on '\(taskId)' is out of range for a FHIR integer")
            }
            return .integer(FHIRPrimitive(FHIRInteger(value)))
        case .date(let components):
            guard let year = components.year else {
                throw FHIRExportError("Choice option '\(id)' on '\(taskId)' is missing a year")
            }
            return .date(FHIRPrimitive(FHIRDate(
                year: year,
                month: components.month.map { UInt8(clamping: $0) },
                day: components.day.map { UInt8(clamping: $0) }
            )))
        case .time(let components):
            return .time(FHIRPrimitive(FHIRTime(
                hour: UInt8(clamping: components.hour ?? 0),
                minute: UInt8(clamping: components.minute ?? 0),
                second: Decimal(components.second ?? 0)
            )))
        case nil:
            throw FHIRExportError("Choice option '\(id)' on '\(taskId)' has no coding; declare a system")
        }
    }
}
