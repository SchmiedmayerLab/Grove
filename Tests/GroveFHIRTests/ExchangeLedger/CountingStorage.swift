//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


/// Counts the transactions a storage runs and the reads, writes, removals and listings inside them, in total over
/// every key: the cost bounds the tests state are totals.
final class CountingStorage: ExchangeProducer.Storage, @unchecked Sendable { // `counts` is guarded by `lock`.
    struct Counts: Equatable {
        var transactions = 0
        var reads = 0
        var writes = 0
        var removals = 0
        var listings = 0
    }

    private struct Counting: ExchangeProducer.Transaction {
        let base: any ExchangeProducer.Transaction
        let storage: CountingStorage

        func read(_ key: String) throws -> Data? {
            storage.count { $0.reads += 1 }
            return try base.read(key)
        }

        func write(_ value: Data, for key: String) throws {
            storage.count { $0.writes += 1 }
            try base.write(value, for: key)
        }

        func remove(_ key: String) throws {
            storage.count { $0.removals += 1 }
            try base.remove(key)
        }

        func keys(prefixedBy prefix: String) throws -> [String] {
            storage.count { $0.listings += 1 }
            return try base.keys(prefixedBy: prefix)
        }
    }

    let base: any ExchangeProducer.Storage
    private let lock = NSLock()
    private var counts = Counts()

    init(_ base: any ExchangeProducer.Storage = ExchangeProducer.InMemoryStorage()) {
        self.base = base
    }

    func transaction<R>(_ body: (any ExchangeProducer.Transaction) throws -> R) throws -> R {
        count { $0.transactions += 1 }
        return try base.transaction { transaction in
            try body(Counting(base: transaction, storage: self))
        }
    }

    /// The counts since the last call, which starts a new tally.
    func takeCounts() -> Counts {
        lock.lock()
        defer {
            lock.unlock()
        }
        let taken = counts
        counts = Counts()
        return taken
    }

    private func count(_ update: (inout Counts) -> Void) {
        lock.lock()
        defer {
            lock.unlock()
        }
        update(&counts)
    }
}
