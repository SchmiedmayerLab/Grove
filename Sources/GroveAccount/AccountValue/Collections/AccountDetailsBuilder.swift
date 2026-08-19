//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation


/// A class-based builder interface for `AccountDetails` that can be passed around the view hierarchy.
///
/// This type allows to easily build and modify an instance of ``AccountDetails``.
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
class AccountDetailsBuilder {
    var storage: AccountDetails
    var defaultValues: AccountDetails

    /// Initialize a new empty builder.
    init() {
        self.storage = AccountDetails()
        self.defaultValues = AccountDetails()
    }


    /// Clear the builder's contents.
    func clear() {
        storage = .init()
    }

    /// Retrieve the current value stored in the builder.
    /// - Parameter key: The ``AccountKey`` metatype.
    /// - Returns: The value is present.
    func get<Key: AccountKey>(_ key: Key.Type) -> Key.Value? {
        storage[Key.self]
    }

    /// Store a new value in the builder.
    /// - Parameters:
    ///   - key: The ``AccountKey`` metatype.
    ///   - value: The value to store.
    /// - Returns: The builder reference for method chaining.
    @discardableResult
    func set<Key: AccountKey>(_ key: Key.Type, value: Key.Value) -> Self {
        storage.set(key, value: value)
        return self
    }

    @discardableResult
    func set<Key: AccountKey>(_ key: Key.Type, defaultValue value: Key.Value) -> Self {
        defaultValues.set(key, value: value)
        return self
    }

    /// Remove a value from the builder.
    /// - Parameter key: The ``AccountKey`` metatype.
    /// - Returns: The builder reference for method chaining.
    @discardableResult
    func remove<Key: AccountKey>(_ key: Key.Type) -> Self {
        storage.remove(key)
        return self
    }

    // periphery:ignore - generic counterpart of the existential overload below
    /// Checks if a value for a ``AccountKey`` is present in the builder.
    /// - Parameter key: The ``AccountKey`` metatype to check if a value exists.
    /// - Returns: Returns `true` if present, otherwise `false`.
    func contains<Key: AccountKey>(_ key: Key.Type) -> Bool {
        storage.contains(Key.self)
    }

    /// Checks if a value for a ``AccountKey`` is present in the builder.
    /// - Parameter key: The ``AccountKey`` metatype to check if a value exists.
    /// - Returns: Returns `true` if present, otherwise `false`.
    func contains(_ key: any AccountKey.Type) -> Bool {
        storage.contains(key)
    }

    /// Build a new storage instance.
    /// - Returns: The built ``AccountValues``.
    func build() -> AccountDetails {
        if !defaultValues.isEmpty {
            storage.add(contentsOf: defaultValues, merge: false)
            return storage
        } else {
            return storage
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountDetailsBuilder: Collection {
    typealias Index = AccountStorage.Index

    var startIndex: Index {
        storage.startIndex
    }

    var endIndex: Index {
        storage.endIndex
    }


    func index(after index: Index) -> Index {
        storage.index(after: index)
    }


    subscript(position: Index) -> any AnyRepositoryValue {
        storage[position]
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountDetailsBuilder {
    @discardableResult
    func setEmptyValue(for accountKey: any AccountKey.Type) -> Self {
        accountKey.setEmpty(in: self)
        return self
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountKey {
    fileprivate static func setEmpty(in builder: AccountDetailsBuilder) {
        builder.set(Self.self, value: initialValue.value)
    }
}
