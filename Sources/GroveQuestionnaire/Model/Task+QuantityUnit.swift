//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


/// The unit of a FHIR `Quantity` as a response or an enableWhen condition records it: coding system, code and text.
@available(iOS 18, macOS 15, watchOS 11, *)
package struct RecordedQuantityUnit: Hashable, Sendable {
    package let system: URL?
    package let code: String?
    package let text: String?

    /// qty-3: a `Quantity` with a code also has a system, so a code without a system is recorded as text.
    package init(system: URL?, code: String?, text: String?) {
        self.system = system
        self.code = system == nil ? nil : code
        self.text = text ?? code
    }

    /// Whether an answer in this unit has an order relative to a threshold in `threshold`, as the pair rules decide.
    ///
    /// Units are not converted. A threshold with a code orders answers with the same code, and the same system
    /// where the threshold names one; a threshold with only unit text orders answers with the same text; a
    /// threshold without a unit orders only answers without a unit.
    package func orders(with threshold: Self) -> Bool {
        if let code = threshold.code {
            return self.code == code && (threshold.system == nil || system == threshold.system)
        }
        if let text = threshold.text {
            return self.text == text
        }
        return code == nil && text == nil
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task.Kind.NumericTaskConfig {
    /// The unit an answer is recorded in: the unit option with `chosenCode`, or the question's fixed unit.
    package func recordedUnit(ofAnswerIn chosenCode: String?) -> RecordedQuantityUnit {
        let fixedText = unit.base.isEmpty ? nil : unit.base
        guard let chosenCode else {
            return RecordedQuantityUnit(system: unitSystem, code: unitCode, text: fixedText ?? unitCode)
        }
        let option = unitOptions.first { $0.code == chosenCode }
        return RecordedQuantityUnit(
            system: option?.system ?? unitSystem,
            code: chosenCode,
            text: option?.display.base ?? fixedText ?? chosenCode
        )
    }

    /// The unit a condition value is recorded in; a code without a system takes the system the question gives it.
    package func recordedUnit(ofConditionWith system: URL?, code: String?, text: String?) -> RecordedQuantityUnit {
        let system = system ?? code.flatMap { code in unitOptions.first { $0.code == code }?.system ?? unitSystem }
        return RecordedQuantityUnit(system: system, code: code, text: text)
    }
}
