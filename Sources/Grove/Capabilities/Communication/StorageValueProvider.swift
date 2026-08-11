//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation


/// An adopter of this protocol is a property of a ``Module`` that provides mechanisms to communicate
/// data with other ``Module``s.
///
/// Data provided through a Storage Value Provider can be retrieved through a ``_StorageValueCollector``.
@available(iOS 18, macOS 15, watchOS 11, *)
protocol StorageValueProvider: GrovePropertyWrapper {
    /// This method is called to collect all provided values into the given ``GroveStorage`` repository.
    /// - Parameter repository: Provides access to the ``GroveStorage`` repository.
    @MainActor
    func collect<Repository: SharedRepository<GroveAnchor>>(into repository: inout Repository)
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Module {
    var storageValueProviders: [any StorageValueProvider] {
        retrieveProperties(ofType: (any StorageValueProvider).self)
    }

    @MainActor
    func collectModuleValues<Repository: SharedRepository<GroveAnchor>>(into repository: inout Repository) {
        for provider in storageValueProviders {
            provider.collect(into: &repository)
        }
    }
}
