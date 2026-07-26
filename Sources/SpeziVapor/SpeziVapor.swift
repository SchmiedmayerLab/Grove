//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(APISupport) import Spezi
import Vapor


/// A namespace for configuring and accessing Spezi from within a Vapor application.
///
/// `SpeziVapor` provides the integration layer between Spezi and Vapor.
/// Use it during application startup to configure your Spezi standard and modules, and use it at runtime to retrieve configured modules from either the `Application` or `Request` context.
///
/// ## Configuration
///
/// Configure Spezi in your Vapor application's `configure` function:
///
/// ```swift
/// func configure(_ app: Application) throws {
///     app.spezi.configure(standard: MyStandard()) {
///         ModuleA()
///         ModuleB()
///     }
/// }
/// ```
///
/// ## Accessing Modules
///
/// Modules can be retrieved by type once Spezi is configured.
///
/// ### From Application
///
/// ```swift
/// let myModule = app.spezi[MyModule.self]
/// ```
///
/// ### From Request
///
/// ```swift
/// let myModule = req.spezi[MyModule.self]
/// ```
@available(macOS 26, iOS 26, watchOS 26, tvOS 26, visionOS 26, *)
public struct SpeziVapor: Sendable {
    private enum SpeziStorageKey: StorageKey {
        typealias Value = Spezi
    }
    
    private let application: Application
    
    public var spezi: Spezi {
        guard let spezi = application.storage[SpeziStorageKey.self] else {
            preconditionFailure("Spezi not configured. Ensure Spezi is added to Application storage before use.")
        }
        return spezi
    }

    init(application: Application) {
        self.application = application
    }
    
    init(request: Request) {
        self.application = request.application
    }
    
    /// Configures Spezi with a custom standard and a collection of modules.
    ///
    /// Call this method once during application startup to initialize Spezi.
    ///
    /// - Parameters:
    ///   - standard: The standard to use for Spezi configuration.
    ///   - modules: A result builder closure that returns the modules to configure.
    @MainActor
    public func configure<S: Standard>(standard: S, @ModuleBuilder _ modules: () -> ModuleCollection) {
        application.storage[SpeziStorageKey.self] = Spezi(from: Configuration(standard: standard, modules))
        Task.immediate {
            await spezi.run()
        }
    }

    /// Configures Spezi with the default standard and a collection of modules.
    ///
    /// Call this method once during application startup to initialize Spezi.
    ///
    /// - Parameter modules: A result builder closure that returns the modules to configure.
    @MainActor
    public func configure(@ModuleBuilder _ modules: () -> ModuleCollection) {
        configure(standard: DefaultStandard(), modules)
    }
    
    /// Accesses a configured module by its type.
    ///
    /// - Parameter type: The type of the module to retrieve.
    /// - Returns: The configured module instance.
    /// - Precondition: The module must be configured, otherwise a `preconditionFailure` is triggered.
    public subscript<M: Module & Sendable>(_: M.Type) -> M {
        guard let module: M = self[M?.self] else {
            preconditionFailure("Module \(M.self) not configured in Spezi.")
        }
        return module
    }
    
    /// Optionally accesses a configured module by its type.
    ///
    /// - Parameter type: The optional type of the module to retrieve.
    /// - Returns: The configured module instance, or `nil` if not configured.
    public subscript<M: Module & Sendable>(_: M?.Type) -> M? {
        spezi.module(M.self)
    }
}
