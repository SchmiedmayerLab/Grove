//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The descendants of named constants, walked once for as long as the constants stay what they are.
///
/// `%resource.descendants()` opens nearly every SDC expression, and a form evaluates dozens of them against one
/// response; the caller that knows when the response changes hands a fresh cache to each context it builds.
public final class FHIRPathDescendantsCache: @unchecked Sendable {
    private let constants: Set<String>
    /// Keeps the constants this cache does not, for longer: a questionnaire outlives every state of its answers.
    private let parent: FHIRPathDescendantsCache?
    private let lock = NSLock()
    private var descendants: [String: [FHIRPathValue]] = [:]

    /// - parameters:
    ///   - constants: The names whose values stay the same for the cache's lifetime.
    ///   - parent: Where the other names are kept, if anywhere.
    public init(constants: Set<String>, parent: FHIRPathDescendantsCache? = nil) {
        self.constants = constants
        self.parent = parent
    }

    /// Whether the constant's descendants are kept here or further up.
    func keeps(_ name: String) -> Bool {
        constants.contains(name) || parent?.keeps(name) == true
    }

    func descendants(of name: String, _ walk: () throws -> [FHIRPathValue]) rethrows -> [FHIRPathValue] {
        if !constants.contains(name), let parent {
            return try parent.descendants(of: name, walk)
        }
        if let known = lock.withLock({ descendants[name] }) {
            return known
        }
        let walked = try walk()
        lock.withLock {
            descendants[name] = walked
        }
        return walked
    }
}


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
    /// Where `%constant.descendants()` is kept between evaluations over the same constants, when the caller has one.
    public var descendants: FHIRPathDescendantsCache?

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
