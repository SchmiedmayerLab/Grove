//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The environment a FHIRPath expression is evaluated in: the input collection
/// (`$this` at the root) plus named `%constants` such as `%resource`.
public struct FHIRPathEvaluationContext: Sendable {
    /// The input collection the expression starts from.
    public var focus: [FHIRPathValue]
    /// Named environment constants, addressed as `%name` in expressions.
    ///
    /// Callers typically provide `resource` (the QuestionnaireResponse under
    /// construction), `questionnaire`, and `context`, plus any SDC `variable`s.
    public var constants: [String: [FHIRPathValue]]
    /// The instant used for `now()`/`today()`/`timeOfDay()`.
    ///
    /// Callers must supply this explicitly; pass a fixed instant to make an evaluation reproducible.
    public var evaluationInstant: Date
    /// The explicit zone used to project `evaluationInstant` for `now()`, `today()`, and
    /// `timeOfDay()`. It is never inferred from the device.
    public var evaluationTimeZone: TimeZone

    /// Creates an evaluation context that projects temporal functions in UTC.
    public init(
        focus: [FHIRPathValue] = [],
        constants: [String: [FHIRPathValue]] = [:],
        evaluationInstant: Date
    ) {
        self.init(
            focus: focus,
            constants: constants,
            evaluationInstant: evaluationInstant,
            evaluationTimeZone: FHIRPathCalendar.utc
        )
    }

    /// Creates an evaluation context that projects temporal functions in an explicit time zone.
    public init(
        focus: [FHIRPathValue] = [],
        constants: [String: [FHIRPathValue]] = [:],
        evaluationInstant: Date,
        evaluationTimeZone: TimeZone
    ) {
        self.focus = focus
        self.constants = constants
        self.evaluationInstant = evaluationInstant
        self.evaluationTimeZone = evaluationTimeZone
        self.constants["ucum"] = [.string("http://unitsofmeasure.org")]
        if let resource = constants["resource"], self.constants["context"] == nil {
            self.constants["context"] = resource
        }
    }
}
