//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A user-configured ``AccountKey``.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol AccountKeyConfiguration: CustomStringConvertible, CustomDebugStringConvertible, Identifiable, Hashable, Sendable
    where ID == ObjectIdentifier {
    /// The associated ``AccountKey``.
    associatedtype Key: AccountKey

    /// Access the ``AccountKey`` meta-type.
    var key: Key.Type { get }

    /// The requirement level that was defined for the ``AccountKey``.
    var requirement: AccountKeyRequirement { get }

    /// A user-friendly, human-readable string description that resembles the `KeyPath` description.
    var keyPathDescription: String { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
struct AccountKeyConfigurationImpl<Key: AccountKey>: AccountKeyConfiguration {
    let key: Key.Type
    let requirement: AccountKeyRequirement

    let keyPathDescription: String

    init(_ keyPath: KeyPath<AccountKeys, Key.Type>, requirement: AccountKeyRequirement) {
        self.key = Key.self
        self.requirement = requirement
        self.keyPathDescription = keyPath.shortDescription
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountKeyConfiguration {
    var keyWithDescription: any AccountKeyWithDescription {
        AccountKeyWithKeyPathDescription(key: key, description: keyPathDescription)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountKeyConfigurationImpl {
    var id: ObjectIdentifier {
        key.id
    }

    var description: String {
        switch requirement {
        case .required:
            return ".requires(\(keyPathDescription))"
        case .collected:
            return ".collects(\(keyPathDescription))"
        case .supported:
            return ".supports(\(keyPathDescription))"
        case .manual:
            return ".manual(\(keyPathDescription))"
        }
    }

    var debugDescription: String {
        description
    }


    static func == (lhs: AccountKeyConfigurationImpl<Key>, rhs: AccountKeyConfigurationImpl<Key>) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}
