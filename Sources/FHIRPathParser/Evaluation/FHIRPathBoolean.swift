//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A truth value in FHIRPath's three-valued logic.
///
/// Anything derived from an empty collection is ``empty`` rather than ``false``: `{} = 1`
/// and `{} and true` both yield `{}`, so operators and filters have to keep the third state.
public enum FHIRPathBoolean: Hashable, Sendable {
    /// The expression held.
    case `true`
    /// The expression did not hold.
    case `false`
    /// The expression evaluated to an empty collection, which is neither.
    case empty

    init(_ value: Bool) {
        self = value ? .true : .false
    }
}
