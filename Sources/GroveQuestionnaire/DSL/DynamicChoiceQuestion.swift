//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A single-select choice question whose options are only known at runtime.
///
/// Reach for this when the options cannot be spelled out in Swift — an `answerValueSet`
/// resolved from a server, or a list assembled from data. The answer is the selected
/// option's code, so nothing checks it; prefer ``ChoiceQuestion`` whenever the options
/// are known at compile time.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct DynamicChoiceQuestion: TypedQuestion {
    public typealias Answer = String

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    let title: String
    let choices: [Choice]
    var system: URL?
    var allowsMultipleSelection = false
    var hasOtherOption = false
    var otherOptionLabel: String?
    var presentation = Questionnaire.Task.Kind.ChoiceConfig.Presentation.list
    var orientation = Questionnaire.Task.Kind.ChoiceConfig.Orientation.vertical
    var followUps: [Questionnaire.Task] = []

    /// Creates a single-select choice question.
    /// - parameter id: The question's linkId.
    /// - parameter title: The question text.
    /// - parameter system: The default coding system of the options.
    /// - parameter choices: The answer options.
    public init(_ id: Questionnaire.Task.ID, _ title: String, system: URL? = nil, choices: [Choice]) {
        self.id = id
        self.title = title
        self.system = system
        self.choices = choices
    }

    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> String? { // swiftlint:disable:this identifier_name
        value.choiceValue.selectedOptions.first.map { optionId in
            optionId.contains("|") ? String(optionId.split(separator: "|", maxSplits: 1).last ?? "") : optionId
        }
    }

    /// Adds a free-text "Other" option (FHIR item type `open-choice`).
    public func allowsOther(_ label: String? = nil) -> Self {
        var copy = self
        copy.hasOtherOption = true
        copy.otherOptionLabel = label
        return copy
    }

    /// Renders the options as a compact menu (`drop-down` itemControl).
    public func dropDown() -> Self {
        var copy = self
        copy.presentation = .dropDown
        return copy
    }

    /// Renders a type-ahead filter over the options (`autocomplete` itemControl).
    public func autocomplete() -> Self {
        var copy = self
        copy.presentation = .autocomplete
        return copy
    }

    /// Lays the options out horizontally (`questionnaire-choiceOrientation`).
    public func horizontal() -> Self {
        var copy = self
        copy.orientation = .horizontal
        return copy
    }

    /// Questions asked once per selected option, presented on a pushed page.
    ///
    /// The follow-ups export as items nested beneath the question, and their answers as
    /// `answer.item` — FHIR's own "asked in the context of this answer".
    public func followUp(@SectionContentBuilder content: () -> [any QuestionnaireComponent]) -> Self {
        var copy = self
        copy.followUps += content().flatMap { $0._makeTasks() }
        return copy
    }

    public func _storeAnswer(_ answer: String) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        .choice(.init(selectedOptions: [optionId(for: answer)]))
    }

    /// The stored option id for an answer code: options are identified by their
    /// `system|code` token, so a bare code is resolved against the declared choices.
    func optionId(for code: String) -> Questionnaire.Task.Kind.ChoiceConfig.Option.ID {
        guard !code.contains("|") else {
            return code
        }
        return choices.first { $0.code == code }?.option(defaultSystem: system).id ?? code
    }

    func makeConfig() -> Questionnaire.Task.Kind.ChoiceConfig {
        .init(
            options: choices.map { $0.option(defaultSystem: system) },
            hasFreeTextOtherOption: hasOtherOption,
            freeTextOtherOptionLabel: otherOptionLabel,
            allowsMultipleSelection: allowsMultipleSelection,
            presentation: presentation,
            orientation: orientation,
            followUpTasks: followUps
        )
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: title, kind: .choice(makeConfig()))
        _core.apply(to: &task)
        return [task]
    }

    /// A condition that holds while the option with the given code is selected.
    public func selected(_ code: String) -> Questionnaire.Condition {
        .responseValueComparison(taskId: id, operator: .equal, value: .SCMCOption(id: optionId(for: code)))
    }
}
