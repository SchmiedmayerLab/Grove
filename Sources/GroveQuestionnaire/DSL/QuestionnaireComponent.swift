//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Anything that can appear inside a ``Questionnaire/Section``'s builder block.
///
/// Declared questions double as *typed handles*: declare them once (typically as
/// `static let`s), list them in the questionnaire body, and reuse the same value for
/// typed response access (`responses[PHQ9.sleep]`) and typed conditions
/// (`PHQ9.sleep.selected(.nearlyEveryDay)`).
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol QuestionnaireComponent: Sendable {
    /// Shared modifier storage; public for protocol conformance, not user API.
    @_documentation(visibility: internal)
    var _core: ComponentCore { get set } // swiftlint:disable:this identifier_name

    /// Compiles the component into model tasks; public for protocol conformance, not user API.
    @_documentation(visibility: internal)
    func _makeTasks() -> [Questionnaire.Task] // swiftlint:disable:this identifier_name
}


// MARK: Modifiers

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireComponent {
    /// Allows the participant to skip this question (FHIR `required` = false).
    public func optional(_ isOptional: Bool = true) -> Self {
        var copy = self
        copy._core.isOptional = isOptional
        return copy
    }

    /// Displays the value without allowing edits (FHIR `readOnly`).
    public func readOnly(_ isReadOnly: Bool = true) -> Self {
        var copy = self
        copy._core.isReadOnly = isReadOnly
        return copy
    }

    /// Hides the item from the participant while keeping it in the response
    /// (FHIR `questionnaire-hidden`) — for calculated or pre-populated carriers.
    public func hidden(_ isHidden: Bool = true) -> Self {
        var copy = self
        copy._core.isHidden = isHidden
        return copy
    }

    /// Shows the item only when the condition holds (FHIR `enableWhen`).
    public func enabledWhen(_ condition: Questionnaire.Condition) -> Self {
        var copy = self
        copy._core.enabledCondition = copy._core.enabledCondition && condition
        return copy
    }

    /// A secondary text line below the title.
    public func subtitle(_ subtitle: String) -> Self {
        var copy = self
        copy._core.subtitle = subtitle
        return copy
    }

    /// Guidance shown below the item (exported as a `help` display item).
    public func help(_ text: String) -> Self {
        var copy = self
        copy._core.footer = text
        return copy
    }

    /// Question numbering shown before the title (FHIR `item.prefix`, e.g. "1a.").
    public func prefix(_ prefix: String) -> Self {
        var copy = self
        copy._core.prefix = prefix
        return copy
    }

    /// An abbreviated title for constrained displays (SDC `shortText`).
    public func shortTitle(_ shortTitle: String) -> Self {
        var copy = self
        copy._core.shortTitle = shortTitle
        return copy
    }

    /// An image rendered alongside the question (SDC `itemMedia`).
    public func media(_ media: Questionnaire.Task.Media) -> Self {
        var copy = self
        copy._core.media = media
        return copy
    }

    /// Continuously computes this item's value from other answers
    /// (SDC `calculatedExpression`, FHIRPath).
    public func calculated(_ expression: ScoreExpression) -> Self {
        var copy = self
        copy._core.calculatedExpression = expression.fhirPath
        // Nobody can answer a computed question, so requiring one strands the section:
        // it stays incomplete until an answer arrives that the participant cannot give.
        copy._core.isOptional = true
        return copy
    }

    /// Unavailable string overload that diagnoses hand-written calculated expressions.
    @available(
        *, unavailable,
        message: "Build the score from the questions: .calculated(.sumOfWeights(of: a, b)). For a hand-written expression use .calculated(.raw(…))"
    )
    public func calculated(_: String) -> Self { self }

    /// Unavailable modifier that diagnoses follow-ups attached to non-choice components.
    @available(
        *, unavailable,
        message: "Follow-ups are asked per selected option, so they belong on a choice question. To gate a sibling, use .enabledWhen(…)"
    )
    public func followUp(@SectionContentBuilder _: () -> [any QuestionnaireComponent]) -> Self { self }

    /// A cross-field validation rule with an authored message (FHIR `targetConstraint`).
    public func constraint(_ fhirPath: String, message: String) -> Self {
        var copy = self
        copy._core.constraints.append(.init(expression: fhirPath, humanDescription: message))
        return copy
    }
}
