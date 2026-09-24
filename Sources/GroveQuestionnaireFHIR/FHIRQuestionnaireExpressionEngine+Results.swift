//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRPathParser
import Foundation
import GroveQuestionnaire


// MARK: Result Mapping

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRQuestionnaireExpressionEngine {
    /// Maps an evaluation result onto the response value shape of the task's kind.
    static func responseValue(
        from result: [FHIRPathValue],
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> QuestionnaireResponses.Response.Value? {
        guard let first = result.first else {
            return QuestionnaireResponses.Response.Value.none
        }
        let value: QuestionnaireResponses.Response.Value? = switch task.kind.variant {
        case .boolean:
            boolValue(from: first)
        case .numeric:
            numberValue(from: first)
        case .freeText:
            stringValue(from: first)
        case .dateTime:
            dateValue(from: first)
        case .choice(let config):
            try choiceValue(from: result, options: config.options)
        case .instructional, .fileAttachment, .custom:
            nil
        }
        guard let value else {
            throw FHIRPathEvaluationError.typeMismatch("Cannot express \(first) as a response for task '\(task.id)'")
        }
        return value
    }

    private static func boolValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        guard case .boolean(let value) = value else {
            return nil
        }
        return .bool(value)
    }

    private static func numberValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        switch value {
        case .integer(let value):
            return .number(Double(value))
        case .decimal(let value), .quantity(let value, _):
            return .number(value.doubleValue)
        default:
            return nil
        }
    }

    private static func stringValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        switch value {
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .string(String(value))
        case .decimal(let value):
            return .string("\(value)")
        default:
            return nil
        }
    }

    private static func dateValue(from value: FHIRPathValue) -> QuestionnaireResponses.Response.Value? {
        switch value {
        case .date(let components), .dateTime(let components), .time(let components):
            return .date(components)
        case .string(let string):
            switch FHIRPathValue.parseTemporal(string) {
            case .date(let components), .dateTime(let components):
                return .date(components)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// Codings (or code strings) select the options they match.
    private static func choiceValue(
        from result: [FHIRPathValue],
        options: [GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option]
    ) throws -> QuestionnaireResponses.Response.Value? {
        var selected: Set<String> = []
        for value in result {
            switch value {
            case .object(let node):
                guard let code = node.stringMember("code") else {
                    continue
                }
                let system = node.stringMember("system").flatMap(URL.init(string:))
                if node.stringMember("system") != nil, system == nil {
                    throw FHIRPathEvaluationError.typeMismatch("Coding.system is not an absolute URI")
                }
                if let match = try ChoiceOptionResolver.coding(system: system, code: code, in: options) {
                    selected.insert(match.id)
                }
            case .string(let string):
                if let match = try ChoiceOptionResolver.token(string, in: options) {
                    selected.insert(match.id)
                }
            default:
                continue
            }
        }
        guard !selected.isEmpty else {
            return nil
        }
        return .choice(.init(selectedOptions: selected))
    }
}
