//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
@GroveBluetooth
final class KVOStateDidChangeObserver<Entity: NSObject, Value>: NSObject, Sendable {
    private var observation: NSKeyValueObservation?

    private let entity: Entity
    private let keyPath: KeyPath<Entity, Value>

    @GroveBluetooth
    init(entity: Entity, property: KeyPath<Entity, Value>, perform action: @GroveBluetooth @Sendable @escaping (Value) async -> Void) {
        self.entity = entity
        self.keyPath = property
        super.init()

        observation = entity.observe(property) { [weak self] _, _ in
            Task { @GroveBluetooth [weak self] in
                guard let self else {
                    return
                }
                let value = self.entity[keyPath: self.keyPath]
                await action(value)
            }
        }
    }
}
