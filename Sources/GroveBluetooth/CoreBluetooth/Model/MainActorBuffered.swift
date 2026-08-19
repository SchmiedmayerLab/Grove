//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
final class MainActorBuffered<Value: Sendable>: Sendable {
    nonisolated(unsafe) private var unsafeValue: Value
    @MainActor private(set) var mainActorValue: Value?

    init(_ value: Value) {
        self.unsafeValue = value
        self.mainActorValue = value
    }

    func loadUnsafe() -> Value {
        loadIfMainActor() ?? unsafeValue
    }

    func load(using lock: borrowing Mutex<Void>) -> Value {
        loadIfMainActor() ?? lock.withLock { _ in
            unsafeValue
        }
    }

    private func loadIfMainActor() -> Value? {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                mainActorValue
            }
        } else {
            nil
        }
    }

    private func _store(_ newValue: Value, mutation: sending @MainActor @escaping (@MainActor () -> Void) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                let valueMutation = { @MainActor in
                    self.mainActorValue = newValue
                }
                mutation(valueMutation)
            }
        } else {
            let valueMutation = { @MainActor in
                self.mainActorValue = newValue
            }
            Task { @MainActor in
                mutation(valueMutation)
            }
        }
    }

    func store(_ newValue: Value, using lock: borrowing Mutex<Void>, mutation: sending @MainActor @escaping (@MainActor () -> Void) -> Void) {
        lock.withLock { _ in
            unsafeValue = newValue
        }
        _store(newValue, mutation: mutation)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension MainActorBuffered where Value: Equatable {
    func storeAndCompare(
        _ newValue: Value,
        using lock: borrowing Mutex<Void>,
        mutation: sending @MainActor @escaping (@MainActor () -> Void) -> Void
    ) -> Bool {
        let didChange = lock.withLock { _ in
            let didChange = unsafeValue != newValue
            unsafeValue = newValue
            return didChange
        }
        _store(newValue, mutation: mutation)

        return didChange
    }
}
