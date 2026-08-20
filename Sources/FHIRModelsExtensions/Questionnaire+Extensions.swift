//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import FHIRPathParser
public import Foundation
public import ModelsR4


extension FHIRTypeWithExtensions {
    /// The element's scoring weight from the current `itemWeight` extension.
    public var itemWeight: Decimal? {
        if case let .decimal(value) = extensions(
            for: "http://hl7.org/fhir/StructureDefinition/itemWeight"
        ).first?.value {
            value.value?.decimal
        } else {
            nil
        }
    }

    /// The `questionnaire-optionExclusive` flag on an answer option.
    public var isExclusiveOption: Bool {
        if case let .boolean(value) = extensions(
            for: "http://hl7.org/fhir/StructureDefinition/questionnaire-optionExclusive"
        ).first?.value {
            value.value?.bool ?? false
        } else {
            false
        }
    }
}


extension FHIRPrimitive where PrimitiveType == FHIRString {
    /// The string's best value for a locale, honoring `translation` extensions
    /// carried on the primitive (the FHIR mechanism for multi-language resources).
    public func localizedString(for locale: Locale = .autoupdatingCurrent) -> String? {
        let translations = `extension`?.filter {
            $0.url.value?.url.absoluteString == "http://hl7.org/fhir/StructureDefinition/translation"
        } ?? []
        // Not `locale.language.languageCode`: that needs iOS 16 / macOS 13, above the lowered
        // deployment floor the package still builds against.
        let language = locale.identifier.split { $0 == "-" || $0 == "_" }.first?.lowercased()
        if !translations.isEmpty, let language {
            for translation in translations {
                guard case let .code(langCode)? = translation.extension?.first(where: { $0.url.value?.url.absoluteString == "lang" })?.value,
                      let lang = langCode.value?.string.lowercased(),
                      lang == language || lang.hasPrefix("\(language)-") else {
                    continue
                }
                let content = translation.extension?.first { $0.url.value?.url.absoluteString == "content" }?.value
                switch content {
                case .string(let value):
                    if let string = value.value?.string {
                        return string
                    }
                case .markdown(let value):
                    if let string = value.value?.string {
                        return string
                    }
                default:
                    break
                }
            }
        }
        return value?.string
    }
}


extension QuestionnaireItem {
    /// Supported FHIR extensions for QuestionnaireItems
    private enum SupportedExtensions {
        static let itemControl = "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl"
        static let questionnaireUnit = "http://hl7.org/fhir/StructureDefinition/questionnaire-unit"
        static let regex = "http://hl7.org/fhir/StructureDefinition/regex"
        static let sliderStepValue = "http://hl7.org/fhir/StructureDefinition/questionnaire-sliderStepValue"
        static let maxDecimalPlaces = "http://hl7.org/fhir/StructureDefinition/maxDecimalPlaces"
        static let minValue = "http://hl7.org/fhir/StructureDefinition/minValue"
        static let maxValue = "http://hl7.org/fhir/StructureDefinition/maxValue"
        static let hidden = "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden"
        static let entryFormat = "http://hl7.org/fhir/StructureDefinition/entryFormat"
    }

    /// Is the question hidden
    /// - Returns: A boolean representing whether the question should be shown to the user
    public var hidden: Bool {
        guard let hiddenExtension = getExtensionInQuestionnaireItem(url: SupportedExtensions.hidden),
              case let .boolean(booleanValue) = hiddenExtension.value,
              let isHidden = booleanValue.value?.bool as? Bool else {
            return false
        }
        return isHidden
    }

    /// Defines the control type for the answer for a question
    /// - Returns: A code representing the control type (i.e. slider)
    public var itemControl: String? {
        guard let itemControlExtension = getExtensionInQuestionnaireItem(url: SupportedExtensions.itemControl),
              case let .codeableConcept(concept) = itemControlExtension.value,
              let itemControlCode = concept.coding?.first?.code?.value?.string else {
            return nil
        }
        return itemControlCode
    }
    
    /// The minimum value for a numerical answer.
    ///
    /// Reads the core `minValue` extension, falling back to SDC's unit-aware
    /// `minQuantity` (whose unit is assumed to match the question's).
    /// - Returns: An optional `NSNumber` containing the minimum value allowed.
    public var minValue: NSNumber? {
        numericMinMaxValue(url: SupportedExtensions.minValue)
            ?? numericMinMaxValue(url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-minQuantity")
    }

    /// The maximum value for a numerical answer.
    ///
    /// Reads the core `maxValue` extension, falling back to SDC's unit-aware
    /// `maxQuantity` (whose unit is assumed to match the question's).
    /// - Returns: An optional `NSNumber` containing the maximum value allowed.
    public var maxValue: NSNumber? {
        numericMinMaxValue(url: SupportedExtensions.maxValue)
            ?? numericMinMaxValue(url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity")
    }
    
    /// The maximum number of decimal places for a decimal answer.
    /// - Returns: An optional `NSNumber` representing the maximum number of digits to the right of the decimal place.
    public var maximumDecimalPlaces: NSNumber? {
        guard let maxDecimalPlacesExtension = getExtensionInQuestionnaireItem(url: SupportedExtensions.maxDecimalPlaces),
              case let .integer(integerValue) = maxDecimalPlacesExtension.value,
              let maxDecimalPlaces = integerValue.value?.integer as? Int32 else {
            return nil
        }
        return NSNumber(value: maxDecimalPlaces)
    }

    /// The offset between numbers on a numerical slider
    /// - Returns: An optional `NSNumber` representing the size of each discrete offset on the scale.
    public var sliderStepValue: NSNumber? {
        guard let sliderStepValueExtension = getExtensionInQuestionnaireItem(url: SupportedExtensions.sliderStepValue),
              case let .integer(integerValue) = sliderStepValueExtension.value,
              let sliderStepValue = integerValue.value?.integer as? Int32 else {
            return nil
        }
        return NSNumber(value: sliderStepValue)
    }
    
    /// The unit of a quantity answer type.
    /// - Returns: An optional `String` containing the unit (i.e. cm) if it was provided.
    public var unit: String? {
        unitCoding?.code?.value?.string
    }

    /// The full `questionnaire-unit` coding of a quantity answer type, preserving
    /// system and display alongside the code so answers can carry the coded unit.
    public var unitCoding: Coding? {
        guard let unitExtension = getExtensionInQuestionnaireItem(url: SupportedExtensions.questionnaireUnit),
              case let .coding(coding) = unitExtension.value else {
            return nil
        }
        return coding
    }
    
    /// The regular expression specified for validating a text input in a question.
    /// - Returns: An optional `String` containing the regular expression, if it exists.
    public var validationRegularExpression: NSRegularExpression? {
        if let pattern = extensions(for: SupportedExtensions.regex).first?.value?.stringValue?.value?.string {
            try? NSRegularExpression(pattern: pattern)
        } else {
            nil
        }
    }
    
    /// The authored human guidance on the first current `targetConstraint`.
    public var validationMessage: String? {
        extensions(for: "http://hl7.org/fhir/StructureDefinition/targetConstraint")
            .first?
            .extension?
            .first { $0.url.value?.url.absoluteString == "human" }?
            .value?
            .stringValue?
            .value?
            .string
    }

    /// The placeholder text associated with the questionaire item.
    public var placeholderText: String? {
        extensions(for: SupportedExtensions.entryFormat).first?.value?.stringValue?.value?.string
    }

    /// The code from the current SDC keyboard extension.
    public var keyboardTypeRawValue: String? {
        guard case .coding(let coding)? = extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-keyboard"
        ).first?.value else {
            return nil
        }
        return coding.code?.value?.string
    }

    /// No Grove 0.2 extension assigns UIKit-specific autocapitalization behavior.
    public var autocapitalizeRawValue: String? { nil }

    /// No Grove 0.2 extension assigns UIKit-specific text-content behavior.
    public var autocompleteRawValue: String? { nil }

    /// The minimum value for a date answer, resolving relative FHIRPath values at
    /// the caller-supplied instant.
    /// - Parameter evaluationInstant: The explicit instant used by clock-sensitive expressions.
    /// - Returns: An optional `DateComponents` containing the minimum date allowed.
    public func minDateValue(evaluationInstant: Date) -> DateComponents? {
        dateMinMaxValue(urls: [SupportedExtensions.minValue], evaluationInstant: evaluationInstant)
    }

    /// The maximum value for a date answer, resolving relative FHIRPath values at
    /// the caller-supplied instant.
    /// - Parameter evaluationInstant: The explicit instant used by clock-sensitive expressions.
    /// - Returns: An optional `DateComponents` containing the maximum date allowed.
    public func maxDateValue(evaluationInstant: Date) -> DateComponents? {
        dateMinMaxValue(urls: [SupportedExtensions.maxValue], evaluationInstant: evaluationInstant)
    }
    
    /// Checks this QuestionnaireItem for an extension matching the given URL and then return it if it exists.
    /// - Parameters:
    ///   - url: A `String` identifying the extension.
    /// - Returns: an optional Extension if it was found.
    private func getExtensionInQuestionnaireItem(url: String) -> Extension? {
        self.`extension`?.first(where: { $0.url.value?.url.absoluteString == url })
    }
    
    private func numericMinMaxValue(url: String) -> NSNumber? {
        switch getExtensionInQuestionnaireItem(url: url)?.value {
        case .integer(let integer):
            (integer.value?.integer).map { NSNumber(value: $0) }
        case .decimal(let decimal):
            (decimal.value?.decimal).map { NSDecimalNumber(decimal: $0) }
        case .quantity(let quantity):
            // Note: this operates on the assumption that the unit used by the min/maxValue quantity is using the same unit as the question itself.
            (quantity.value?.value?.decimal).map { NSDecimalNumber(decimal: $0) }
        default:
            nil
        }
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    private func dateMinMaxValue(
        urls: [String],
        evaluationInstant: Date
    ) -> DateComponents? {
        for url in urls {
            guard let ext = getExtensionInQuestionnaireItem(url: url) else {
                continue
            }
            switch ext.value {
            case .date(let value):
                guard let value = value.value else {
                    continue
                }
                return value.dateComponents()
            case .time(let value):
                guard let value = value.value else {
                    continue
                }
                return value.dateComponents()
            case .dateTime(let value):
                guard let value = value.value else {
                    continue
                }
                return value.dateComponents()
            case .string(let value):
                guard let value = value.value?.string else {
                    continue
                }
                if let value = try? FHIRPathExpression.evaluate(
                    expression: value,
                    evaluationInstant: evaluationInstant,
                    as: DateComponents.self
                ) {
                    return value
                } else {
                    continue
                }
            default:
                continue
            }
        }
        return nil
    }
}
