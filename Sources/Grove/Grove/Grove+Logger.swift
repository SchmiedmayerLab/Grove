//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Grove {
    /// Access the application logger.
    ///
    /// Access the global Grove Logger. If used with ``Module/Application`` property wrapper you can create and access your module-specific `Logger`.
    ///
    /// Below is a short code example on how to create and access your module-specific `Logger`.
    ///
    /// ```swift
    /// class ExampleModule: Module {
    ///     @Application(\.logger)
    ///     var logger
    ///
    ///     func configure() {
    ///         logger.info("\(Self.self) is getting configured...")
    ///     }
    /// }
    /// ```
    public var logger: Logger {
        if let module = Grove.moduleInitContext {
            return Logger(subsystem: "org.grovealliance.modules", category: module.loggerCategory)
        }
        return Grove.logger
    }
}
