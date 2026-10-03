//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


/// A storage that fails on demand: from the n-th write of a transaction, or at commit after `body` returned.
final class FaultyStorage: ExchangeEventSequencer.Storage, @unchecked Sendable { // The fault settings are guarded by `lock`.
    struct Fault: Error, Equatable {}

    private final class Faulting: ExchangeEventSequencer.Transaction {
        let base: any ExchangeEventSequencer.Transaction
        let failingWrite: Int?
        var writes = 0

        init(base: any ExchangeEventSequencer.Transaction, failingWrite: Int?) {
            self.base = base
            self.failingWrite = failingWrite
        }

        func read(_ key: String) throws -> Data? {
            try base.read(key)
        }

        func write(_ value: Data, for key: String) throws {
            writes += 1
            if writes == failingWrite {
                throw Fault()
            }
            try base.write(value, for: key)
        }

        func remove(_ key: String) throws {
            try base.remove(key)
        }

        func keys(prefixedBy prefix: String) throws -> [String] {
            try base.keys(prefixedBy: prefix)
        }
    }

    let base = ExchangeEventSequencer.InMemoryStorage()
    private let lock = NSLock()
    private var failingWrite: Int?
    private var failsAtCommit = false

    /// Makes the `write`-th write of every later transaction throw; `nil` stops it.
    func failWrite(_ write: Int?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        failingWrite = write
    }

    /// Makes every later transaction fail after its body returned, so nothing it wrote commits.
    func failAtCommit(_ fails: Bool) {
        lock.lock()
        defer {
            lock.unlock()
        }
        failsAtCommit = fails
    }

    func transaction<R>(_ body: (any ExchangeEventSequencer.Transaction) throws -> R) throws -> R {
        lock.lock()
        let (failingWrite, failsAtCommit) = (self.failingWrite, self.failsAtCommit)
        lock.unlock()
        return try base.transaction { transaction in
            let result = try body(Faulting(base: transaction, failingWrite: failingWrite))
            // Throwing from inside the base transaction discards its buffered writes: a failed commit.
            if failsAtCommit {
                throw Fault()
            }
            return result
        }
    }
}
