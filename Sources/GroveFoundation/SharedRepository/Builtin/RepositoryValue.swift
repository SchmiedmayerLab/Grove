//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Represents type erased `RepositoryValue`.
///
/// Refer to ``RepositoryValue``.
public protocol AnyRepositoryValue {
    /// This property gives access to a type-erased version of `Source`.
    var anySource: any KnowledgeSource.Type { get }
    /// This property gives access to a type-erased version of ``RepositoryValue/value``.
    var anyValue: Any { get }
}


/// A stored value in a shared repository.
///
/// This container type contains the stored value an type information of the associated ``KnowledgeSource``.
public struct RepositoryValue<Source: KnowledgeSource> {
    /// The value of the knowledge source.
    public let value: Source.Value

    /// Initialize a new repository value.
    /// - Parameter value: The value instance.
    init(_ value: Source.Value) {
        self.value = value
    }
}


extension RepositoryValue: AnyRepositoryValue {}


extension RepositoryValue: Sendable where Source.Value: Sendable {}


extension RepositoryValue {
    /// The type erased `Source`.
    public var anySource: any KnowledgeSource.Type {
        Source.self
    }

    /// The type erased ``RepositoryValue/value``.
    public var anyValue: Any {
        value
    }
}
