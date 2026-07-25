//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziVapor
import VaporTesting

/// Configure a Vapor `Application` with Spezi for testing purposes.
///
/// This method can be used in unit tests to bootstrap a Vapor application and resolve Spezi dependencies.
///
/// - Parameters:
///   - routes: An optional closure to register routes on the application.
///   - standard: The Spezi [`Standard`](https://swiftpackageindex.com/stanfordspezi/spezi/documentation/spezi/standard) to initialize.
///   - modules: The collection of [`Module`](https://swiftpackageindex.com/stanfordspezi/spezi/documentation/spezi/module)s to configure.
///   - test: An async closure that receives the configured `Application` for testing.
/// - Throws: Any error thrown during configuration, route registration, or execution of the test closure
@MainActor
func withSpeziVaporApp(
    routes: ((_ app: Application) throws -> Void)? = nil,
    standard: any Standard,
    @ModuleBuilder modules: () -> ModuleCollection,
    _ test: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        app.spezi.configure(standard: standard, modules)
        try routes?(app)
        try await test(app)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

/// Configure a Vapor `Application` with Spezi using the `DefaultStandard`.
///
/// This method can be used in unit tests to bootstrap a Vapor application and resolve Spezi dependencies.
///
/// - Parameters:
///   - routes: An optional closure to register routes on the application.
///   - modules: The collection of [`Module`](https://swiftpackageindex.com/stanfordspezi/spezi/documentation/spezi/module)s to configure.
///   - test: An async closure that receives the configured `Application` for testing.
/// - Throws: Any error thrown during configuration, route registration, or execution of the test closure.
@MainActor
func withSpeziVaporApp(
    routes: ((_ app: Application) throws -> Void)? = nil,
    @ModuleBuilder modules: () -> ModuleCollection,
    _ test: (Application) async throws -> Void
) async throws {
    try await withSpeziVaporApp(routes: routes, standard: DefaultStandard(), modules: modules, test)
}
