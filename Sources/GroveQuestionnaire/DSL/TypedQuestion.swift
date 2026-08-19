//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A component that collects a single typed answer and doubles as its response handle.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol TypedQuestion<Answer>: QuestionnaireComponent, Hashable, Identifiable where ID == Questionnaire.Task.ID {
    associatedtype Answer: Sendable

    /// The question's linkId — explicit, stable wire identity.
    var id: Questionnaire.Task.ID { get }

    /// Reads a typed answer from a stored response value; public for protocol conformance.
    @_documentation(visibility: internal)
    static func _extractAnswer(from value: QuestionnaireResponses.Response.Value) -> Answer? // swiftlint:disable:this identifier_name
    /// Stores a typed answer as a response value; public for protocol conformance.
    ///
    /// An instance method because the stored form can depend on the question: a choice
    /// question stores the `system|code` option token its own options carry.
    @_documentation(visibility: internal)
    func _storeAnswer(_ answer: Answer) -> QuestionnaireResponses.Response.Value // swiftlint:disable:this identifier_name
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension TypedQuestion {
    /// A condition that holds once this question has any answer.
    public var answered: Questionnaire.Condition {
        .hasResponse(taskId: id)
    }

    /// Pre-fills the question with a starting value the participant can edit
    /// (FHIR `initial[x]`).
    public func initialValue(_ answer: Answer) -> Self {
        var copy = self
        copy._core.initialValue = _storeAnswer(answer)
        return copy
    }
}


// MARK: Typed Response Access

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// Handles are erased to linkIds, so reading one from another instrument's responses
    /// compiles and then quietly answers `nil` forever. Catch it on first access instead.
    private func assertBelongsToQuestionnaire(_ question: some TypedQuestion) {
        assert(
            questionnaire.allLinkIDs.contains(question.id),
            "'\(question.id)' is not part of '\(questionnaire.metadata.title)'; this access always sees no answer"
        )
    }

    /// Typed access to a question's answer, keyed by its declared handle.
    ///
    /// ```swift
    /// let severity = responses[PHQ9.total]   // Double?
    /// ```
    public subscript<Question: TypedQuestion>(question: Question) -> Question.Answer? {
        get {
            assertBelongsToQuestionnaire(question)
            return Question._extractAnswer(from: responses[question.id].value)
        }
        set {
            assertBelongsToQuestionnaire(question)
            responses[question.id] = .init(value: newValue.map(question._storeAnswer) ?? .none)
        }
    }
}
