//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The DSL name for a questionnaire section (one page of questions).
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias Section = Questionnaire.Section


/// Collects the components of a ``Questionnaire/Section``.
@available(iOS 18, macOS 15, watchOS 11, *)
@resultBuilder
public enum SectionContentBuilder {
    /// Contributes a single component written on its own line.
    public static func buildExpression(_ component: some QuestionnaireComponent) -> [any QuestionnaireComponent] {
        [component]
    }

    /// Starts the block from its first line.
    ///
    /// Accumulating pairwise means a bad item fails on its own line rather than taking the
    /// whole block with it, and an empty block has no `buildBlock()` to resolve to.
    public static func buildPartialBlock(first: [any QuestionnaireComponent]) -> [any QuestionnaireComponent] {
        first
    }

    /// Appends the next line's components to those gathered so far.
    public static func buildPartialBlock(
        accumulated: [any QuestionnaireComponent],
        next: [any QuestionnaireComponent]
    ) -> [any QuestionnaireComponent] {
        accumulated + next
    }

    /// Contributes nothing when an `if` without an `else` does not run.
    public static func buildOptional(_ components: [any QuestionnaireComponent]?) -> [any QuestionnaireComponent] {
        // swiftlint:disable:previous discouraged_optional_collection
        components ?? []
    }

    /// Contributes the components of an `if` branch.
    public static func buildEither(first components: [any QuestionnaireComponent]) -> [any QuestionnaireComponent] {
        components
    }

    /// Contributes the components of an `else` branch.
    public static func buildEither(second components: [any QuestionnaireComponent]) -> [any QuestionnaireComponent] {
        components
    }

    /// Flattens the components a `for` loop contributes.
    public static func buildArray(_ components: [[any QuestionnaireComponent]]) -> [any QuestionnaireComponent] {
        components.flatMap(\.self)
    }

    /// Unavailable builder overload that diagnoses a condition without an item.
    @available(*, unavailable, message: "A condition belongs on an item: put it on the question with .enabledWhen(…)")
    public static func buildExpression(_: Questionnaire.Condition) -> [any QuestionnaireComponent] { [] }

    /// Unavailable builder overload that diagnoses text without an item.
    @available(*, unavailable, message: "Text needs an item: wrap it in Instruction(\"<linkId>\", \"…\")")
    public static func buildExpression(_: String) -> [any QuestionnaireComponent] { [] }

    /// Unavailable builder overload that diagnoses a nested section.
    @available(*, unavailable, message: "Sections do not nest; use Group(\"<linkId>\") { … } inside a section")
    public static func buildExpression(_: Questionnaire.Section) -> [any QuestionnaireComponent] { [] }
}


// MARK: DSL Entry Point

@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Section {
    /// Declares a section (one page of the questionnaire) from typed components.
    ///
    /// ```swift
    /// Section("symptoms", title: "Your Symptoms") {
    ///     PHQ9.interest
    ///     PHQ9.sleep
    /// }
    /// ```
    public init(_ id: String, title: String = "", @SectionContentBuilder content: () -> [any QuestionnaireComponent]) {
        self.init(id: id, title: title, tasks: content().flatMap { $0._makeTasks() }, fhirGroupId: id)
    }

    /// An abbreviated title for constrained displays (SDC `shortText`).
    public func shortTitle(_ shortTitle: String) -> Self {
        var copy = self
        copy.shortTitle = shortTitle
        return copy
    }
}
