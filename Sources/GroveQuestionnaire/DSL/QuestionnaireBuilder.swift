//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Collects the sections of a ``Questionnaire``.
@available(iOS 18, macOS 15, watchOS 11, *)
@resultBuilder
public enum QuestionnaireBuilder {
    /// Contributes a single section written on its own line.
    public static func buildExpression(_ section: Questionnaire.Section) -> [Questionnaire.Section] {
        [section]
    }

    /// Starts the block from its first line.
    public static func buildPartialBlock(first: [Questionnaire.Section]) -> [Questionnaire.Section] {
        first
    }

    /// Appends the next line's sections to those gathered so far.
    public static func buildPartialBlock(
        accumulated: [Questionnaire.Section],
        next: [Questionnaire.Section]
    ) -> [Questionnaire.Section] {
        accumulated + next
    }

    /// Contributes nothing when an `if` without an `else` does not run.
    public static func buildOptional(_ sections: [Questionnaire.Section]?) -> [Questionnaire.Section] {
        // swiftlint:disable:previous discouraged_optional_collection
        sections ?? []
    }

    /// Contributes the sections of an `if` branch.
    public static func buildEither(first sections: [Questionnaire.Section]) -> [Questionnaire.Section] {
        sections
    }

    /// Contributes the sections of an `else` branch.
    public static func buildEither(second sections: [Questionnaire.Section]) -> [Questionnaire.Section] {
        sections
    }

    /// Flattens the sections a `for` loop contributes.
    public static func buildArray(_ sections: [[Questionnaire.Section]]) -> [Questionnaire.Section] {
        sections.flatMap(\.self)
    }

    /// Unavailable builder overload that diagnoses a questionnaire item without a section.
    @available(*, unavailable, message: "A questionnaire is built from Sections; wrap this item in Section(\"<linkId>\") { … }")
    public static func buildExpression(_: some QuestionnaireComponent) -> [Questionnaire.Section] { [] }
}


// MARK: DSL Entry Point

@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// Declares a questionnaire natively in Swift.
    ///
    /// The same model backs FHIR-imported questionnaires, so a Swift-declared
    /// instrument renders identically and exports to a conformant FHIR R4
    /// `Questionnaire` (and its collected answers to a `QuestionnaireResponse`).
    ///
    /// ```swift
    /// enum Onboarding {
    ///     static let mood = BooleanQuestion("mood", "Are you feeling well today?")
    ///     static let followUp = TextQuestion("mood-details", "What is bothering you?")
    ///         .enabledWhen(mood == false)
    ///
    ///     static let questionnaire = Questionnaire(
    ///         url: URL(string: "https://example.org/fhir/Questionnaire/onboarding")!,
    ///         version: "1.0.0",
    ///         title: "Daily Check-In"
    ///     ) {
    ///         Section("checkin", title: "Check-In") {
    ///             mood
    ///             followUp
    ///         }
    ///     }
    /// }
    /// ```
    public init(
        url: URL,
        version: String,
        title: String,
        explainer: String = "",
        publisher: String? = nil,
        copyright: String? = nil,
        @QuestionnaireBuilder sections: () -> [Section]
    ) {
        self.init(
            metadata: .init(
                id: url.absoluteString,
                url: url,
                version: version,
                title: title,
                explainer: explainer,
                publisher: publisher,
                copyright: copyright
            ),
            sections: sections()
        )
    }
}
