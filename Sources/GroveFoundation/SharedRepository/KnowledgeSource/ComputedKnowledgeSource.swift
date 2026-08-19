//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A ``KnowledgeSource`` that allows to compose it's values from it's surrounding knowledge environment.
public protocol ComputedKnowledgeSource<Anchor, Repository>: SomeComputedKnowledgeSource, SendableMetatype {
    associatedtype Repository

    /// Computes the value of the ``KnowledgeSource``.
    ///
    /// - Note: The implementation of this method must be deterministic.
    /// - Parameter repository: The repository to use for computation.
    /// - Returns: Returns the computed value.
    @Sendable
    static func compute(from repository: Repository) -> Value
}
