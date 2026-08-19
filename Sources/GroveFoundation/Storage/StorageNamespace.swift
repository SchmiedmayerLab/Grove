//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The container that persisted framework state lives in.
///
/// Storage is scoped to the consuming application, never to the framework, so that no vendor or
/// product name appears in a path on disk.
///
/// ```swift
/// let directory = try StorageNamespace.app.directory(.scheduler)
/// ```
///
/// ## Topics
///
/// ### Namespaces
/// - ``app``
/// - ``appGroup(_:)``
/// - ``custom(_:)``
///
/// ### Locating Storage
/// - ``Component``
/// - ``containerURL()``
/// - ``directory(_:)``
public struct StorageNamespace: Hashable, Sendable {
    private enum Kind: Hashable, Sendable {
        case app
        case appGroup(String)
        case custom(String)
    }

    /// Scopes storage to the current application.
    public static var app: Self {
        Self(kind: .app)
    }

    private let kind: Kind

    /// Scopes storage to a shared app group container, so a host app and its extensions see the same data.
    ///
    /// - Parameter identifier: The app group identifier, as declared in the app's entitlements.
    public static func appGroup(_ identifier: String) -> Self {
        Self(kind: .appGroup(identifier))
    }

    /// Scopes storage to an explicit identifier.
    ///
    /// Use this in tests and in command-line tools, which have no bundle identifier of their own.
    public static func custom(_ identifier: String) -> Self {
        Self(kind: .custom(identifier))
    }
}


extension StorageNamespace {
    /// A directory within a ``StorageNamespace``, owned by one module.
    ///
    /// Declare components in an extension on this type:
    /// ```swift
    /// extension StorageNamespace.Component {
    ///     static let scheduler = Self("Scheduler")
    /// }
    /// ```
    public struct Component: Hashable, Sendable, CustomStringConvertible {
        /// The directory's name.
        public let name: String

        public var description: String {
            name
        }

        /// Creates a component.
        ///
        /// - Parameter name: A single path component. Must not be empty or contain a path separator.
        public init(_ name: String) {
            precondition(
                !name.isEmpty && !name.contains("/"),
                "A StorageNamespace.Component must be a single non-empty path component, got '\(name)'."
            )
            self.name = name
        }
    }
}


extension StorageNamespace {
    /// An error preventing a ``StorageNamespace`` from resolving to a directory.
    public enum ResolutionError: Error, CustomStringConvertible {
        /// The current process has no bundle identifier, so ``StorageNamespace/app`` cannot be resolved.
        case noBundleIdentifier
        /// The app group container was unavailable, usually because the entitlement is missing.
        case appGroupUnavailable(String)

        public var description: String {
            switch self {
            case .noBundleIdentifier:
                """
                StorageNamespace.app requires a bundle identifier, and this process has none. \
                Tests and command-line tools must pass an explicit namespace, e.g. \
                StorageNamespace.custom("com.example.tests").
                """
            case .appGroupUnavailable(let identifier):
                "The app group container '\(identifier)' is unavailable. Check the app's entitlements."
            }
        }
    }

    /// The root directory for this namespace.
    ///
    /// Resolution is pure: nothing is created. Call ``createDirectory(_:)`` when the directory has to
    /// exist — relocating a store into a directory that was created first cannot use an atomic rename.
    ///
    /// - Returns: A directory under `Library/Application Support`, which is where app-created data the
    ///     user does not manipulate directly belongs.
    public func containerURL() throws -> URL {
        switch kind {
        case .app:
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                throw ResolutionError.noBundleIdentifier
            }
            return try applicationSupportURL().appendingPathComponent(bundleIdentifier, isDirectory: true)
        case .appGroup(let identifier):
            #if canImport(Darwin)
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw ResolutionError.appGroupUnavailable(identifier)
            }
            return container
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            #else
            throw ResolutionError.appGroupUnavailable(identifier)
            #endif
        case .custom(let identifier):
            return try applicationSupportURL().appendingPathComponent(identifier, isDirectory: true)
        }
    }

    /// The directory a module's persisted state lives in.
    ///
    /// Resolution is pure; see ``containerURL()``.
    ///
    /// - Parameter component: The module's component.
    /// - Returns: `<container>/<component>`.
    public func directory(_ component: Component) throws -> URL {
        try containerURL().appendingPathComponent(component.name, isDirectory: true)
    }

    /// Creates a module's directory, and every directory above it.
    ///
    /// - Parameter component: The module's component.
    /// - Returns: The directory, which now exists.
    @discardableResult
    public func createDirectory(_ component: Component) throws -> URL {
        let url = try directory(component)
        // Application Support is not created by default inside an iOS app container.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // `URL.applicationSupportDirectory` is iOS 16+; the deployment floor is iOS 15.
    private func applicationSupportURL() throws -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let url = urls.first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
