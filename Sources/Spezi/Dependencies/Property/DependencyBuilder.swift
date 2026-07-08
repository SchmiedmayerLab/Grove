//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A result builder to build a `DependencyCollection`.
///
/// For more information refer to ``DependencyCollection``.
@resultBuilder
public enum DependencyBuilder: DependencyCollectionBuilder {
    /// An auto-closure expression, providing the default dependency value, building the `DependencyCollection`.
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
    public static func buildExpression<M: Module>(_ expression: M) -> DependencyCollection {
        DependencyCollection(expression)
    }
}
