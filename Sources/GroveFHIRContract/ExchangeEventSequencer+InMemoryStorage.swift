//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension ExchangeEventSequencer {
    /// A ledger that lives in this process only, and the reference implementation of the storage contract.
    ///
    /// Every launch starts empty and mints a new producer instance, so nothing is ever reused. Use it for
    /// tests, previews and single-process tools; share one instance to share one ledger across sequencers.
    /// A transaction holds one lock, reads the live map, buffers its writes and applies them only when
    /// `body` returns, so a throw commits nothing and a transaction costs what it touches.
    public final class InMemoryStorage: Storage, @unchecked Sendable { // `entries` is guarded by `lock`.
        /// One transaction: reads see the buffered writes first, then the live map.
        private final class Buffered: Transaction {
            unowned let storage: InMemoryStorage
            /// `nil` removes the key at commit.
            var writes: [String: Data?] = [:]
            var isOpen = true

            init(storage: InMemoryStorage) {
                self.storage = storage
            }

            func read(_ key: String) throws -> Data? {
                precondition(isOpen, "A ledger transaction is used only inside its body.")
                if let write = writes[key] {
                    return write
                }
                return storage.entries[key]
            }

            func write(_ value: Data, for key: String) throws {
                precondition(isOpen, "A ledger transaction is used only inside its body.")
                writes[key] = .some(value)
            }

            func remove(_ key: String) throws {
                precondition(isOpen, "A ledger transaction is used only inside its body.")
                writes[key] = .some(nil)
            }

            func keys(prefixedBy prefix: String) throws -> [String] {
                precondition(isOpen, "A ledger transaction is used only inside its body.")
                var keys = Set(storage.entries.keys.filter { $0.hasPrefix(prefix) })
                for (key, value) in writes where key.hasPrefix(prefix) {
                    if value == nil {
                        keys.remove(key)
                    } else {
                        keys.insert(key)
                    }
                }
                return Array(keys)
            }
        }

        private let lock = NSLock()
        private var entries: [String: Data] = [:]

        /// An empty ledger.
        public init() {}

        public func transaction<R>(_ body: (any Transaction) throws -> R) throws -> R {
            lock.lock()
            defer {
                lock.unlock()
            }
            let transaction = Buffered(storage: self)
            defer {
                transaction.isOpen = false
            }
            let result = try body(transaction)
            for (key, value) in transaction.writes {
                entries[key] = value
            }
            return result
        }
    }
}
