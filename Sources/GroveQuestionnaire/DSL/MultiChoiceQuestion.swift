//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A multi-select choice question (FHIR item type `choice` with `repeats`).
///
/// The multi-select counterpart of ``ChoiceQuestion``: the typed answer is the set of
/// selected options.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct MultiChoiceQuestion<Option: QuestionnaireOption>: TypedQuestion {
    public typealias Answer = Set<Option>

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    var coded: DynamicMultiChoiceQuestion

    /// Creates a multi-select choice question over an option type.
    /// - parameter id: The question's linkId.
    /// - parameter title: The question text.
    public init(_ id: Questionnaire.Task.ID, _ title: String) {
        self.id = id
        self.coded = DynamicMultiChoiceQuestion(id, title, system: Option.system, choices: Option.choices)
    }

    // `Answer?` is the TypedQuestion contract: nil means the participant has not answered,
    // which an empty selection does not.
    // swiftlint:disable:next identifier_name discouraged_optional_collection
    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> Set<Option>? {
        let codes = DynamicMultiChoiceQuestion._extractAnswer(from: value) ?? []
        let options = Set(codes.compactMap(Option.init(rawValue:)))
        return options.isEmpty ? nil : options
    }

    /// Bounds the number of selections (`questionnaire-minOccurs`/`maxOccurs`).
    public func selections(_ range: ClosedRange<Int>) -> Self {
        var copy = self
        copy.coded = coded.selections(range)
        return copy
    }

    /// Adds a free-text "Other" option (FHIR item type `open-choice`).
    public func allowsOther(_ label: String? = nil) -> Self {
        var copy = self
        copy.coded = coded.allowsOther(label)
        return copy
    }

    /// Questions asked once per selected option, presented on a pushed page.
    ///
    /// The follow-ups export as items nested beneath the question, and their answers as
    /// `answer.item` — FHIR's own "asked in the context of this answer".
    public func followUp(@SectionContentBuilder content: () -> [any QuestionnaireComponent]) -> Self {
        var copy = self
        copy.coded = coded.followUp(content: content)
        return copy
    }

    public func _storeAnswer(_ answer: Set<Option>) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        coded._storeAnswer(Set(answer.map(\.rawValue)))
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
