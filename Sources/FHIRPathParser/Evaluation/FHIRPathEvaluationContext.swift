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
    /// The instant used for `now()`/`today()`/`timeOfDay()`, so evaluation is reproducible.
    public var now: Date

    public init(focus: [FHIRPathValue] = [], constants: [String: [FHIRPathValue]] = [:], now: Date = Date()) {
        self.focus = focus
        self.constants = constants
        self.now = now
        self.constants["ucum"] = [.string("http://unitsofmeasure.org")]
        if let resource = constants["resource"], self.constants["context"] == nil {
            self.constants["context"] = resource
        }
    }
}
