//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A single-select choice question (FHIR item type `choice`).
///
/// The options are the cases of a ``QuestionnaireOption`` type, which is also the typed
/// answer:
///
/// ```swift
/// static let sleep = ChoiceQuestion<Frequency>("sleep", "Trouble sleeping?")
///
/// sleep.selected(.nearlyEveryDay)   // a typo is a compile error
/// responses[sleep]                  // Frequency?
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ChoiceQuestion<Option: QuestionnaireOption>: TypedQuestion {
    public typealias Answer = Option

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    var coded: DynamicChoiceQuestion

    /// Creates a single-select choice question over an option type.
    /// - parameter id: The question's linkId.
    /// - parameter title: The question text.
    public init(_ id: Questionnaire.Task.ID, _ title: String) {
        self.id = id
        self.coded = DynamicChoiceQuestion(id, title, system: Option.system, choices: Option.choices)
    }

    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> Option? { // swiftlint:disable:this identifier_name
        DynamicChoiceQuestion._extractAnswer(from: value).flatMap(Option.init(rawValue:))
    }

    /// Adds a free-text "Other" option (FHIR item type `open-choice`).
    public func allowsOther(_ label: String? = nil) -> Self {
        var copy = self
        copy.coded = coded.allowsOther(label)
        return copy
    }

    /// Renders the options as a compact menu (`drop-down` itemControl).
    public func dropDown() -> Self {
        var copy = self
        copy.coded = coded.dropDown()
        return copy
    }

    /// Renders a type-ahead filter over the options (`autocomplete` itemControl).
    public func autocomplete() -> Self {
        var copy = self
        copy.coded = coded.autocomplete()
        return copy
    }

    /// Lays the options out horizontally (`questionnaire-choiceOrientation`).
    public func horizontal() -> Self {
        var copy = self
        copy.coded = coded.horizontal()
        return copy
    }

    /// Questions asked once per selected option, presented on a pushed page.
    ///
    /// ```swift
    /// ChoiceQuestion<Activity>("activity", "What did you do?")
    ///     .followUp {
    ///         ChoiceQuestion<Frequency>("how-often", "How often?")
    ///         NumberQuestion.integer("minutes", "For how many minutes?")
    ///     }
    /// ```
    ///
    /// The follow-ups export as items nested beneath the question, and their answers as
    /// `answer.item` — FHIR's own "asked in the context of this answer". The same questions
    /// are asked for every selected option; to gate a *sibling* question on one answer,
    /// use ``QuestionnaireComponent/enabledWhen(_:)`` instead.
    public func followUp(@SectionContentBuilder content: () -> [any QuestionnaireComponent]) -> Self {
        var copy = self
        copy.coded = coded.followUp(content: content)
        return copy
    }

    public func _storeAnswer(_ answer: Option) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        coded._storeAnswer(answer.rawValue)
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: coded.title, kind: .choice(coded.makeConfig()))
        _core.apply(to: &task)
        return [task]
    }

    /// A condition that holds while the given option is selected.
    public func selected(_ option: Option) -> Questionnaire.Condition {
        coded.selected(option.rawValue)
    }
}
