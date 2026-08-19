//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
extension Grove {
    /// Access the global Grove instance.
    ///
    /// Access the global Grove instance using the ``Module/Application`` property wrapper inside your ``Module``.
    ///
    /// Below is a short code example on how to access the Grove instance.
    ///
    /// ```swift
    /// class ExampleModule: Module {
    ///     @Application(\.grove)
    ///     var grove
    /// }
    /// ```
    public var grove: Grove {
        // this seems nonsensical, but is essential to support Grove access from the @Application modifier
        self
    }
}
