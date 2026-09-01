//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveLocalStorage
import Synchronization


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    // Essentially just a thread-safe dictionary that keeps track of our `LocalStorageKey`s used by `SensorKit.queryAnchorKeys`.
    // The reason this exists is bc the LocalStorage API is intended to be used with long-lived LocalStorageKey objects, which doesn't easily
    // work with the multi-key scoping approach we're using here.
    // Were we not to use something like this for caching and re-using the keys, we'd need to create temporary `LocalStorageKey`s for
    // every load/store operation, which would of course work but would also defeat the whole purpose of having the `LocalStorageKey`s
    // be long-lived objects which are also used for e.g. locking / properly handling concurrent reads or writes.
    final class LocalStorageKeysStore<Key: Hashable, Value>: Sendable {
        private struct DictKey: Hashable {
            // periphery:ignore - read by the synthesized Hashable of this dictionary key
            let key: Key
            // periphery:ignore - read by the synthesized Hashable of this dictionary key
            let valueType: String
            
            init(key: Key) {
                self.key = key
                // this is fine bc we're not using it as a stable identifier
                // (the `valueType` key must only be valid&unique for the lifetime of the app)
                self.valueType = String(reflecting: Value.self)
            }
        }
        
        private let makeStorageKey: @Sendable (Key) -> LocalStorageKey<Value>
        
        // `Key` is not `Sendable`, so the lock cannot own the dictionary.
        private let lock = Mutex<Void>(())
        nonisolated(unsafe) private var keys: [DictKey: LocalStorageKey<Value>] = [:]

        /// Every key materialized by this store in the current process.
        ///
        /// Reset operations use this to fence an in-flight query whose default anchor has not yet
        /// produced an on-disk LocalStorage entry.
        var allKeys: [Key] {
            lock.withLock { _ in
                keys.keys.map(\.key)
            }
        }
        
        init(makeStorageKey: @escaping @Sendable (Key) -> LocalStorageKey<Value>) {
            self.makeStorageKey = makeStorageKey
        }
        
        func storageKey(for key: Key) -> LocalStorageKey<Value> {
            lock.withLock { _ in
                let dictKey = DictKey(key: key)
                if let storageKey = keys[dictKey] {
                    return storageKey
                } else {
                    let storageKey = makeStorageKey(key)
                    keys[dictKey] = storageKey
                    return storageKey
                }
            }
        }
    }
}
