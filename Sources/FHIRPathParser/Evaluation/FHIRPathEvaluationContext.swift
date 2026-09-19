//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Synchronization


/// The descendants of named constants, walked once for as long as the constants stay what they are.
///
/// `%resource.descendants()` opens nearly every SDC expression, and a form evaluates dozens of them against one
/// response; the caller that knows when the response changes hands a fresh cache to each context it builds.
@available(iOS 18, macOS 15, watchOS 11, *)
package final class FHIRPathDescendantsCache: Sendable {
    private struct State {
        var descendants: [String: [FHIRPathValue]] = [:]
        /// Per constant and member, where in the descendants each string value of that member is found.
        var positions: [String: [String: [String: [Int]]]] = [:]
    }

    private let constants: Set<String>
    /// Keeps the constants this cache does not, for longer: a questionnaire outlives every state of its answers.
    private let parent: FHIRPathDescendantsCache?
    private let state = Mutex(State())

    /// - parameters:
    ///   - constants: The names whose values stay the same for the cache's lifetime.
    ///   - parent: Where the other names are kept, if anywhere.
    package init(constants: Set<String>, parent: FHIRPathDescendantsCache? = nil) {
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
        if let known = state.withLock({ $0.descendants[name] }) {
            return known
        }
        let walked = try walk()
        state.withLock {
            $0.descendants[name] = walked
        }
        return walked
    }

    /// The descendants whose `member` is one string among `literals`, in document order: what
    /// `%constant.descendants().where(member = 'literal')` selects, found through an index of the member
    /// built on the first such ask rather than by filtering every descendant on each.
    func descendants(
        of name: String,
        whose member: String,
        isAmong literals: Set<String>,
        _ walk: () throws -> [FHIRPathValue]
    ) rethrows -> [FHIRPathValue] {
        if !constants.contains(name), let parent {
            return try parent.descendants(of: name, whose: member, isAmong: literals, walk)
        }
        let all = try descendants(of: name, walk)
        let index = state.withLock { $0.positions[name]?[member] } ?? {
            var built: [String: [Int]] = [:]
            for (position, value) in all.enumerated() {
                if let string = MemberFilter.string(member, of: value) {
                    built[string, default: []].append(position)
                }
            }
            state.withLock {
                $0.positions[name, default: [:]][member] = built
            }
            return built
        }()
        let found = literals.flatMap { index[$0] ?? [] }
        return (literals.count > 1 ? found.sorted() : found).map { all[$0] }
    }
}


/// The environment a FHIRPath expression is evaluated in: the input collection
/// (`$this` at the root) plus named `%constants` such as `%resource`.
@available(iOS 18, macOS 15, watchOS 11, *)
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
    package var descendants: FHIRPathDescendantsCache?

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
