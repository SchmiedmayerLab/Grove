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
    private static func enableWhen(
        from condition: GroveQuestionnaire.Questionnaire.Condition,
        using context: FHIRExportContext
    ) throws -> QuestionnaireItemEnableWhen {
        switch condition {
        case .hasResponse(let taskId):
            return QuestionnaireItemEnableWhen(
                answer: .boolean(FHIRPrimitive(FHIRBool(true))),
                operator: FHIRPrimitive(QuestionnaireItemOperator.exists),
                question: taskId.asFHIRStringPrimitive()
            )
        case .not(.hasResponse(let taskId)):
            return QuestionnaireItemEnableWhen(
                answer: .boolean(FHIRPrimitive(FHIRBool(false))),
                operator: FHIRPrimitive(QuestionnaireItemOperator.exists),
                question: taskId.asFHIRStringPrimitive()
            )
        case let .responseValueComparison(taskId, comparison, value):
            return QuestionnaireItemEnableWhen(
                answer: try enableWhenAnswer(for: value, forTaskWithId: taskId, using: context),
                operator: FHIRPrimitive(enableWhenOperator(for: comparison)),
                question: taskId.asFHIRStringPrimitive()
            )
        default:
            throw FHIRExportError("Condition \(condition) is not representable as FHIR enableWhen; use enabledWhen with a FHIRPath expression instead")
        }
    }

    private static func enableWhenOperator(
        for comparison: GroveQuestionnaire.Questionnaire.Condition.ComparisonOperator
    ) -> QuestionnaireItemOperator {
        switch comparison {
        case .equal: .equal
        case .notEqual: .notEqual
        case .lessThan: .lessThan
        case .greaterThan: .greaterThan
        case .lessThanOrEqual: .lessThanOrEqual
        case .greaterThanOrEqual: .greaterThanOrEqual
        }
    }

    private static func enableWhenAnswer(
        for value: GroveQuestionnaire.Questionnaire.Condition.Value,
        forTaskWithId taskId: GroveQuestionnaire.Questionnaire.Task.ID,
        using context: FHIRExportContext
    ) throws -> QuestionnaireItemEnableWhen.AnswerX {
        switch value {
        case .bool(let bool):
            return .boolean(FHIRPrimitive(FHIRBool(bool)))
        case .integer(let integer):
            return .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: integer))))
        case .decimal(let decimal):
            return .decimal(decimal.asFHIRDecimalPrimitive())
        case .string(let string):
            return .string(string.asFHIRStringPrimitive())
        case let .quantity(quantity, unitCode):
            return .quantity(context.quantity(quantity, unitCode: unitCode, forTaskWithId: taskId))
        case .date(let components):
            return try enableWhenAnswer(forDate: components)
        case .SCMCOption(let optionId):
            return enableWhenAnswer(forOption: optionId)
        }
    }

    private static func enableWhenAnswer(forDate components: DateComponents) throws -> QuestionnaireItemEnableWhen.AnswerX {
        if components.year == nil {
            return .time(FHIRPrimitive(FHIRTime(
                hour: UInt8(clamping: components.hour ?? 0),
                minute: UInt8(clamping: components.minute ?? 0),
                second: Decimal(components.second ?? 0)
            )))
        }
        if components.hour != nil {
            throw FHIRExportError("dateTime enableWhen conditions are not exportable yet; compare on a date instead")
        }
        return .date(FHIRPrimitive(FHIRDate(
            year: components.year ?? 0,
            month: components.month.map { UInt8(clamping: $0) },
            day: components.day.map { UInt8(clamping: $0) }
        )))
    }

    /// Option tokens are `system|code` (or a bare code).
    private static func enableWhenAnswer(forOption optionId: String) -> QuestionnaireItemEnableWhen.AnswerX {
        guard let separator = optionId.firstIndex(of: "|") else {
            return .coding(Coding(code: optionId.asFHIRStringPrimitive()))
        }
        return .coding(Coding(
            code: String(optionId[optionId.index(after: separator)...]).asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: String(optionId[..<separator])))
        ))
    }

    /// Writes a condition as `enableWhen` comparisons, or as an SDC `enableWhenExpression`
    /// when it is authored as a FHIRPath expression.
    mutating func applyCondition(
        _ condition: GroveQuestionnaire.Questionnaire.Condition,
        using context: FHIRExportContext,
        extensions: inout [Extension]
    ) throws {
        var condition = condition.simplified()
        // Single-element conjunctions/disjunctions carry no combinator semantics.
        while true {
            if case .all(let set) = condition, set.count == 1, let inner = set.first {
                condition = inner
            } else if case .any(let set) = condition, set.count == 1, let inner = set.first {
                condition = inner
            } else {
                break
            }
        }
        switch condition {
        case true:
            return
        case .expression(let expression):
            extensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
                value: .expression(Expression(
                    expression: expression.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
                ))
            ))
        case .all(let conditions):
            self.enableWhen = try conditions.map { try Self.enableWhen(from: $0, using: context) }
            self.enableBehavior = FHIRPrimitive(EnableWhenBehavior.all)
        case .any(let conditions):
            self.enableWhen = try conditions.map { try Self.enableWhen(from: $0, using: context) }
            self.enableBehavior = FHIRPrimitive(EnableWhenBehavior.any)
        case let leaf:
            self.enableWhen = [try Self.enableWhen(from: leaf, using: context)]
        }
    }
}
