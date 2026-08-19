//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A multi-select choice question whose options are only known at runtime.
///
/// The multi-select counterpart of ``DynamicChoiceQuestion``: the answer is the set of
/// selected codes. Prefer ``MultiChoiceQuestion`` whenever the options are known at
/// compile time.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct DynamicMultiChoiceQuestion: TypedQuestion {
    public typealias Answer = Set<String>

    public var _core = ComponentCore() // swiftlint:disable:this identifier_name
    public let id: Questionnaire.Task.ID
    var single: DynamicChoiceQuestion
    var minSelections: Int?
    var maxSelections: Int?

    var title: String {
        single.title
    }

    /// Creates a multi-select choice question.
    public init(_ id: Questionnaire.Task.ID, _ title: String, system: URL? = nil, choices: [Choice]) {
        self.id = id
        self.single = DynamicChoiceQuestion(id, title, system: system, choices: choices)
        self.single.allowsMultipleSelection = true
    }

    // `Answer?` is the TypedQuestion contract: nil means the participant has not answered,
    // which an empty selection does not.
    // swiftlint:disable:next identifier_name discouraged_optional_collection
    public static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> Set<String>? {
        let selected = value.choiceValue.selectedOptions
        guard !selected.isEmpty else {
            return nil
        }
        return Set(selected.map { optionId in
            optionId.contains("|") ? String(optionId.split(separator: "|", maxSplits: 1).last ?? "") : optionId
        })
    }

    /// Bounds the number of selections (`questionnaire-minOccurs`/`maxOccurs`).
    public func selections(_ range: ClosedRange<Int>) -> Self {
        var copy = self
        copy.minSelections = range.lowerBound
        copy.maxSelections = range.upperBound
        return copy
    }

    /// Adds a free-text "Other" option (FHIR item type `open-choice`).
    public func allowsOther(_ label: String? = nil) -> Self {
        var copy = self
        copy.single = copy.single.allowsOther(label)
        return copy
    }

    /// Questions asked once per selected option, presented on a pushed page.
    ///
    /// The follow-ups export as items nested beneath the question, and their answers as
    /// `answer.item` — FHIR's own "asked in the context of this answer".
    public func followUp(@SectionContentBuilder content: () -> [any QuestionnaireComponent]) -> Self {
        var copy = self
        copy.single = copy.single.followUp(content: content)
        return copy
    }

    public func _storeAnswer(_ answer: Set<String>) -> QuestionnaireResponses.Response.Value { // swiftlint:disable:this identifier_name
        .choice(.init(selectedOptions: Set(answer.map(single.optionId(for:)))))
    }

    func makeConfig() -> Questionnaire.Task.Kind.ChoiceConfig {
        var config = single.makeConfig()
        config.minSelections = minSelections
        config.maxSelections = maxSelections
        return config
    }

    public func _makeTasks() -> [Questionnaire.Task] { // swiftlint:disable:this identifier_name
        var task = Questionnaire.Task(id: id, title: title, kind: .choice(makeConfig()))
        _core.apply(to: &task)
        return [task]
    }

    /// A condition that holds while the option with the given code is selected.
    public func selected(_ code: String) -> Questionnaire.Condition {
        .responseValueComparison(taskId: id, operator: .equal, value: .SCMCOption(id: single.optionId(for: code)))
    }
}
