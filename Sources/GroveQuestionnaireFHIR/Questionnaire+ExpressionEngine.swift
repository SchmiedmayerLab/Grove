//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRPathParser
public import GroveQuestionnaire
public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire {
    /// Returns a copy that evaluates its calculated expressions.
    ///
    /// A questionnaire imported from FHIR gets its engine during conversion. One declared
    /// in Swift has no engine until this attaches it, so `calculated(_:)`
    /// scores stay empty without it.
    ///
    /// ```swift
    /// let questionnaire = try SleepCheckIn.questionnaire.withExpressionEngine(clock: .live(in: .current))
    /// ```
    ///
    /// The engine reads the FHIR projection of this questionnaire, but the questionnaire
    /// itself is unchanged — anything the FHIR export does not carry survives, because the
    /// model is never round-tripped.
    ///
    /// - parameter clock: What the time functions read, such as `today()` in a score.
    /// - parameter launchContext: Resources the SDC `launchContext` expressions may read.
    public func withExpressionEngine(clock: QuestionnaireClock, launchContext: [String: ResourceProxy] = [:]) throws -> Self {
        var copy = self
        copy.expressionEngine = try FHIRQuestionnaireExpressionEngine(
            questionnaire: try ModelsR4.Questionnaire(projecting: self),
            variables: [],
            launchContext: launchContext.mapValues { try FHIRPathNode.encoding($0) },
            clock: clock
        )
        return copy
    }
}
