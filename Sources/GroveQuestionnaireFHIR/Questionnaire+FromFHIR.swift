//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order file_length

private import Algorithms
private import FHIRModelsExtensions
private import FHIRPathParser
public import Foundation
private import GroveFoundation
public import GroveQuestionnaire
public import ModelsR4
private import struct SwiftUI.Color
private import UniformTypeIdentifiers


@available(iOS 18, macOS 15, watchOS 11, *)
private typealias FHIRConversionError = GroveQuestionnaire.Questionnaire.FHIRConversionError


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire {
    /// Controls conversion behaviour when creating a Grove `Questionnaire` from a FHIR R4 `Questionnaire`
    public struct FHIRConversionOptions: Sendable {
        /// All known question kinds, with the builtin ones at the end of the list.
        fileprivate let knownQuestionKinds: [any QuestionKindDefinition.Type]
        /// Whether conversion refuses questionnaires that must not be administered:
        /// `retired` ones, and ones outside their `effectivePeriod`. Disable only for
        /// tooling that inspects rather than administers.
        fileprivate let enforcesPublicationLifecycle: Bool
        /// The locale used to resolve `translation` extensions on user-visible text.
        fileprivate let locale: Locale
        /// App-supplied resources for SDC `launchContext` (e.g. the study participant's
        /// `Patient`), keyed by the context name expressions reference (`%patient`).
        fileprivate let launchContext: [String: ResourceProxy]
        /// Resolves external `answerValueSet` canonicals to ValueSets the app ships
        /// (ideally pre-expanded); `nil` values fail the conversion loudly.
        fileprivate let resolveValueSet: (@Sendable (URL) -> ModelsR4.ValueSet?)?

        public init(
            extraQuestionKinds: [any QuestionKindDefinition.Type] = [],
            enforcesPublicationLifecycle: Bool = true,
            locale: Locale = .autoupdatingCurrent,
            launchContext: [String: ResourceProxy] = [:],
            resolveValueSet: (@Sendable (URL) -> ModelsR4.ValueSet?)? = nil
        ) {
            self.knownQuestionKinds = extraQuestionKinds + GroveQuestionnaire.Questionnaire.builtinQuestionKinds
            self.enforcesPublicationLifecycle = enforcesPublicationLifecycle
            self.locale = locale
            self.launchContext = launchContext
            self.resolveValueSet = resolveValueSet
        }
    }
    
    /// An error that occured when creating a Grove `Questionnaire` from a FHIR R4 `Questionnaire`
    public enum FHIRConversionError: LocalizedError {
        /// The input FHIR questionnaire didn't contain any questions.
        case emptyQuestionnaire
        /// The input FHIR questionnaire contained a nonstandard question kind for which there was no matching `QuestionKindDefinition`.
        case unhandledNonstandardQuestionKind(taskLinkId: String)
        /// Some unspecified problem was encountered.
        case other(String)
        
        public var errorDescription: String? {
            switch self {
            case .emptyQuestionnaire:
                "Empty Questionnaire"
            case .unhandledNonstandardQuestionKind(let taskLinkId):
                """
                Unable to parse questionnaire item for task '\(taskLinkId)'.
                No matching task definition.
                """
            case .other(let message):
                message
            }
        }
    }
    
    /// Creates a Grove `Questionnaire` from a FHIR R4 `Questionnaire`.
    ///
    /// - parameter other: A FHIR R4 Questionnaire
    /// - parameter evaluationInstant: The instant used for publication-lifecycle warnings and
    ///   every clock-sensitive FHIRPath expression. Defaults to the wall clock; pass a fixed
    ///   instant to make a conversion reproducible.
    /// - parameter options: Additional options to control the conversion process. Use this to specify e.g. custom question kinds.
    public init(
        _ other: ModelsR4.Questionnaire,
        evaluationInstant: Date = .now,
        using options: FHIRConversionOptions = .init()
    ) throws(FHIRConversionError) {
        let metadata = try Self.metadata(of: other, evaluationInstant: evaluationInstant, using: options)
        // R4: a resource with unprocessed modifier extensions must not be processed as if
        // their meaning were understood; none are supported, so conversion refuses them.
        if let modifier = other.modifierExtension?.first {
            throw .other("Unsupported modifierExtension '\(modifier.url.value?.url.absoluteString ?? "?")' on the questionnaire.")
        }
        let (usesExpressions, variables) = try Self.expressionUsage(of: other)
        var engine: FHIRQuestionnaireExpressionEngine?
        if usesExpressions || !variables.isEmpty || !options.launchContext.isEmpty {
            do {
                engine = try FHIRQuestionnaireExpressionEngine(
                    questionnaire: other,
                    variables: variables,
                    launchContext: try options.launchContext.mapValues { try FHIRPathNode.encoding($0) },
                    evaluationInstant: evaluationInstant
                )
            } catch {
                throw .other("Failed to set up the expression engine: \(error)")
            }
        }
        let sections = try other.toSections(
            using: options,
            engine: engine,
            evaluationInstant: evaluationInstant
        )
        do {
            self = try .validated(metadata: metadata, sections: sections)
        } catch {
            throw .other("\(error)")
        }
        self.expressionEngine = engine
    }

    private static func metadata(
        of other: ModelsR4.Questionnaire,
        evaluationInstant: Date,
        using options: FHIRConversionOptions
    ) throws(FHIRConversionError) -> Metadata {
        guard let id = other.url?.value?.url.absoluteString ?? other.id?.value?.string else {
            throw .other("Missing both 'url' and 'id' fields. At least one must be present.")
        }
        let lifecycle: PublicationLifecycle = switch other.status.value {
        case .draft: .draft
        case .active, nil: .active
        case .retired: .retired
        case .unknown: .unknown
        }
        if options.enforcesPublicationLifecycle && lifecycle == .retired {
            // Administering a retired instrument is a study-conduct error.
            throw .other("Questionnaire '\(id)' is retired and must not be administered.")
        }
        return Metadata(
            id: id,
            url: other.url?.value?.url,
            version: other.version?.value?.string,
            title: other.title?.localizedString(for: options.locale) ?? "",
            explainer: other.description_fhir?.localizedString(for: options.locale) ?? "",
            lifecycle: lifecycle,
            publisher: other.publisher?.value?.string,
            copyright: other.copyright?.value?.string,
            administrationWarnings: administrationWarnings(
                of: other,
                lifecycle: lifecycle,
                evaluationInstant: evaluationInstant
            ),
            entryMode: entryMode(of: other),
            variables: try other.sdcVariables()
        )
    }

    /// Conditions that don't prevent administering the questionnaire, but that the app should surface.
    private static func administrationWarnings(
        of other: ModelsR4.Questionnaire,
        lifecycle: PublicationLifecycle,
        evaluationInstant: Date
    ) -> [String] {
        var warnings: [String] = []
        if lifecycle == .draft {
            warnings.append("The questionnaire is a draft.")
        }
        // Out-of-period instruments are common in published examples and archival
        // content, so they convert but carry a warning the app can act on.
        if let start = try? other.effectivePeriod?.start?.value?.asNSDate() as? Date, evaluationInstant < start {
            warnings.append("The questionnaire is not yet effective (effectivePeriod starts \(start)).")
        }
        if let end = try? other.effectivePeriod?.end?.value?.asNSDate() as? Date, evaluationInstant > end {
            warnings.append("The questionnaire is past its effectivePeriod (ended \(end)).")
        }
        // rendering-styleSensitive: the spec says a renderer that ignores styling
        // should not render such questionnaires; surface it instead of silence.
        if case .boolean(let styleSensitive)? = other.extensions(
            for: "http://hl7.org/fhir/StructureDefinition/rendering-styleSensitive"
        ).first?.value, styleSensitive.value?.bool == true {
            warnings.append("The questionnaire declares itself style-sensitive; this renderer does not apply rendering-style/xhtml.")
        }
        return warnings
    }

    private static func entryMode(of other: ModelsR4.Questionnaire) -> EntryMode {
        guard case .code(let code)? = other.extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-entryMode"
        ).first?.value, let mode = (code.value?.string).flatMap({ EntryMode(rawValue: $0) }) else {
            return .random
        }
        return mode
    }

    /// Walks the FHIR item tree, rejecting content that must not be administered, and reports
    /// whether the questionnaire uses expressions and which `variable`s it declares.
    ///
    /// Duplicate linkIds are invalid FHIR (que-2) but author-suppliable; walking the tree covers
    /// group linkIds too, and surfaces a conversion error rather than tripping the native model's
    /// programmer-error check.
    private static func expressionUsage(
        of other: ModelsR4.Questionnaire
    ) throws(FHIRConversionError) -> (usesExpressions: Bool, variables: [FHIRQuestionnaireExpressionEngine.Variable]) {
        var seenIds: Set<String> = []
        var usesExpressions = false
        var variables: [FHIRQuestionnaireExpressionEngine.Variable] = []
        // A `variable` is visible to the declaring element and its descendants, so an
        // item-level declaration carries the linkIds it covers.
        func collectVariables(
            of element: some FHIRTypeWithExtensions,
            scope: FHIRQuestionnaireExpressionEngine.Variable.Scope
        ) throws(FHIRConversionError) {
            for variable in try element.sdcVariables() {
                variables.append(.init(name: variable.name, expression: variable.expression, scope: scope))
            }
        }
        func check(_ items: [ModelsR4.QuestionnaireItem]) throws(FHIRConversionError) {
            for item in items {
                if let modifier = item.modifierExtension?.first {
                    let url = modifier.url.value?.url.absoluteString ?? "?"
                    throw .other("Unsupported modifierExtension '\(url)' on item '\(item.linkId.value?.string ?? "?")'.")
                }
                if let linkId = item.linkId.value?.string, !seenIds.insert(linkId).inserted {
                    throw .other("Duplicate linkId '\(linkId)' in questionnaire.")
                }
                try collectVariables(of: item, scope: .items(item.linkIdsIncludingDescendants()))
                if SDCExpressionURLs.all.contains(where: { !item.extensions(for: $0).isEmpty }) {
                    usesExpressions = true
                }
                try check(item.item ?? [])
            }
        }
        try collectVariables(of: other, scope: .global)
        try check(other.item ?? [])
        return (usesExpressions, variables)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private struct ConversionContext {
    let options: GroveQuestionnaire.Questionnaire.FHIRConversionOptions
    /// The caller-supplied instant used to resolve relative date bounds.
    let evaluationInstant: Date
    /// The FHIR questionnaire being converted
    let questionnaire: ModelsR4.Questionnaire
    /// The "is enabled" condition of the parent item.
    let parentItemCondition: GroveQuestionnaire.Questionnaire.Condition
    /// The expression engine, when the questionnaire uses SDC expression features.
    var engine: FHIRQuestionnaireExpressionEngine?
    /// The (non-top-level) FHIR groups enclosing the current items, outermost first.
    var groupPath: [GroveQuestionnaire.Questionnaire.Task.Group] = []
    /// The linkId of the question item the current items are nested under, if any.
    var parentTaskId: String?
}


/// The SDC/core extension URLs that require the expression engine.
private enum SDCExpressionURLs {
    static let enableWhen = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression"
    static let calculated = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression"
    static let initial = "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression"
    static let targetConstraint = "http://hl7.org/fhir/StructureDefinition/targetConstraint"

    static let all: [FHIRPrimitive<FHIRURI>] = [
        FHIRPrimitive(FHIRURI(stringLiteral: enableWhen)),
        FHIRPrimitive(FHIRURI(stringLiteral: calculated)),
        FHIRPrimitive(FHIRURI(stringLiteral: initial)),
        FHIRPrimitive(FHIRURI(stringLiteral: targetConstraint))
    ]
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.Questionnaire {
    fileprivate func toSections(
        using options: GroveQuestionnaire.Questionnaire.FHIRConversionOptions,
        engine: FHIRQuestionnaireExpressionEngine? = nil,
        evaluationInstant: Date
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.Section] {
        guard let items = item, !items.isEmpty else {
            throw .emptyQuestionnaire
        }
        return try topLevelGroups(of: items).map { item, isSynthesized throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) in
            let linkId = try item.getLinkId()
            guard item.type.value == .group else {
                throw .other("Top-level item '\(linkId)' is not a group")
            }
            let context = ConversionContext(
                options: options,
                evaluationInstant: evaluationInstant,
                questionnaire: self,
                parentItemCondition: .none,
                engine: engine
            )
            return try item.toSection(using: context, isSynthesized: isSynthesized)
        }
    }

    /// The top-level items, with each run of non-`group` items wrapped into a synthesized group,
    /// so that every section is backed by a group item.
    private func topLevelGroups(
        of items: [ModelsR4.QuestionnaireItem]
    ) throws(FHIRConversionError) -> [(item: ModelsR4.QuestionnaireItem, isSynthesized: Bool)] {
        var topLevelItems: [(item: ModelsR4.QuestionnaireItem, isSynthesized: Bool)] = []
        var itemsIterator = items.makeIterator()
        var nextGroupIdx = 0
        while let item = itemsIterator.next() {
            guard let itemType = item.type.value else {
                throw .other("QuestionnaireItem is missing 'type'")
            }
            if itemType == .group {
                topLevelItems.append((item, false))
                continue
            }
            var groupedItems = [item]
            var nextGroup: ModelsR4.QuestionnaireItem?
            while let nextItem = itemsIterator.next() {
                // gobble up all following non-group items, until we reach the next group
                guard let nextItemType = nextItem.type.value else {
                    throw .other("QuestionnaireItem is missing 'type'")
                }
                guard nextItemType != .group else {
                    nextGroup = nextItem
                    break
                }
                groupedItems.append(nextItem)
            }
            let group = ModelsR4.QuestionnaireItem(
                item: groupedItems,
                linkId: "___\(nextGroupIdx)".asFHIRStringPrimitive(),
                type: .init(.group)
            )
            topLevelItems.append((group, true))
            nextGroupIdx += 1
            if let nextGroup {
                topLevelItems.append((nextGroup, false))
            }
        }
        return topLevelItems
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.QuestionnaireItem {
    /// - invariant: the item must be a top-level `group` item.
    fileprivate func toSection(
        using context: ConversionContext,
        isSynthesized: Bool
    ) throws(FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Section {
        guard type.value == .group else {
            throw .other("Not a group item!")
        }
        let linkId = try getLinkId()
        guard let nestedItems = item, !nestedItems.isEmpty else {
            // do we want to allow this? be a little more lenient here?
            throw .other("Empty top-level group!")
        }
        let groupCondition = try GroveQuestionnaire.Questionnaire.Condition(self, using: context)
        let itemContext = ConversionContext(
            options: context.options,
            evaluationInstant: context.evaluationInstant,
            questionnaire: context.questionnaire,
            parentItemCondition: groupCondition,
            engine: context.engine
        )
        return .init(
            id: linkId,
            title: isSynthesized ? "" : self.text?.localizedString(for: context.options.locale) ?? "",
            shortTitle: isSynthesized ? nil : shortText(for: context.options.locale),
            tasks: try nestedItems.flatMap2 { item throws(FHIRConversionError) in
                try item.toTasks(using: itemContext)
            },
            fhirGroupId: isSynthesized ? nil : linkId
        )
    }
    
    /// Converts a FHIR QuestionnaireItem into a Task (within a Section) within a Grove Questionnaire.
    ///
    /// - invariant: If this `QuestionnaireItem` is a `group`, is must not be a top-level item (in that case, ``toSection(using:)`` must be used instead).
    fileprivate func toTasks(
        using context: ConversionContext
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.Task] {
        guard let itemType = type.value else {
            throw .other("QuestionnaireItem is missing 'type'")
        }
        switch itemType {
        case .group:
            guard let nestedItems = self.item, !nestedItems.isEmpty else {
                return []
            }
            // Non-top-level groups are flattened into a series of tasks for display purposes;
            // the group itself is recorded on each task's groupPath, carrying the title and
            // condition that let the export and the response emitter restore the hierarchy.
            let group = GroveQuestionnaire.Questionnaire.Task.Group(
                id: try getLinkId(),
                title: self.text?.localizedString(for: context.options.locale) ?? "",
                shortTitle: shortText(for: context.options.locale),
                condition: try .init(self, using: context)
            )
            let itemContext = ConversionContext(
                options: context.options,
                evaluationInstant: context.evaluationInstant,
                questionnaire: context.questionnaire,
                parentItemCondition: context.parentItemCondition,
                engine: context.engine,
                groupPath: context.groupPath + [group],
                parentTaskId: context.parentTaskId
            )
            return try nestedItems.flatMap2 { item throws(FHIRConversionError) in
                try item.toTasks(using: itemContext)
            }
        // swiftlint:disable:next line_length
        case .display, .boolean, .decimal, .integer, .date, .dateTime, .time, .string, .text, .url, .choice, .openChoice, .attachment, .reference, .quantity, .question:
            return try toQuestionTasks(ofType: itemType, using: context)
        }
    }

    /// The task for a non-group item, followed by the tasks of the items nested beneath it.
    private func toQuestionTasks(
        ofType itemType: ModelsR4.QuestionnaireItemType,
        using context: ConversionContext
    ) throws(FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.Task] {
        let kind = try toTaskKind(using: context)
        let condition = try enabledCondition(using: context)
        let media = try itemMedia(for: kind)
        var task = GroveQuestionnaire.Questionnaire.Task(
            id: try self.getLinkId(),
            title: itemType == .display ? "" : self.text?.localizedString(for: context.options.locale) ?? "",
            prefix: self.prefix?.localizedString(for: context.options.locale),
            shortTitle: shortText(for: context.options.locale),
            footer: supportLinkFooter(),
            media: media,
            kind: kind,
            isOptional: !(self.required?.value?.bool ?? false), // FHIR defines the default of `required` as false.
            enabledCondition: condition,
            isReadOnly: self.readOnly?.value?.bool ?? false,
            isHidden: self.hidden || hiddenByUsageMode(),
            initialValue: try initialResponseValue(for: kind),
            initialExpression: try sdcExpression(SDCExpressionURLs.initial),
            calculatedExpression: try sdcExpression(SDCExpressionURLs.calculated),
            variables: try sdcVariables(),
            constraints: try targetConstraints(),
            codes: itemCodes(),
            definition: self.definition?.value?.url,
            groupPath: context.groupPath,
            parentTaskId: context.parentTaskId
        )
        if task.initialValue == nil,
           let initialExpression = task.initialExpression,
           let engine = context.engine {
            // SDC population is best-effort: a failing initialExpression leaves the
            // item blank rather than failing the questionnaire.
            task.initialValue = try? engine.evaluateInitialValue(initialExpression, for: task)
        }
        guard itemType != .display, let nestedItems = item, !nestedItems.isEmpty else {
            return [task]
        }
        // Nested display items with the `help` itemControl are guidance for THIS
        // question, not standalone items; surface them as the task's footer.
        let helpItems = nestedItems.filter { $0.type.value == .display && ($0.itemControl == "help" || $0.itemControl == "help-button") }
        if !helpItems.isEmpty {
            let helpText = helpItems
                .compactMap { $0.text?.localizedString(for: context.options.locale) }
                .joined(separator: "\n")
            task.footer = task.footer.isEmpty ? helpText : "\(helpText)\n\(task.footer)"
        }
        let questionItems = nestedItems.filter { item in !helpItems.contains { $0.linkId == item.linkId } }
        return try [task] + nestedTasks(of: questionItems, under: task, using: context)
    }

    /// The item's own `enableWhen`/`enableWhenExpression`, combined with the condition of its parent.
    private func enabledCondition(
        using context: ConversionContext
    ) throws(FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Condition {
        var condition = try context.parentItemCondition && .init(self, using: context)
        if let enableExpression = try sdcExpression(SDCExpressionURLs.enableWhen) {
            guard enableWhen?.isEmpty ?? true else {
                // SDC: enableWhenExpression may only be used in the absence of enableWhen.
                throw .other("Item '\(try getLinkId())' has both enableWhen and enableWhenExpression")
            }
            condition = context.parentItemCondition && .expression(enableExpression)
        }
        return condition
    }

    /// The image or other attachment the item is rendered with, taken from SDC `itemMedia`.
    private func itemMedia(
        for kind: GroveQuestionnaire.Questionnaire.Task.Kind
    ) throws(FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Task.Media? {
        guard case .attachment(let attachment)? = extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-itemMedia"
        ).first?.value else {
            return nil
        }
        guard let base64 = attachment.data?.value?.dataString, let data = Data(base64Encoded: base64),
              let contentType = attachment.contentType?.value?.string else {
            throw .other("itemMedia on '\(try getLinkId())' must carry inline data and a contentType")
        }
        guard !kind.is(AnnotateImageQuestionKind.self) else {
            // The annotate-image kind draws on the itemMedia image itself; rendering it a
            // second time as decoration would show the body map twice.
            return nil
        }
        return .init(data: data, contentType: contentType, altText: attachment.title?.value?.string)
    }

    private func supportLinkFooter() -> String {
        guard case .uri(let supportLink)? = extensions(
            for: "http://hl7.org/fhir/StructureDefinition/questionnaire-supportLink"
        ).first?.value, let url = supportLink.value?.url else {
            return ""
        }
        return "[More Information](\(url.absoluteString))"
    }

    /// SDC usageMode: display-only items exist for QR review, not capture.
    private func hiddenByUsageMode() -> Bool {
        guard case .code(let usageMode)? = extensions(
            for: "http://hl7.org/fhir/StructureDefinition/questionnaire-usageMode"
        ).first?.value, let mode = usageMode.value?.string else {
            return false
        }
        return mode == "display" || mode == "display-non-empty"
    }

    /// FHIR: items nested beneath a question are only in scope once the parent question is
    /// answered; a generated QuestionnaireResponse nests their answers beneath the parent's answer.
    private func nestedTasks(
        of items: [ModelsR4.QuestionnaireItem],
        under task: GroveQuestionnaire.Questionnaire.Task,
        using context: ConversionContext
    ) throws(FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.Task] {
        let itemContext = ConversionContext(
            options: context.options,
            evaluationInstant: context.evaluationInstant,
            questionnaire: context.questionnaire,
            parentItemCondition: context.parentItemCondition && task.enabledCondition
                && .hasResponse(taskId: task.id),
            engine: context.engine,
            groupPath: context.groupPath,
            parentTaskId: task.id
        )
        return try items.flatMap2 { item throws(FHIRConversionError) in
            try item.toTasks(using: itemContext)
        }
    }

    fileprivate func toTaskKind( // swiftlint:disable:this cyclomatic_complexity function_body_length
        using context: ConversionContext
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Task.Kind {
        guard let itemType = type.value else {
            throw .other("QuestionnaireItem is missing 'type'")
        }
        switch itemType {
        case .group:
            throw .other("Attempted to request '\(GroveQuestionnaire.Questionnaire.Task.Kind.self)' for questionnaire item of type '\(itemType)'")
        case .display:
            // rendering-markdown on _text supplies a markdown-formatted equivalent,
            // which the native renderer displays with full markdown support.
            var displayText = text?.localizedString(for: context.options.locale)
            if case .markdown(let markdown)? = text?.extension?.first(where: {
                $0.url.value?.url.absoluteString == "http://hl7.org/fhir/StructureDefinition/rendering-markdown"
            })?.value, let string = markdown.value?.string {
                displayText = string
            }
            guard let text = displayText else {
                throw .other("QuestionnaireItem of type display is missing 'text'")
            }
            switch itemControl {
            case .none:
                return .instructional(text)
            case .some:
                if let custom = try toCustomTaskKind(using: context) {
                    return custom
                }
                // SDC: itemControl is a rendering hint; unsupporting renderers fall back.
                return .instructional(text)
            }
        case .question:
            throw .other("Invalid question type 'question'")
        case .boolean:
            switch itemControl {
            case .none:
                return .boolean
            case .some:
                if let custom = try toCustomTaskKind(using: context) {
                    return custom
                }
                return .boolean
            }
        case .decimal, .integer, .quantity:
            let inputMode: GroveQuestionnaire.Questionnaire.Task.Kind.NumericTaskConfig.InputMode
            switch itemControl {
            case "slider":
                inputMode = if let sliderStepValue {
                    .slider(stepValue: sliderStepValue.doubleValue)
                } else {
                    .numberPad(itemType == .integer ? .integer : .decimal)
                }
            case .none:
                inputMode = .numberPad(itemType == .integer ? .integer : .decimal)
            case .some:
                if let custom = try toCustomTaskKind(using: context) {
                    return custom
                }
                inputMode = .numberPad(itemType == .integer ? .integer : .decimal)
            }
            let unitCoding = self.unitCoding
            // questionnaire-unitOption codings (plus a contained unitValueSet) let the
            // participant choose the unit they answer in.
            var unitOptions: [GroveQuestionnaire.Questionnaire.Task.Kind.NumericTaskConfig.UnitOption] = []
            for ext in extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption") {
                guard case .coding(let coding) = ext.value, let code = coding.code?.value?.string else {
                    throw .other("unitOption without a coded unit")
                }
                unitOptions.append(.init(
                    display: coding.display?.localizedString(for: context.options.locale) ?? code,
                    system: coding.system?.value?.url,
                    code: code
                ))
            }
            if case .canonical(let canonical)? = extensions(
                for: "http://hl7.org/fhir/StructureDefinition/questionnaire-unitValueSet"
            ).first?.value, let reference = canonical.value?.url.absoluteString, reference.starts(with: "#") {
                let valueSet = context.questionnaire.getContainedValueSets().first { "#\($0.id?.value?.string ?? "")" == reference }
                for include in valueSet?.compose?.include ?? [] {
                    for concept in include.concept ?? [] {
                        guard let code = concept.code.value?.string else {
                            continue
                        }
                        unitOptions.append(.init(
                            display: concept.display?.localizedString(for: context.options.locale) ?? code,
                            system: include.system?.value?.url,
                            code: code
                        ))
                    }
                }
            }
            // A quantity item with one unitOption is a fixed-unit question. Preserve
            // that coding in the model so its response can emit a coded Quantity.
            let fixedQuantityUnit = itemType == .quantity && unitOptions.count == 1 ? unitOptions.first : nil
            return .numeric(.init(
                inputMode: inputMode,
                minimum: minValue?.doubleValue,
                maximum: maxValue?.doubleValue,
                maxDecimalPlaces: self.maximumDecimalPlaces?.uintValue,
                unit: unitCoding?.display?.value?.string ?? unit ?? fixedQuantityUnit?.display ?? unitOptions.first?.display ?? "",
                unitSystem: unitCoding?.system?.value?.url ?? fixedQuantityUnit?.system,
                unitCode: unitCoding?.code?.value?.string ?? fixedQuantityUnit?.code,
                valueKind: {
                    switch itemType {
                    case .integer: .integer
                    case .quantity: .quantity
                    default: .decimal
                    }
                }(),
                unitOptions: unitOptions
            ))
        case .date:
            return try toDateTimeTaskKind(style: .dateOnly, using: context)
        case .time:
            return try toDateTimeTaskKind(style: .timeOnly, using: context)
        case .dateTime:
            return try toDateTimeTaskKind(style: .dateAndTime, using: context)
        case .string, .text, .url:
            switch itemControl {
            case .some:
                if let custom = try toCustomTaskKind(using: context) {
                    return custom
                }
            case .none:
                break
            }
            // The v0.2 conversion surface maps only the standards-defined SDC keyboard hint.
            var keyboard: GroveQuestionnaire.Questionnaire.Task.Kind.FreeTextConfig.KeyboardHint?
            switch extensions(for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-keyboard").first?.value {
            case .coding(let coding):
                // SDC types the value as a Coding; the other two are lenient fallbacks.
                keyboard = (coding.code?.value?.string).flatMap { .init(rawValue: $0) }
            case .codeableConcept(let concept):
                keyboard = (concept.coding?.first?.code?.value?.string).flatMap { .init(rawValue: $0) }
            case .code(let code):
                keyboard = (code.value?.string).flatMap { .init(rawValue: $0) }
            default:
                keyboard = nil
            }
            return .freeText(.init(
                minLength: self.extensions(for: "http://hl7.org/fhir/StructureDefinition/minLength").first?.value?.intValue,
                maxLength: { () -> Int? in
                    if let value = self.maxLength?.value?.integer {
                        Int(value)
                    } else {
                        self.extensions(for: "http://hl7.org/fhir/StructureDefinition/maxLength").first?.value?.intValue
                    }
                }(),
                regex: self.validationRegularExpression,
                disableAutocorrection: itemType == .url,
                expectsURL: itemType == .url,
                keyboard: itemType == .url ? .url : keyboard,
                isMultiline: itemType == .text
            ))
        case .choice, .openChoice:
            var presentation = GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Presentation.list
            switch itemControl {
            case "check-box", "radio-button":
                // Both are the standard list; multi-select comes from `repeats` alone.
                break
            case "drop-down":
                presentation = .dropDown
            case "autocomplete":
                presentation = .autocomplete
            case .some:
                if let custom = try toCustomTaskKind(using: context) {
                    return custom
                }
            case .none:
                break
            }
            var options: [GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option] = []
            // Options can come from an answerValueSet — contained (`#id`) or resolved by the
            // app-supplied registry — preferring a pre-computed expansion over compose.
            if let answerValueSetURL = answerValueSet?.value?.url.absoluteString {
                let valueSet: ModelsR4.ValueSet?
                if answerValueSetURL.starts(with: "#") {
                    valueSet = context.questionnaire.getContainedValueSets().first {
                        "#\($0.id?.value?.string ?? "")" == answerValueSetURL
                    }
                } else if let url = URL(string: answerValueSetURL), let resolved = context.options.resolveValueSet?(url) {
                    valueSet = resolved
                } else {
                    throw .other("Unresolvable answerValueSet '\(answerValueSetURL)': supply it via FHIRConversionOptions.resolveValueSet")
                }
                guard let valueSet else {
                    throw .other("Unable to find answer options")
                }
                options += try valueSet.choiceOptions(for: context.options.locale)
            } else {
                // If the `QuestionnaireItem` has `answerOptions` defined instead, extract these options
                // and convert them to `Questionnaire.Task.Kind.ChoiceConfig.Option`s
                guard let answerOptions = answerOption else {
                    throw .other("Missing answerOption")
                }
                for option in answerOptions {
                    // questionnaire-optionPrefix ("A.", "B.") joins the displayed title.
                    var prefix: String?
                    if case .string(let value)? = option.extensions(
                        for: "http://hl7.org/fhir/StructureDefinition/questionnaire-optionPrefix"
                    ).first?.value {
                        prefix = value.localizedString(for: context.options.locale)
                    }
                    func title(_ display: String) -> String {
                        prefix.map { "\($0) \(display)" } ?? display
                    }
                    switch option.value {
                    case .coding(let coding):
                        guard let code = coding.code?.value?.string else {
                            throw .other("Invalid coding value for answer option")
                        }
                        let system = coding.system?.value?.url
                        options.append(.init(
                            // system|code token, so identical codes from different systems stay distinct
                            id: system.map { "\($0.absoluteString)|\(code)" } ?? code,
                            title: title(coding.display?.localizedString(for: context.options.locale) ?? code),
                            subtitle: "", // could supply this via an extension
                            fhirCoding: system.map { .init(system: $0, code: code) },
                            // the weight may sit on the answerOption element or on its coding
                            weight: option.itemWeight ?? coding.itemWeight,
                            isExclusive: option.isExclusiveOption
                        ))
                    case .string(let value):
                        guard let string = value.value?.string else {
                            throw .other("Invalid string value for answer option")
                        }
                        options.append(.init(id: "string|\(string)", title: title(string), answerValue: .string(string)))
                    case .integer(let value):
                        guard let integer = value.value?.integer else {
                            throw .other("Invalid integer value for answer option")
                        }
                        options.append(.init(id: "integer|\(integer)", title: title("\(integer)"), answerValue: .integer(Int(integer))))
                    case .date(let value):
                        guard let date = value.value else {
                            throw .other("Invalid date value for answer option")
                        }
                        let components = DateComponents(
                            year: date.year,
                            month: date.month.map(numericCast),
                            day: date.day.map(numericCast)
                        )
                        options.append(.init(id: "date|\(date.description)", title: title(date.description), answerValue: .date(components)))
                    case .time(let value):
                        guard let time = value.value else {
                            throw .other("Invalid time value for answer option")
                        }
                        let components = DateComponents(
                            hour: numericCast(time.hour),
                            minute: numericCast(time.minute),
                            second: Int(time.second.doubleValue)
                        )
                        options.append(.init(id: "time|\(time.description)", title: title(time.description), answerValue: .time(components)))
                    case .reference:
                        throw .other("Unsupported choice option value: \(option.value).")
                    }
                }
            }
            let orientation: GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Orientation
            if case .code(let code)? = extensions(
                for: "http://hl7.org/fhir/StructureDefinition/questionnaire-choiceOrientation"
            ).first?.value, code.value?.string == "horizontal" {
                orientation = .horizontal
            } else {
                orientation = .vertical
            }
            var openLabel: String?
            if case .string(let label)? = extensions(
                for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-openLabel"
            ).first?.value {
                openLabel = label.localizedString(for: context.options.locale)
            }
            return .choice(.init(
                options: options,
                hasFreeTextOtherOption: itemType == .openChoice,
                freeTextOtherOptionLabel: openLabel,
                allowsMultipleSelection: repeats == true,
                presentation: presentation,
                orientation: orientation,
                minSelections: repeats == true
                    ? self.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-minOccurs").first?.value?.intValue
                    : nil,
                maxSelections: repeats == true
                    ? self.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs").first?.value?.intValue
                    : nil
            ))
        case .attachment:
            switch itemControl {
            case .some:
                if let custom = try toCustomTaskKind(using: context) {
                    return custom
                }
                fallthrough
            default:
                return .fileAttachment(.init(
                    contentTypes: self.extensions(for: "http://hl7.org/fhir/StructureDefinition/mimeType").compactMapIntoSet { ext in
                        ext.value?.stringValue.flatMap { UTType(mimeType: $0) }
                    },
                    maxSize: { () -> UInt64? in
                        if let value = self.extensions(for: "http://hl7.org/fhir/StructureDefinition/maxSize").first?.value?.intValue {
                            UInt64(exactly: value)
                        } else {
                            nil
                        }
                    }(),
                    // ISSUE this will likely lead to effectively all such questions NOT allowing multiple selection,
                    // since the `repeats` field is typically not used, and eg the phoenix builder only offers it when you know where to look...
                    allowsMultipleSelection: repeats == true
                ))
            }
        case .reference:
            throw .other("Unsupported question type '\(itemType)'")
        }
    }

    /// Reads an SDC expression-valued extension, enforcing the FHIRPath language guard.
    private func sdcExpression(_ url: String) throws(FHIRConversionError) -> String? {
        guard let ext = extensions(for: FHIRPrimitive(FHIRURI(stringLiteral: url))).first else {
            return nil
        }
        guard case .expression(let expression) = ext.value else {
            throw .other("Extension '\(url)' must carry a valueExpression")
        }
        guard expression.language.value?.string == "text/fhirpath" else {
            // text/cql and x-fhir-query are out of scope; failing loudly beats mis-evaluating.
            throw .other("Unsupported Expression.language '\(expression.language.value?.string ?? "?")' — only text/fhirpath is supported")
        }
        return expression.expression?.value?.string
    }

    /// The codes identifying the question itself (`item.code`), carried through unchanged
    /// so a standardised instrument re-exports with the codes it was published with.
    private func itemCodes() -> [GroveQuestionnaire.Questionnaire.Task.Code] {
        (self.code ?? []).compactMap { coding in
            guard let code = coding.code?.value?.string else {
                return nil
            }
            return .init(system: coding.system?.value?.url, code: code, display: coding.display?.value?.string)
        }
    }

    /// The item's authored current `targetConstraint` extensions.
    private func targetConstraints() throws(FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.Task.Constraint] {
        var constraints: [GroveQuestionnaire.Questionnaire.Task.Constraint] = []
        for ext in extensions(for: FHIRPrimitive(FHIRURI(stringLiteral: SDCExpressionURLs.targetConstraint))) {
            constraints.append(try toConstraint(ext))
        }
        return constraints
    }

    private func toConstraint(
        _ ext: ModelsR4.Extension
    ) throws(FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Task.Constraint {
        guard let expression = try constraintExpression(of: ext) else {
            throw .other("Constraint on item '\((try? getLinkId()) ?? "?")' is missing its expression")
        }
        let human: String?
        switch ext.subExtension("human")?.value {
        case .string(let value):
            human = value.value?.string
        default:
            human = nil
        }
        let severity: GroveQuestionnaire.Questionnaire.Task.Constraint.Severity
        if case .code(let code)? = ext.subExtension("severity")?.value, code.value?.string == "warning" {
            severity = .warning
        } else {
            severity = .error
        }
        let key: String? = switch ext.subExtension("key")?.value {
        case .id(let value), .string(let value):
            value.value?.string
        default:
            nil
        }
        return .init(
            expression: expression,
            humanDescription: human ?? "Invalid Input",
            severity: severity,
            key: key
        )
    }

    /// A constraint's FHIRPath expression.
    private func constraintExpression(of ext: ModelsR4.Extension) throws(FHIRConversionError) -> String? {
        switch ext.subExtension("expression")?.value {
        case .expression(let value):
            guard value.language.value?.string == "text/fhirpath" else {
                throw .other("Unsupported constraint Expression.language — only text/fhirpath is supported")
            }
            return value.expression?.value?.string
        default:
            return nil
        }
    }

    /// The task's pre-populated starting value: `answerOption.initialSelected` for
    /// choice items, `item.initial` for everything else.
    private func initialResponseValue(
        for kind: GroveQuestionnaire.Questionnaire.Task.Kind
    ) throws(FHIRConversionError) -> QuestionnaireResponses.Response.Value? {
        if case .choice(let config) = kind.variant {
            return initialChoiceResponseValue(for: config)
        }
        guard let initial = initial?.first?.value else {
            return nil
        }
        switch initial {
        case .boolean, .integer, .decimal, .quantity, .string, .uri:
            return initial.scalarResponseValue
        case .date, .dateTime, .time:
            return initial.dateResponseValue
        case .coding:
            // Handled in the choice branch above; a coding initial on a non-choice item is invalid.
            throw .other("initial coding on a non-choice item")
        case .attachment, .reference:
            throw .other("Unsupported initial value type on item '\((try? getLinkId()) ?? "?")'")
        }
    }

    /// The options a choice task starts out with, from `answerOption.initialSelected` and
    /// any coded `item.initial`.
    private func initialChoiceResponseValue(
        for config: GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig
    ) -> QuestionnaireResponses.Response.Value? {
        // answerOption maps 1:1 onto config.options for answerOption-built items.
        var selected: Set<String> = []
        for (index, option) in (answerOption ?? []).enumerated()
        where option.initialSelected?.value?.bool == true && config.options.indices.contains(index) {
            selected.insert(config.options[index].id)
        }
        for initial in initial ?? [] {
            if case .coding(let coding) = initial.value, let code = coding.code?.value?.string {
                let token = (coding.system?.value?.url).map { "\($0.absoluteString)|\(code)" } ?? code
                if let match = config.options.first(where: { $0.id == token || $0.id.hasSuffix("|\(code)") && coding.system == nil }) {
                    selected.insert(match.id)
                }
            }
        }
        return selected.isEmpty ? nil : .choice(.init(selectedOptions: selected))
    }

    /// The style comes from the caller's `type` match, so every item type maps to exactly one.
    private func toDateTimeTaskKind(
        style: GroveQuestionnaire.Questionnaire.Task.Kind.DateTimeConfig.Style,
        using context: ConversionContext
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Task.Kind {
        if itemControl != nil, let custom = try toCustomTaskKind(using: context) {
            return custom
        }
        return .dateTime(.init(
            style: style,
            minValue: minDateValue(evaluationInstant: context.evaluationInstant),
            maxValue: maxDateValue(evaluationInstant: context.evaluationInstant)
        ))
    }

    /// Attempts to match this item against a registered custom question kind.
    ///
    /// Returns `nil` when no registered kind recognizes the item — SDC defines
    /// `itemControl` as a rendering hint, so unrecognized controls fall back to the
    /// standard widget for the item's type instead of failing the conversion.
    /// Errors thrown by a kind that DID recognize the item (malformed configuration)
    /// still propagate.
    private func toCustomTaskKind(
        using context: ConversionContext
    ) throws(GroveQuestionnaire.Questionnaire.FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Task.Kind? {
        for definition in context.options.knownQuestionKinds {
            guard let definition = definition as? any QuestionKindDefinitionWithFHIRDecodingSupport.Type else {
                continue
            }
            if let config = try definition.parse(self) {
                return .init(variant: .custom(questionKind: definition, config: config))
            }
        }
        return nil
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.ValueSet {
    /// Builds choice options from a ValueSet, preferring a pre-computed `expansion`
    /// over `compose` (which must enumerate concepts — filters need an expansion).
    fileprivate func choiceOptions(
        for locale: Locale
    ) throws(FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option] {
        var options: [GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option] = []
        if let contains = expansion?.contains, !contains.isEmpty {
            for entry in contains {
                guard let code = entry.code?.value?.string, let system = entry.system?.value?.url else {
                    throw .other("ValueSet expansion entry without system and code")
                }
                options.append(.init(
                    id: "\(system.absoluteString)|\(code)",
                    title: entry.display?.localizedString(for: locale) ?? code,
                    subtitle: "",
                    fhirCoding: .init(system: system, code: code),
                    weight: entry.itemWeight
                ))
            }
            return options
        }
        guard let includes = compose?.include, !includes.isEmpty else {
            throw .other("Unable to find answer options")
        }
        // Every compose.include contributes options; dropping any would silently
        // truncate the author's option list.
        for include in includes {
            guard let system = include.system?.value?.url else {
                throw .other("answerValueSet include without a system is not supported")
            }
            guard let concepts = include.concept, !concepts.isEmpty else {
                throw .other("answerValueSet include without enumerated concepts is not supported (ship an expansion instead)")
            }
            for option in concepts {
                guard let code = option.code.value?.string else {
                    throw .other("Invalid Concept in answer option")
                }
                options.append(.init(
                    id: "\(system.absoluteString)|\(code)",
                    title: option.display?.localizedString(for: locale) ?? code,
                    subtitle: "", // could supply this via an extension
                    fhirCoding: .init(system: system, code: code),
                    weight: option.itemWeight
                ))
            }
        }
        return options
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.QuestionnaireItemInitial.ValueX {
    /// The response value of a numeric, boolean or textual `initial[x]`; `nil` for the other kinds.
    fileprivate var scalarResponseValue: QuestionnaireResponses.Response.Value? {
        switch self {
        case .boolean(let value):
            (value.value?.bool).map { .bool($0) }
        case .integer(let value):
            (value.value?.integer).map { .number(Double($0)) }
        case .decimal(let value):
            (value.value?.decimal.doubleValue).map { .number($0) }
        case .quantity(let value):
            (value.value?.value?.decimal.doubleValue).map { .number($0) }
        case .string(let value):
            (value.value?.string).map { .string($0) }
        case .uri(let value):
            (value.value?.url.absoluteString).map { .string($0) }
        default:
            nil
        }
    }

    /// The response value of a `date`, `dateTime` or `time` `initial[x]`; `nil` for the other kinds.
    fileprivate var dateResponseValue: QuestionnaireResponses.Response.Value? {
        switch self {
        case .date(let value):
            guard let date = value.value else {
                return nil
            }
            return .date(DateComponents(year: date.year, month: date.month.map(numericCast), day: date.day.map(numericCast)))
        case .dateTime(let value):
            guard let dateTime = value.value else {
                return nil
            }
            return .date(DateComponents(
                year: dateTime.date.year,
                month: dateTime.date.month.map(numericCast),
                day: dateTime.date.day.map(numericCast),
                hour: (dateTime.time?.hour).map(numericCast),
                minute: (dateTime.time?.minute).map(numericCast),
                second: (dateTime.time?.second.doubleValue).map(Int.init)
            ))
        case .time(let value):
            guard let time = value.value else {
                return nil
            }
            return .date(DateComponents(hour: numericCast(time.hour), minute: numericCast(time.minute), second: Int(time.second.doubleValue)))
        default:
            return nil
        }
    }
}


extension ModelsR4.Extension {
    /// The nested extension carrying `url`, as used by the complex extensions.
    fileprivate func subExtension(_ url: String) -> ModelsR4.Extension? {
        self.extension?.first { $0.url.value?.url.absoluteString == url }
    }
}


extension ModelsR4.Extension.ValueX {
    var stringValue: String? {
        switch self {
        case .string(let value):
            value.value?.string
        case .code(let value):
            // The core mimeType extension carries a valueCode; accept it alongside the
            // lenient string form.
            value.value?.string
        default:
            nil
        }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value):
            (value.value?.integer).map { Int($0) }
        case .decimal(let value):
            // The core maxSize extension carries a valueDecimal; accept whole values.
            (value.value?.decimal).flatMap { Int(exactly: NSDecimalNumber(decimal: $0)) }
        default:
            nil
        }
    }
    
    /// The value's `CodeableConcept` value, if applicable.
    var codeableConceptValue: ModelsR4.CodeableConcept? {
        switch self {
        case .codeableConcept(let concept):
            concept
        default:
            nil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.QuestionnaireItem {
    fileprivate func getLinkId() throws(FHIRConversionError) -> String {
        guard let linkId = self.linkId.value?.string else {
            throw .other("QuestionnaireItem is missing 'linkId'")
        }
        return linkId
    }

    fileprivate func shortText(for locale: Locale) -> String? {
        guard case .string(let short)? = extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText"
        ).first?.value else {
            return nil
        }
        return short.localizedString(for: locale)
    }

    /// This item's linkId together with those of its descendants, i.e. the scope a `variable`
    /// declared on this item is visible in.
    fileprivate func linkIdsIncludingDescendants() -> Set<String> {
        var ids: Set<String> = []
        if let linkId = self.linkId.value?.string {
            ids.insert(linkId)
        }
        for child in item ?? [] {
            ids.formUnion(child.linkIdsIncludingDescendants())
        }
        return ids
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.Condition {
    fileprivate init(
        _ item: ModelsR4.QuestionnaireItem,
        using context: ConversionContext
    ) throws(FHIRConversionError) {
        guard let enableWhen = item.enableWhen, !enableWhen.isEmpty else {
            self = .none
            return
        }
        let behaviour = item.enableBehavior?.value ?? .all
        let elements = try enableWhen.mapIntoSet { enableWhen throws(FHIRConversionError) in
            try Self(enableWhen, using: context)
        }
        switch behaviour {
        case .all:
            self = .all(elements)
        case .any:
            self = .any(elements)
        }
    }
    
    fileprivate init( // swiftlint:disable:this function_body_length cyclomatic_complexity
        _ enableWhen: ModelsR4.QuestionnaireItemEnableWhen,
        using _: ConversionContext
    ) throws(FHIRConversionError) {
        guard let questionLinkId = enableWhen.question.value?.string else {
            throw .other("EnableWhen is missing question linkId")
        }
        guard let enableWhenOperator = enableWhen.operator.value else {
            throw .other("EnableWhen is missing operator")
        }
        switch enableWhenOperator {
        case .exists:
            switch enableWhen.answer {
            case .boolean(let value):
                guard let value = value.value?.bool else {
                    throw .other("EnableWhen is boolean value")
                }
                if value {
                    self = .hasResponse(taskId: questionLinkId)
                } else {
                    self = .not(.hasResponse(taskId: questionLinkId))
                }
            default:
                throw .other("EnableWhen with exists operation must have boolean value")
            }
        case .equal:
            self = .responseValueComparison(
                taskId: questionLinkId,
                operator: .equal,
                value: try enableWhen.answer.toConditionValue()
            )
        case .notEqual:
            // Deliberately NOT compiled as not(equal): FHIR's != evaluates to false when
            // the referenced question has no answer, whereas a negated equality would
            // evaluate to true there.
            self = .responseValueComparison(
                taskId: questionLinkId,
                operator: .notEqual,
                value: try enableWhen.answer.toConditionValue()
            )
        case .greaterThan:
            self = .responseValueComparison(
                taskId: questionLinkId,
                operator: .greaterThan,
                value: try enableWhen.answer.toConditionValue()
            )
        case .lessThan:
            self = .responseValueComparison(
                taskId: questionLinkId,
                operator: .lessThan,
                value: try enableWhen.answer.toConditionValue()
            )
        case .greaterThanOrEqual:
            self = .responseValueComparison(
                taskId: questionLinkId,
                operator: .greaterThanOrEqual,
                value: try enableWhen.answer.toConditionValue()
            )
        case .lessThanOrEqual:
            self = .responseValueComparison(
                taskId: questionLinkId,
                operator: .lessThanOrEqual,
                value: try enableWhen.answer.toConditionValue()
            )
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.QuestionnaireItemEnableWhen.AnswerX {
    private static func unwrap<T>(_ value: T?) throws(FHIRConversionError) -> T {
        if let value {
            return value
        } else {
            throw .other("\(Self.self) is missing value")
        }
    }

    fileprivate func toConditionValue() throws(FHIRConversionError) -> GroveQuestionnaire.Questionnaire.Condition.Value {
        switch self {
        case .boolean(let value):
            return .bool(try Self.unwrap(value.value?.bool))
        case .coding(let value):
            let code = try Self.unwrap(value.code?.value?.string)
            // Match the option-id token form: system|code when the coding carries a
            // system, bare code otherwise (which then matches any system).
            let token = (value.system?.value?.url).map { "\($0.absoluteString)|\(code)" } ?? code
            return .SCMCOption(id: token)
        case .date, .time, .dateTime:
            return .date(try Self.unwrap(dateComponents()))
        case .decimal(let value):
            return .decimal(try Self.unwrap(value.value?.decimal.doubleValue))
        case .integer(let value):
            return .integer(Int(try Self.unwrap(value.value?.integer)))
        case .quantity(let quantity):
            // Same-unit magnitude comparison; unit conversion is out of scope, so a
            // condition whose unit differs from the question's simply never matches.
            let value = try Self.unwrap(quantity.value?.value?.decimal.doubleValue)
            return .quantity(value: value, unitCode: quantity.code?.value?.string ?? quantity.unit?.value?.string)
        case .reference(let value):
            throw .other("Unsupported comparison value '\(value)'")
        case .string(let value):
            return .string(try Self.unwrap(value.value?.string))
        }
    }

    /// The components of a `date`, `time` or `dateTime` answer; `nil` for the other kinds.
    private func dateComponents() -> DateComponents? {
        switch self {
        case .date(let value):
            guard let date = value.value else {
                return nil
            }
            return DateComponents(
                year: date.year,
                month: date.month.map(numericCast),
                day: date.day.map(numericCast)
            )
        case .time(let value):
            guard let time = value.value else {
                return nil
            }
            return DateComponents(
                hour: numericCast(time.hour),
                minute: numericCast(time.minute),
                second: Int(time.second.doubleValue)
            )
        case .dateTime(let value):
            guard let value = value.value else {
                return nil
            }
            return DateComponents(
                year: value.date.year,
                month: value.date.month.map(numericCast),
                day: (value.date.day).map(numericCast),
                hour: (value.time?.hour).map(numericCast),
                minute: (value.time?.minute).map(numericCast),
                second: (value.time?.second.doubleValue).map(Int.init)
            )
        default:
            return nil
        }
    }
}


// MARK: Utils

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRTypeWithExtensions {
    /// Reads the supported FHIRPath form of the SDC `variable` extension while
    /// retaining its declaration order for lossless export.
    fileprivate func sdcVariables() throws(FHIRConversionError) -> [GroveQuestionnaire.Questionnaire.ExpressionVariable] {
        var variables: [GroveQuestionnaire.Questionnaire.ExpressionVariable] = []
        for ext in extensions(for: "http://hl7.org/fhir/StructureDefinition/variable") {
            guard case .expression(let expression) = ext.value,
                  let name = expression.name?.value?.string,
                  let source = expression.expression?.value?.string else {
                throw FHIRConversionError.other("Malformed variable extension")
            }
            guard expression.language.value?.string == "text/fhirpath" else {
                throw FHIRConversionError.other(
                    "Unsupported Expression.language '\(expression.language.value?.string ?? "?")' — only text/fhirpath is supported"
                )
            }
            variables.append(.init(name: name, expression: source))
        }
        return variables
    }
}

extension Sequence {
    /// Same as Swift's `flatMap`, but it supports typed throws
    fileprivate func flatMap2<U, E>(_ transform: (Element) throws(E) -> some Sequence<U>) throws(E) -> [U] {
        var result: [U] = []
        for element in self {
            result.append(contentsOf: try transform(element))
        }
        return result
    }
}
