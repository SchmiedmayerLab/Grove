//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import GroveLocalStorage


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    // Essentially just a thread-safe dictionary that keeps track of our `LocalStorageKey`s used by the `SampleTypeScopedLocalStorage`.
    // The reason this exists is bc the LocalStorage API is intended to be used with long-lived LocalStorageKey objects, which doesn't easily
    // work with the multi-key scoping approach we're using here.
    // Were we not to use something like this for caching and re-using the keys, we'd need to create temporary `LocalStorageKey`s for
    // every load/store operation, which would of course work but would also defeat the whole purpose of having the `LocalStorageKey`s
    // be long-lived objects which are also used for e.g. locking / properly handling concurrent reads or writes.
    final class LocalStorageKeysStore<Key: Hashable, Value>: Sendable {
        private struct DictKey: Hashable {
            let key: Key
            let valueType: String
            
            init(key: Key) {
                self.key = key
                // this is fine bc we're not using it as a stable identifier
                // (the `valueType` key must only be valid&unique for the lifetime of the app)
                self.valueType = String(reflecting: Value.self)
            }
        }
        
        private let makeStorageKey: @Sendable (Key) -> LocalStorageKey<Value>
        
        private let lock = RWLock()
        nonisolated(unsafe) private var keys: [DictKey: LocalStorageKey<Value>] = [:]
        
        init(makeStorageKey: @escaping @Sendable (Key) -> LocalStorageKey<Value>) {
            self.makeStorageKey = makeStorageKey
        }
        
        func storageKey(for key: Key) -> LocalStorageKey<Value> {
            lock.withWriteLock {
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
    
    
    /// A read-write "view" into a `LocalStorage`.
    struct ScopedLocalStorage<Key: Hashable, Value: SendableMetatype>: Sendable {
        private let localStorage: LocalStorage
        private let localStorageKeysStore: LocalStorageKeysStore<Key, Value>
        
        init(localStorage: LocalStorage, localStorageKeysStore: LocalStorageKeysStore<Key, Value>) {
            self.localStorage = localStorage
            self.localStorageKeysStore = localStorageKeysStore
        }
        
        private func storageKey(for key: Key) -> LocalStorageKey<Value> {
            localStorageKeysStore.storageKey(for: key)
        }
        
        subscript(key: Key) -> Value? {
            get {
                try? localStorage.load(storageKey(for: key))
            }
            nonmutating set {
                try? localStorage.store(newValue, for: storageKey(for: key))
            }
        }
    }
}
