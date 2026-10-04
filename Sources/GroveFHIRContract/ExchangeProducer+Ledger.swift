//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


extension ExchangeProducer {
    /// Durable, keyed, transactional storage for one ledger.
    ///
    /// The entries belong to Grove: a storage keeps keys and values byte-exact and never interprets them.
    /// A conformance meets the five clauses of <doc:ExchangeLedgerStorage>: atomicity, durability,
    /// serializable isolation, no regression or duplication, and byte-exactness. Running one process's
    /// transactions one at a time, as a lock or a transaction that takes the write lock when it begins does,
    /// also keeps a release from removing a reservation another call has just reused; a storage whose
    /// transactions overlap loses only that, and the call's redelivery becomes a duplicate, never a reuse.
    public protocol Storage: Sendable {
        /// Runs `body` as one transaction and returns its result.
        ///
        /// The transaction is valid only inside `body`. Grove never calls `transaction` from inside `body`,
        /// and its bodies have no effect outside the transaction other than idempotent process-memory notes
        /// about which calls hold a reservation, so a storage may discard an attempt and run `body` again. A
        /// `body` that throws commits nothing.
        func transaction<R>(_ body: (any Transaction) throws -> R) throws -> R
    }

    /// One transaction's view of the ledger: an untyped map from key to value that sees its own writes.
    public protocol Transaction {
        /// The value stored under `key`, or `nil` when there is none.
        func read(_ key: String) throws -> Data?
        /// Stores `value` under `key`, replacing any earlier value.
        func write(_ value: Data, for key: String) throws
        /// Removes `key`; removing an absent key does nothing.
        func remove(_ key: String) throws
        /// Every key that starts with `prefix`, in no particular order.
        ///
        /// Grove calls it only from ``ExchangeProducer/resetLedger()`` and
        /// ``ExchangeProducer/forgetReservations(madeBefore:)``, never on the export path.
        func keys(prefixedBy prefix: String) throws -> [String]
    }

    /// Faults in the stored entries themselves; errors a ``Storage`` throws propagate unchanged.
    ///
    /// ``ExchangeProducer/resetLedger()`` is always a safe recovery.
    public enum LedgerError: Error, Equatable, Sendable {
        /// The entry was written by a later layout; it is refused rather than misread.
        case unsupportedEntryVersion(key: String, version: Int)
        /// The entry is malformed, out of range, or inconsistent with the ledger, such as a reservation
        /// at or above the counter of its own producer instance, one at an instant no FHIR instant can
        /// state, or one naming facts the ledger lacks.
        case corruptEntry(key: String)
    }

    /// The exchange-event ledger over one storage: it hands out event sequences and keeps what each event is
    /// rebuilt from until the caller releases it.
    ///
    /// It holds no lock and no mutable state of its own; which reservations live calls hold is tracked in
    /// process memory by `HoldRegistry`.
    struct Ledger: Sendable {
        let storage: any Storage
        /// Which reservations live calls in this process hold or are about to hold.
        let holds: HoldRegistry

        /// Forgets every entry in one transaction.
        func reset() throws {
            try storage.transaction { transaction in
                for key in try transaction.keys(prefixedBy: "") {
                    try transaction.remove(key)
                }
            }
        }

        /// Forgets the reservations made before `cutoff`, then the facts no remaining reservation references,
        /// in one transaction, and returns how many reservations it forgot.
        func forgetReservations(madeBefore cutoff: Date) throws -> Int {
            let cutoffMilliseconds = ExchangeInstant.millisecondsSinceEpoch(cutoff)
            return try storage.transaction { transaction in
                var forgotten = 0
                var referenced: Set<String> = []
                for key in try transaction.keys(prefixedBy: LedgerKey.eventPrefix) {
                    guard let value = try transaction.read(key) else {
                        continue
                    }
                    let event = try EventEntry(decoding: value, key: key)
                    if event.instantMilliseconds < cutoffMilliseconds {
                        try transaction.remove(key)
                        forgotten += 1
                    } else {
                        referenced.insert(event.factsDigest)
                    }
                }
                for key in try transaction.keys(prefixedBy: LedgerKey.factsPrefix)
                where !referenced.contains(String(key.dropFirst(LedgerKey.factsPrefix.count))) {
                    try transaction.remove(key)
                }
                return forgotten
            }
        }
    }
}


extension ExchangeProducer.Ledger {
    /// One reservation per distinct request, durable before this returns.
    ///
    /// A key whose stored reservation carries the request's fingerprint returns that reservation
    /// unchanged: the same producer instance, sequence, instant and facts, and writes nothing. Any other
    /// request takes the next sequence at `instant` (millisecond precision) under `facts`, replacing what
    /// the key held. New sequences follow the requests' sorted order; a counter that would overflow mints
    /// a new producer instance. A sequence is never handed out twice. A key requested under two fingerprints
    /// in one call takes two sequences and keeps the later, so a retry of that call mints both again: request
    /// one fingerprint per key and call for exact retries. Each returned reservation is held
    /// for the caller until ``finish(_:released:forgetting:)``. Exporters reach it through
    /// `ExchangeProducer.reserve(_:at:forgetting:)`, which passes the facts the producer prepared once and
    /// hands the holds to a receipt.
    ///
    /// An `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    /// `ExchangeIdentityError.invalidInstant` before the ledger is touched, as the ledger would refuse to read
    /// it back.
    func reserve(
        _ requests: some Collection<ExchangeEventRequest>,
        at instant: Date,
        facts current: PreparedFacts
    ) throws -> [ExchangeEventRequest: ExchangeEventReservation] {
        let instantMilliseconds = ExchangeInstant.millisecondsSinceEpoch(instant)
        guard ExchangeInstant.statableMilliseconds.contains(instantMilliseconds) else {
            throw ExchangeIdentityError.invalidInstant
        }
        let ordered = Set(requests).sorted { ($0.key.rawValue, $0.fingerprint) < ($1.key.rawValue, $1.fingerprint) }
        // Noted inside the transaction, before it commits, until the holds are taken, so no release removes a
        // reservation this call is about to hold in between.
        let notes = HoldRegistry.Notes()
        var acquired: [ExchangeEventReservation.Handle] = []
        defer {
            holds.endReserving(notes, acquiring: acquired)
        }
        let reserved = try storage.transaction { transaction in
            var reserving = ReserveCall(transaction: transaction, current: current, instantMilliseconds: instantMilliseconds)
            let reserved = try reserving.reserve(ordered)
            holds.beginReserving(reserved.values.map(\.handle), in: notes)
            return reserved
        }
        acquired = reserved.values.map(\.handle)
        return reserved
    }

    /// Ends one hold per handle.
    ///
    /// `released` says the caller's output is durably handed off. When the last live holder of a
    /// reservation in this process finishes and any holder released it, the reservation is removed, but
    /// only while the key still holds exactly that reservation and, checked inside the removing transaction,
    /// no call in this process holds it or is about to; such a call takes the release over, so the last one
    /// to finish removes it. Only when `released` is true are `keys` forgotten: each key's reservation, whatever
    /// event it holds, is removed the same way when a producer instance of `held` made it, so a caller from
    /// before a reset, or one that holds nothing, forgets nothing. Opens one transaction when anything is to be
    /// removed, none otherwise.
    func finish(
        _ held: [ExchangeEventReservation.Handle],
        released: Bool,
        forgetting keys: [ExchangeEventKey]
    ) throws {
        let removable = holds.end(held, released: released)
        // A reset mints a new producer instance, so nothing reserved after it carries one of these.
        let instances = Set(held.map(\.instance))
        let forgotten = released && !instances.isEmpty ? keys : []
        guard !removable.isEmpty || !forgotten.isEmpty else {
            return
        }
        try storage.transaction { transaction in
            // A reserve whose transaction returned the reservation noted it there, so it stays and that call takes the
            // release over; a reserve whose transaction runs after this one no longer finds it, as a storage runs a
            // process's transactions one at a time.
            for handle in removable where !holds.handOver(handle) {
                if try Self.reservation(of: handle.key, in: transaction) == handle {
                    try transaction.remove(LedgerKey.event(handle.key))
                }
            }
            for key in forgotten {
                if let stored = try Self.reservation(of: key, in: transaction), instances.contains(stored.instance), !holds.handOver(stored) {
                    try transaction.remove(LedgerKey.event(key))
                }
            }
        }
    }
}


extension ExchangeProducer.Ledger {
    /// The reservation `key` holds in `transaction`, if any.
    private static func reservation(
        of key: ExchangeEventKey,
        in transaction: any ExchangeProducer.Transaction
    ) throws -> ExchangeEventReservation.Handle? {
        let entryKey = LedgerKey.event(key)
        return try transaction.read(entryKey).map { value in
            let stored = try EventEntry(decoding: value, key: entryKey)
            return ExchangeEventReservation.Handle(key: key, instance: stored.instance, sequence: stored.sequence)
        }
    }
}
