//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Dispatch
import Foundation
import GroveFHIRContract


/// A serializable storage whose transactions overlap, as an SQL engine's serializable isolation lets them: each
/// attempt reads a snapshot and buffers its writes, and commits only if no transaction that committed after its
/// snapshot wrote a key it read or listed; otherwise it runs `body` again. It meets C1 to C5 in one process.
final class OptimisticStorage: ExchangeProducer.Storage, @unchecked Sendable { // State is guarded by `lock`.
    private final class Attempt: ExchangeProducer.Transaction {
        let snapshot: [String: Data]
        var writes: [String: Data?] = [:]
        var reads: Set<String> = []
        var prefixes: [String] = []

        init(snapshot: [String: Data]) {
            self.snapshot = snapshot
        }

        func read(_ key: String) throws -> Data? {
            reads.insert(key)
            if let write = writes[key] {
                return write
            }
            return snapshot[key]
        }

        func write(_ value: Data, for key: String) throws {
            writes[key] = .some(value)
        }

        func remove(_ key: String) throws {
            writes[key] = .some(nil)
        }

        func keys(prefixedBy prefix: String) throws -> [String] {
            prefixes.append(prefix)
            var keys = Set(snapshot.keys.filter { $0.hasPrefix(prefix) })
            for (key, value) in writes where key.hasPrefix(prefix) {
                if value == nil {
                    keys.remove(key)
                } else {
                    keys.insert(key)
                }
            }
            return Array(keys)
        }

        func conflicts(with written: Set<String>) -> Bool {
            written.contains { key in reads.contains(key) || prefixes.contains { key.hasPrefix($0) } }
        }
    }

    /// Signalled when the gated transaction has run its body and waits to validate and commit.
    let entered = DispatchSemaphore(value: 0)
    /// Lets the gated transaction validate and commit.
    let proceed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var entries: [String: Data] = [:]
    /// The keys each commit wrote, by the version it produced.
    private var commits: [(version: Int, keys: Set<String>)] = []
    private var version = 0
    private var gateNext = false

    /// Pauses the next transaction after its body, before it validates and commits.
    func gate() {
        lock.lock()
        defer {
            lock.unlock()
        }
        gateNext = true
    }

    func transaction<R>(_ body: (any ExchangeProducer.Transaction) throws -> R) throws -> R {
        lock.lock()
        var gated = gateNext
        gateNext = false
        lock.unlock()
        while true {
            lock.lock()
            let attempt = Attempt(snapshot: entries)
            let start = version
            lock.unlock()
            let result = try body(attempt)
            if gated {
                gated = false
                entered.signal()
                proceed.wait()
            }
            lock.lock()
            defer {
                lock.unlock()
            }
            // Only the commits after this attempt's snapshot, newest first.
            let later = commits.reversed().prefix { $0.version > start }
            guard !later.contains(where: { attempt.conflicts(with: $0.keys) }) else {
                continue
            }
            for (key, value) in attempt.writes {
                entries[key] = value
            }
            version += 1
            commits.append((version, Set(attempt.writes.keys)))
            return result
        }
    }
}
