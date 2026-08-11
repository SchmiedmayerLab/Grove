//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A `KnowledgeSource` serves as a typed key for a ``SharedRepository`` implementation.
///
/// A ``KnowledgeSource`` is anchored to a given ``RepositoryAnchor`` and defines a ``Value`` type which by default
/// is set to `Self`.
public protocol KnowledgeSource<Anchor>: SendableMetatype {
    /// The type of a value this `KnowledgeSource` represents.
    associatedtype Value = Self
    /// The ``RepositoryAnchor`` to which this `KnowledgeSource` is anchored to.
    associatedtype Anchor: RepositoryAnchor
}
