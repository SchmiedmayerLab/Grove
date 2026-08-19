//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A type-safe wrapper around `UserDefaults`.
///
/// ## Topics
///
/// ### Static Properties
/// - ``standard``
///
/// ### Initializers
/// - ``init(defaults:)``
///
/// ### Accessing Data
/// - ``subscript(_:)->T``
/// - ``subscript(_:)->T?``
/// - ``hasEntry(for:)-(LocalPreferenceKey<Any>.Key)``
/// - ``hasEntry(for:)-(LocalPreferenceKey<Any>)``
/// - ``removeEntry(for:)-(LocalPreferenceKey<Any>.Key)``
/// - ``removeEntry(for:)-(LocalPreferenceKey<Any>)``
/// - ``removeAllEntries(in:)``
///
/// ### Migrations
/// - ``runMigrations(_:)``
/// - ``MigrateName``
/// - ``MigrateValue``
/// - ``Migration``
public struct LocalPreferencesStore: Hashable, @unchecked Sendable {
    /// The Local Preferences Store for `UserDefaults.standard`
    public static let standard = LocalPreferencesStore(defaults: .standard)
    
    @usableFromInline let defaults: UserDefaults
    
    /// Creates a Preferences Store for the specified `UserDefaults` suite.
    @inlinable
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }
}


// MARK: Operations

extension LocalPreferencesStore {
    /// Checks whether the store contains an entry for the specified key.
    @inlinable
    public func hasEntry(for key: LocalPreferenceKey<some Any>) -> Bool {
        hasEntry(for: key.key)
    }
    
    /// Checks whether the store contains an entry for the specified key.
    @inlinable
    public func hasEntry(for key: LocalPreferenceKey<some Any>.Key) -> Bool {
        defaults.hasEntry(for: key.value)
    }
    
    /// Checks whether the store contains any entry that falls into the specified namespace.
    ///
    /// - parameter namespace: The ``LocalPreferenceKeys/Namespace`` to check for. Must not be the global namespace.
    internal func hasEntry(in namespace: LocalPreferenceKeys.Namespace) -> Bool {
        guard !namespace.isGlobal else {
            assertionFailure("Passed global namespace to \(#function)")
            return !defaults.dictionaryRepresentation().isEmpty
        }
        let prefixes = [
            namespace.format(keyName: "", applyKVOCompatibilityFixes: true),
            namespace.format(keyName: "", applyKVOCompatibilityFixes: false)
        ]
        return defaults.dictionaryRepresentation().keys.contains { key in
            prefixes.contains { key.starts(with: $0) }
        }
    }
    
    /// Removes the entry for the specified key from the store.
    @inlinable
    public func removeEntry(for key: LocalPreferenceKey<some Any>) {
        removeEntry(for: key.key)
    }
    
    /// Removes the entry for the specified key from the store.
    @inlinable
    public func removeEntry(for key: LocalPreferenceKey<some Any>.Key) {
        defaults.removeObject(forKey: key.value)
    }
    
    /// Removes from the store all those entries which fall into the specified namespace.
    ///
    /// - parameter namespace: The ``LocalPreferenceKeys/Namespace`` whose entries should be removed. Must not be the global namespace.
    public func removeAllEntries(in namespace: LocalPreferenceKeys.Namespace) {
        guard !namespace.isGlobal else {
            assertionFailure("Passed global namespace to \(#function)")
            // in the case of the global namespace, we simply don't remove anything.
            return
        }
        let prefixes = [
            namespace.format(keyName: "", applyKVOCompatibilityFixes: true),
            namespace.format(keyName: "", applyKVOCompatibilityFixes: false)
        ]
        for key in defaults.dictionaryRepresentation().keys where prefixes.contains(where: { key.starts(with: $0) }) {
            defaults.removeObject(forKey: key)
        }
    }
    
    /// Accesses a ``LocalPreferenceKey``'s persisted value.
    @inlinable
    public subscript<T>(key: LocalPreferenceKey<T>) -> T {
        get {
            key.readOrDefault(in: defaults)
        }
        nonmutating set {
            try? key.write(newValue, in: defaults)
        }
    }
    
    /// Accesses a ``LocalPreferenceKey``'s persisted value.
    @_disfavoredOverload
    @inlinable
    public subscript<T>(key: LocalPreferenceKey<T>) -> T? { // we always return nonnil values, but allow nil-resetting
        get {
            key.readOrDefault(in: defaults)
        }
        nonmutating set {
            try? key.write(newValue, in: defaults)
        }
    }
}


extension UserDefaults {
    @inlinable
    func hasEntry(for key: String) -> Bool {
        object(forKey: key) != nil
    }
}
