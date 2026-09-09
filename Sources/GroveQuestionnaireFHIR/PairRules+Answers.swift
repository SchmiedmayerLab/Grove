//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreFoundation
import Foundation

// The constraint matrix stays explicit so each R4 answer family fails closed at its own boundary.
// swiftlint:disable cyclomatic_complexity large_tuple

extension PairContext {
    // Every family in the IG's deterministic answer checker is handled in one pass.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func validateAnswerConstraints(
        definition: FHIRJSONObject,
        answers: [FHIRJSONObject],
        path: String
    ) {
        let expectedTypes = PairRules.answerTypes[
            definition["type"] as? String ?? ""
        ] ?? []
        var selectedOptions: [FHIRJSONObject] = []
        for (index, answer) in answers.enumerated() {
            let answerPath = "\(path).answer[\(index)]"
            guard let answerValue = PairRules.answerValue(answer),
                  expectedTypes.contains(answerValue.key) else {
                issues.append(.init(
                    code: .answerType,
                    path: answerPath,
                    message: "Answer type does not match Questionnaire item type."
                ))
                continue
            }
            let options = definition["answerOption"] as? [FHIRJSONObject] ?? []
            if !options.isEmpty,
               ["valueCoding", "valueString", "valueInteger", "valueDate", "valueTime"]
                .contains(answerValue.key) {
                let selected = PairRules.selectedInlineOption(
                    definition,
                    value: answerValue.value
                )
                let isOpenText = definition["type"] as? String == "open-choice"
                    && answerValue.key == "valueString"
                if selected == nil, !isOpenText {
                    issues.append(.init(
                        code: .answerOption,
                        path: answerPath,
                        message: "Answer is not one of the Questionnaire's inline answer options."
                    ))
                } else if let selected {
                    selectedOptions.append(selected)
                }
            }

            if let canonical = definition["answerValueSet"] as? String,
               answerValue.key == "valueCoding" {
                switch resolver.contains(canonical: canonical, coding: answerValue.value) {
                case .some(true):
                    break
                case .some(false):
                    issues.append(.init(
                        code: .answerValueSet,
                        path: answerPath,
                        message: "Coded answer is not in the referenced ValueSet."
                    ))
                case nil:
                    issues.append(.init(
                        code: .valueSetUnresolved,
                        path: answerPath,
                        message: "Cannot resolve and deterministically expand '\(canonical)'."
                    ))
                }
            }

            validateLength(definition: definition, answer: answerValue, path: answerPath)
            validateDecimalPlaces(definition: definition, answer: answerValue, path: answerPath)
            validateBounds(definition: definition, answer: answerValue, path: answerPath)
            validateUnit(definition: definition, answer: answerValue, path: answerPath)
            validateAttachment(definition: definition, answer: answerValue, path: answerPath)
        }

        let selectedExclusive = selectedOptions.contains { option in
            let extensions = PairRules.extensions(
                option,
                url: PairRules.URL.optionExclusive
            )
            return extensions.contains {
                guard let value = PairRules.extensionValue($0) else {
                    return false
                }
                return value.key == "valueBoolean"
                    && PairRules.boolean(value.value) == true
            }
        }
        if selectedExclusive, answers.count > 1 {
            issues.append(.init(
                code: .optionExclusive,
                path: path,
                message: "An exclusive option cannot be combined with another answer."
            ))
        }
        if definition["repeats"] as? Bool != true, answers.count > 1 {
            issues.append(.init(
                code: .repeats,
                path: path,
                message: "A non-repeating item cannot carry multiple answers."
            ))
        }
        let minimumExtension = PairRules.firstExtensionValue(
            definition,
            url: PairRules.URL.minOccurs
        )
        let minimum = minimumExtension.flatMap { PairRules.integer($0.value) }
        let maximumExtension = PairRules.firstExtensionValue(
            definition,
            url: PairRules.URL.maxOccurs
        )
        let maximum = maximumExtension.flatMap { PairRules.integer($0.value) }
        if let minimum, answers.count < minimum {
            issues.append(.init(
                code: .answerOccurrence,
                path: path,
                message: "Answer count is below questionnaire-minOccurs."
            ))
        }
        if let maximum, answers.count > maximum {
            issues.append(.init(
                code: .answerOccurrence,
                path: path,
                message: "Answer count exceeds questionnaire-maxOccurs."
            ))
        }
    }

    mutating func validateLength(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard ["valueString", "valueUri"].contains(answer.key),
              let value = answer.value as? String else {
            return
        }
        let length = value.unicodeScalars.count
        let minimumExtension = PairRules.firstExtensionValue(
            definition,
            url: PairRules.URL.minLength
        )
        let minimum = minimumExtension.flatMap { PairRules.integer($0.value) }
        let maximum = PairRules.integer(definition["maxLength"])
        if let minimum, length < minimum {
            issues.append(.init(
                code: .answerLength,
                path: path,
                message: "Answer is shorter than minLength."
            ))
        }
        if let maximum, length > maximum {
            issues.append(.init(
                code: .answerLength,
                path: path,
                message: "Answer exceeds maxLength."
            ))
        }
    }

    mutating func validateDecimalPlaces(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        let maximumExtension = PairRules.firstExtensionValue(
            definition,
            url: PairRules.URL.maxDecimalPlaces
        )
        guard answer.key == "valueDecimal",
              let maximum = maximumExtension.flatMap({ PairRules.integer($0.value) }),
              let actual = PairRules.decimalPlaces(answer.value),
              actual > maximum else {
            return
        }
        issues.append(.init(
            code: .answerDecimalPlaces,
            path: path,
            message: "Answer exceeds maxDecimalPlaces."
        ))
    }

    mutating func validateBounds(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        let bounds: [(url: String, minimum: Bool, code: ValidationIssue.Code)] = [
            (PairRules.URL.minValue, true, .answerValueBound),
            (PairRules.URL.maxValue, false, .answerValueBound),
            (PairRules.URL.minQuantity, true, .answerQuantityBound),
            (PairRules.URL.maxQuantity, false, .answerQuantityBound)
        ]
        for bound in bounds {
            guard let value = PairRules.firstExtensionValue(
                definition,
                url: bound.url
            )?.value else {
                continue
            }
            let valid = bound.minimum
                ? PairRules.lessThanOrEqual(value, answer.value)
                : PairRules.lessThanOrEqual(answer.value, value)
            if valid != true {
                issues.append(.init(
                    code: bound.code,
                    path: path,
                    message: "Answer violates a bound or uses an incomparable unit."
                ))
            }
        }
    }

    mutating func validateUnit(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard answer.key == "valueQuantity",
              let quantity = answer.value as? FHIRJSONObject else {
            return
        }
        let unitOptionExtensions = PairRules.extensions(
            definition,
            url: PairRules.URL.unitOption
        )
        let options = unitOptionExtensions
            .compactMap(PairRules.extensionValue)
            .map(\.value)
        if !options.isEmpty,
           !options.contains(where: { PairRules.valuesEqual(quantity, $0) }) {
            issues.append(.init(
                code: .answerUnit,
                path: path,
                message: "Quantity unit is not one of questionnaire-unitOption."
            ))
        }
        guard let canonical = PairRules.firstExtensionValue(
            definition,
            url: PairRules.URL.unitValueSet
        )?.value as? String else {
            return
        }
        let coding: FHIRJSONObject = ["system": quantity["system"] as Any, "code": quantity["code"] as Any]
        switch resolver.contains(canonical: canonical, coding: coding) {
        case .some(true):
            break
        case .some(false):
            issues.append(.init(
                code: .answerUnit,
                path: path,
                message: "Quantity unit is not certified by questionnaire-unitValueSet."
            ))
        case nil:
            issues.append(.init(
                code: .valueSetUnresolved,
                path: path,
                message: "Cannot resolve and deterministically expand unit ValueSet '\(canonical)'."
            ))
        }
    }

    mutating func validateAttachment(
        definition: FHIRJSONObject,
        answer: (key: String, value: Any),
        path: String
    ) {
        guard answer.key == "valueAttachment",
              let attachment = answer.value as? FHIRJSONObject else {
            return
        }
        let mimeTypeExtensions = PairRules.extensions(
            definition,
            url: PairRules.URL.mimeType
        )
        let allowedTypes = Set(
            mimeTypeExtensions
                .compactMap(PairRules.extensionValue)
                .compactMap { $0.value as? String }
        )
        let contentTypeAllowed = (attachment["contentType"] as? String).map(allowedTypes.contains) ?? false
        if !allowedTypes.isEmpty, !contentTypeAllowed {
            issues.append(.init(
                code: .answerAttachment,
                path: path,
                message: "Attachment contentType is not allowed."
            ))
        }
        let maximumExtension = PairRules.firstExtensionValue(
            definition,
            url: PairRules.URL.maxSize
        )
        guard let maximum = maximumExtension.flatMap({ PairRules.decimal($0.value) }) else {
            return
        }
        guard let size = PairRules.decimal(attachment["size"]),
              size <= maximum else {
            issues.append(.init(
                code: .answerAttachment,
                path: path,
                message: "Attachment exceeds maxSize or does not declare size."
            ))
            return
        }
    }
}
