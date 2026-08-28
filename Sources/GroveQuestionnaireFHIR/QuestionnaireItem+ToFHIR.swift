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
    /// Writes a group wrapper, carrying the title and condition once for all the tasks inside it.
    fileprivate init(
        _ group: GroveQuestionnaire.Questionnaire.Task.Group,
        using context: FHIRExportContext
    ) throws {
        self.init(linkId: group.id.asFHIRStringPrimitive(), type: FHIRPrimitive(QuestionnaireItemType.group))
        if !group.title.isEmpty {
            self.text = group.title.asFHIRStringPrimitive()
        }
        var extensions: [Extension] = []
        if let shortTitle = group.shortTitle {
            extensions.append(.shortText(shortTitle))
        }
        try applyCondition(group.condition, using: context, extensions: &extensions)
        self.extension = extensions.isEmpty ? nil : extensions
    }

    fileprivate init(
        _ task: GroveQuestionnaire.Questionnaire.Task,
        using context: FHIRExportContext
    ) throws {
        let type = try Self.itemType(for: task)
        self.init(linkId: task.id.asFHIRStringPrimitive(), type: FHIRPrimitive(type))
        // FHIR forbids `required` (que-6), `readOnly` (que-9), `initial` (que-8) and nested
        // items (que-1) on display items, so the renderer's own defaults must stop here.
        let isDisplay = type == .display

        var extensions: [Extension] = []
        applyCoreFields(of: task, isDisplay: isDisplay, extensions: &extensions)
        extensions += Self.presentationExtensions(of: task)
        extensions += Self.expressionExtensions(of: task)
        extensions += Self.constraintExtensions(of: task)
        // The footer authored via .help() exports as a nested help display item.
        if !task.footer.isEmpty && !isDisplay {
            self.item = [Self.helpItem(for: task)]
        }

        try applyKindDetails(of: task, using: context, extensions: &extensions)
        try applyCondition(task.enabledCondition, using: context, extensions: &extensions)
        // que-11: an item with answerOptions records its pre-selection as
        // `answerOption.initialSelected`, written alongside the options above.
        if !isDisplay,
           task.initialExpression == nil,
           answerOption?.isEmpty ?? true,
           let initial = try Self.initialEntry(for: task, using: context) {
            self.initial = [initial]
        }
        // Follow-up questions are asked once per selected option — which is what FHIR
        // means by items nested beneath a question, answered in the context of each answer.
        let followUps = try task.kind.followUpTasks.map { try QuestionnaireItem($0, using: context) }
        if !followUps.isEmpty && !isDisplay {
            self.item = (self.item ?? []) + followUps
        }
        self.extension = extensions.isEmpty ? nil : extensions
    }

    /// Builds a section's items, restoring the structure the conversion flattened:
    /// nested-group wrappers from each task's ``Questionnaire/Task/groupPath``, and
    /// child questions beneath their parent per ``Questionnaire/Task/parentTaskId``.
    ///
    /// The response emitter rebuilds the same shape, so questionnaire and response
    /// describe one tree.
    static func items(
        for section: GroveQuestionnaire.Questionnaire.Section,
        using context: FHIRExportContext
    ) throws -> [QuestionnaireItem] {
        var itemsByTaskId: [String: QuestionnaireItem] = [:]
        for task in section.tasks {
            itemsByTaskId[task.id] = try QuestionnaireItem(task, using: context)
        }
        // Deepest-first, so a grandchild is attached before its parent moves.
        for task in section.tasks.reversed() {
            guard let parentId = task.parentTaskId,
                  let child = itemsByTaskId.removeValue(forKey: task.id),
                  var parent = itemsByTaskId[parentId] else {
                continue
            }
            parent.item = (parent.item ?? []) + [child]
            itemsByTaskId[parentId] = parent
        }
        var result: [QuestionnaireItem] = []
        // The group wrappers currently open, outermost first.
        var openGroups: [(linkId: String, item: QuestionnaireItem)] = []
        func close(downTo depth: Int) {
            while openGroups.count > depth {
                let closed = openGroups.removeLast()
                if var parent = openGroups.popLast() {
                    parent.item.item = (parent.item.item ?? []) + [closed.item]
                    openGroups.append(parent)
                } else {
                    result.append(closed.item)
                }
            }
        }
        for task in section.tasks where task.parentTaskId == nil {
            guard let item = itemsByTaskId[task.id] else {
                continue
            }
            let path = task.groupPath
            var shared = 0
            while shared < Swift.min(openGroups.count, path.count), openGroups[shared].linkId == path[shared].id {
                shared += 1
            }
            close(downTo: shared)
            for group in path[shared...] {
                openGroups.append((group.id, try QuestionnaireItem(group, using: context)))
            }
            if var last = openGroups.popLast() {
                last.item.item = (last.item.item ?? []) + [item]
                openGroups.append(last)
            } else {
                result.append(item)
            }
        }
        close(downTo: 0)
        return result
    }

    private static func helpItem(for task: GroveQuestionnaire.Questionnaire.Task) -> QuestionnaireItem {
        var help = QuestionnaireItem(
            linkId: "\(task.id)-help".asFHIRStringPrimitive(),
            type: FHIRPrimitive(QuestionnaireItemType.display)
        )
        help.text = task.footer.asFHIRStringPrimitive()
        help.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
            value: .codeableConcept(CodeableConcept(coding: [
                Coding(
                code: "help".asFHIRStringPrimitive(),
                system: "http://hl7.org/fhir/questionnaire-item-control".asFHIRURIPrimitive()
            )
            ]))
        )
        ]
        return help
    }

    // MARK: Item Type

    private static func itemType(for task: GroveQuestionnaire.Questionnaire.Task) throws -> QuestionnaireItemType {
        switch task.kind.variant {
        case .instructional:
            return .display
        case .boolean:
            return .boolean
        case .freeText(let config):
            return itemType(forFreeText: config)
        case .dateTime(let config):
            return itemType(forDateTime: config)
        case .numeric(let config):
            return itemType(forNumeric: config)
        case .choice(let config):
            return config.hasFreeTextOtherOption ? .openChoice : .choice
        case .fileAttachment:
            return .attachment
        case .custom:
            throw ExportError("Custom question kind on '\(task.id)' has no FHIR export")
        }
    }

    /// `text` is FHIR's long-form answer; a short one is a `string`, and exporting every
    /// free-text question as `text` turned single-line questions multi-line on re-import.
    private static func itemType(
        forFreeText config: GroveQuestionnaire.Questionnaire.Task.Kind.FreeTextConfig
    ) -> QuestionnaireItemType {
        if config.expectsURL {
            .url
        } else {
            config.isMultiline ? .text : .string
        }
    }

    private static func itemType(
        forDateTime config: GroveQuestionnaire.Questionnaire.Task.Kind.DateTimeConfig
    ) -> QuestionnaireItemType {
        switch config.style {
        case .dateOnly: .date
        case .timeOnly: .time
        case .dateAndTime: .dateTime
        }
    }

    private static func itemType(
        forNumeric config: GroveQuestionnaire.Questionnaire.Task.Kind.NumericTaskConfig
    ) -> QuestionnaireItemType {
        switch config.valueKind {
        case .integer: .integer
        case .decimal: .decimal
        case .quantity: .quantity
        }
    }

    // MARK: Extensions

    private static func presentationExtensions(of task: GroveQuestionnaire.Questionnaire.Task) -> [Extension] {
        var extensions: [Extension] = []
        if task.isHidden {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden",
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            ))
        }
        if let media = task.media {
            var attachment = Attachment()
            attachment.data = FHIRPrimitive(Base64Binary(media.data.base64EncodedString()))
            attachment.contentType = FHIRPrimitive(ModelsR4.FHIRString(media.contentType))
            attachment.title = media.altText?.asFHIRStringPrimitive()
            extensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-itemMedia",
                value: .attachment(attachment)
            ))
        }
        return extensions
    }

    private static func expressionExtensions(of task: GroveQuestionnaire.Questionnaire.Task) -> [Extension] {
        var extensions = task.variables.map { variable in
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/variable",
                value: .expression(Expression(
                    expression: variable.expression.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath")),
                    name: variable.name.asFHIRStringPrimitive()
                ))
            )
        }
        if let initial = task.initialExpression {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression",
                value: .expression(Expression(
                    expression: initial.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
                ))
            ))
        }
        if let calculated = task.calculatedExpression {
            extensions.append(Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
                value: .expression(Expression(
                    expression: calculated.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
                ))
            ))
        }
        return extensions
    }

    private static func constraintExtensions(of task: GroveQuestionnaire.Questionnaire.Task) -> [Extension] {
        var extensions: [Extension] = []
        for (index, constraint) in task.constraints.enumerated() {
            var target = Extension(url: "http://hl7.org/fhir/StructureDefinition/targetConstraint")
            target.extension = [
                // `key` is 1..1 on the extension; unauthored rules take one from the item.
                Extension(url: "key", value: .id((constraint.key ?? Self.constraintKey(for: task.id, at: index)).asFHIRStringPrimitive())),
                Extension(url: "expression", value: .expression(Expression(
                    expression: constraint.expression.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
                ))),
                Extension(url: "human", value: .string(constraint.humanDescription.asFHIRStringPrimitive())),
                Extension(url: "severity", value: .code(FHIRPrimitive(ModelsR4.FHIRString(constraint.severity.rawValue))))
            ]
            extensions.append(target)
        }
        return extensions
    }

    /// A `targetConstraint` key derived from an item, in the `id` alphabet the extension requires.
    ///
    /// linkIds admit characters `id` forbids, so they are folded away; the index keeps the
    /// key unique and the derivation keeps it stable across exports.
    private static func constraintKey(for taskId: String, at index: Int) -> String {
        let suffix = "-\(index + 1)"
        let sanitized = taskId.map { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == ".") ? character : "-"
        }
        return String(String(sanitized).prefix(64 - suffix.count)) + suffix
    }

    // MARK: Initial Values

    private static func initialEntry(
        for task: GroveQuestionnaire.Questionnaire.Task,
        using context: FHIRExportContext
    ) throws -> QuestionnaireItemInitial? {
        guard let initialValue = task.initialValue else {
            return nil
        }
        switch initialValue {
        case .none:
            return nil
        case .bool(let bool):
            return QuestionnaireItemInitial(value: .boolean(FHIRPrimitive(FHIRBool(bool))))
        case .string(let string):
            return QuestionnaireItemInitial(value: .string(string.asFHIRStringPrimitive()))
        case .number(let number):
            return initialNumber(number, for: task)
        case let .quantity(number, unitCode):
            return QuestionnaireItemInitial(value: .quantity(
                context.quantity(number, unitCode: unitCode, forTaskWithId: task.id)
            ))
        case .date(let components):
            return try initialDate(components, on: task.id)
        case .choice(let choice):
            return try initialCoding(forOption: choice.selectedOptions.first, on: task.id)
        case .attachments, .custom:
            throw ExportError("Initial value on '\(task.id)' is not exportable")
        }
    }

    private static func initialNumber(
        _ number: Double,
        for task: GroveQuestionnaire.Questionnaire.Task
    ) -> QuestionnaireItemInitial {
        if case .numeric(let config) = task.kind.variant, config.valueKind == .integer {
            return QuestionnaireItemInitial(value: .integer(FHIRPrimitive(FHIRInteger(Int32(clamping: Int(number))))))
        }
        return QuestionnaireItemInitial(value: .decimal(number.asFHIRDecimalPrimitive()))
    }

    private static func initialDate(
        _ components: DateComponents,
        on taskId: GroveQuestionnaire.Questionnaire.Task.ID
    ) throws -> QuestionnaireItemInitial {
        guard let year = components.year else {
            throw ExportError("Initial date on '\(taskId)' is missing a year")
        }
        return QuestionnaireItemInitial(value: .date(FHIRPrimitive(FHIRDate(
            year: year,
            month: components.month.map { UInt8(clamping: $0) },
            day: components.day.map { UInt8(clamping: $0) }
        ))))
    }

    private static func initialCoding(
        forOption optionId: String?,
        on taskId: GroveQuestionnaire.Questionnaire.Task.ID
    ) throws -> QuestionnaireItemInitial {
        guard let optionId, let separator = optionId.firstIndex(of: "|") else {
            throw ExportError("Initial choice on '\(taskId)' must reference a coded option")
        }
        return QuestionnaireItemInitial(value: .coding(Coding(
            code: String(optionId[optionId.index(after: separator)...]).asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: String(optionId[..<separator])))
        )))
    }

    // MARK: Core Fields

    private mutating func applyCoreFields(
        of task: GroveQuestionnaire.Questionnaire.Task,
        isDisplay: Bool,
        extensions: inout [Extension]
    ) {
        switch task.kind.variant {
        case .instructional(let text):
            self.text = text.asFHIRStringPrimitive()
        default:
            if !task.title.isEmpty {
                self.text = task.title.asFHIRStringPrimitive()
            }
        }
        self.prefix = task.prefix?.asFHIRStringPrimitive()
        if !task.codes.isEmpty {
            self.code = task.codes.map { code in
                Coding(
                    code: code.code.asFHIRStringPrimitive(),
                    display: code.display?.asFHIRStringPrimitive(),
                    system: code.system?.asFHIRURIPrimitive()
                )
            }
        }
        self.definition = task.definition?.asFHIRURIPrimitive()
        if let shortTitle = task.shortTitle {
            extensions.append(.shortText(shortTitle))
        }
        if !task.isOptional && !isDisplay {
            self.required = FHIRPrimitive(FHIRBool(true))
        }
        if task.isReadOnly && !isDisplay {
            self.readOnly = FHIRPrimitive(FHIRBool(true))
        }
    }
}
