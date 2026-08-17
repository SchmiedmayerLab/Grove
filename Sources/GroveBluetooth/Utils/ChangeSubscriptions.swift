//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import OrderedCollections


final class ChangeSubscriptions<Value: Sendable>: Sendable {
    private struct Registration: Sendable {
        let subscription: AsyncStream<Value>
        let id: UUID
    }

    nonisolated(unsafe) private var continuations: OrderedDictionary<UUID, AsyncStream<Value>.Continuation> = [:]
    private let lock = NSLock()

    nonisolated init() {}

    func notifySubscribers(with value: Value, ignoring: Set<UUID> = []) {
        lock.withLock {
            for (id, continuation) in continuations where !ignoring.contains(id) {
                continuation.yield(value)
            }
        }
    }

    func notifySubscriber(id: UUID, with value: Value) {
        lock.withLock {
            _ = continuations[id]?.yield(value)
        }
    }

    nonisolated private func _newSubscription() -> Registration {
        let id = UUID()
        let stream = AsyncStream { continuation in
            lock.withLock {
                self.continuations[id] = continuation
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }

                self.lock.withLock {
                    _ = self.continuations.removeValue(forKey: id)
                }
            }
        }

        return Registration(subscription: stream, id: id)
    }

    nonisolated func newSubscription() -> AsyncStream<Value> {
        _newSubscription().subscription
    }

    @discardableResult
    nonisolated func newOnChangeSubscription(
        perform action: @escaping @Sendable (_ oldValue: Value, _ newValue: Value) async -> Void
    ) -> UUID {
        let registration = _newSubscription()

        // avoid accidentally inheriting any task local values
        Task.detached { @Sendable @GroveBluetooth [weak self] in
            var currentValue: Value?

            for await element in registration.subscription {
                guard self != nil else {
                    return
                }

                await action(currentValue ?? element, element)
                currentValue = element
            }
        }

        // There is no need to save this Task handle (makes it easier for use as we are in an non-isolated context right here).
        // The task will automatically cleanup itself, once it the AsyncStream is getting cancelled/finished.

        return registration.id
    }

    deinit {
        lock.withLock {
            for continuation in continuations.values {
                continuation.finish()
            }

            continuations.removeAll()
        }
    }
}
