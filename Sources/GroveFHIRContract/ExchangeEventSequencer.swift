//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The exchange-event ledger of one installation: it hands out event sequences and keeps what each
/// event is rebuilt from until the caller releases it.
///
/// Grove owns the ledger's logic and its entries; the application supplies durable, transactional
/// storage through ``Storage``. The ledger holds the producer instance and its counter, one reservation
/// per event key an exporter has not yet released, and the facts (application, host, studies) each
/// reservation was minted under. A key that is still reserved, under the same context, returns its
/// reservation unchanged, so an exact redelivery after a crash rebuilds byte-identical output. Nothing
/// is forgotten implicitly; ``forgetReservations(madeBefore:)`` is the explicit maintenance call.
///
/// Every operation is one storage transaction; the sequencer itself holds no lock and no mutable state,
/// so any number of sequencers may share one storage. Calls block for their transaction, so keep them
/// off the main actor. See <doc:ExchangeLedgerStorage> for the contract a storage must meet.
public final class ExchangeEventSequencer: Sendable {
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
        /// and its bodies have no effect outside the transaction other than process-memory notes that end
        /// when the call returns, so a storage may discard an attempt and run `body` again. A `body` that
        /// throws commits nothing.
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
        /// Grove calls it only from ``ExchangeEventSequencer/reset()`` and
        /// ``ExchangeEventSequencer/forgetReservations(madeBefore:)``, never on the export path.
        func keys(prefixedBy prefix: String) throws -> [String]
    }

    /// Faults in the stored entries themselves; errors a ``Storage`` throws propagate unchanged.
    ///
    /// ``ExchangeEventSequencer/reset()`` is always a safe recovery.
    public enum LedgerError: Error, Equatable, Sendable {
        /// The entry was written by a later layout; it is refused rather than misread.
        case unsupportedEntryVersion(key: String, version: Int)
        /// The entry is malformed, out of range, or inconsistent with the ledger, such as a reservation
        /// at or above the counter of its own producer instance, one at an instant no FHIR instant can
        /// state, or one naming facts the ledger lacks.
        case corruptEntry(key: String)
    }

    let storage: any Storage
    /// Which reservations live calls in this process hold or are about to hold.
    let holds: HoldRegistry

    /// Creates a sequencer over the application's storage.
    ///
    /// Nothing is read here; the ledger is read, and any storage error surfaces, on first use.
    public convenience init(storage: any Storage) {
        self.init(storage: storage, holds: .shared)
    }

    init(storage: any Storage, holds: HoldRegistry) {
        self.storage = storage
        self.holds = holds
    }

    /// A sequencer over a fresh ``InMemoryStorage``, for tests, previews and single-process tools.
    public static func inMemory() -> ExchangeEventSequencer {
        ExchangeEventSequencer(storage: InMemoryStorage())
    }

    /// Forgets every entry in one transaction.
    ///
    /// The next reservation mints a new producer instance and numbers from one, and a receipt from before
    /// the reset releases nothing. Always a safe recovery from ``LedgerError``.
    public func reset() throws {
        try storage.transaction { transaction in
            for key in try transaction.keys(prefixedBy: "") {
                try transaction.remove(key)
            }
        }
    }

    /// Forgets the reservations made before `cutoff`, by their reservation instant, then the facts no
    /// remaining reservation references, in one transaction.
    ///
    /// Grove never calls this itself. It costs time proportional to the ledger. The cutoff and the
    /// stored instants are on the caller's clock, so choose a cutoff that tolerates clock skew. A
    /// forgotten key that is redelivered becomes a new event, including one a live call still holds.
    ///
    /// - Returns: The number of reservations forgotten.
    @discardableResult
    public func forgetReservations(madeBefore cutoff: Date) throws -> Int {
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


extension ExchangeEventSequencer {
    /// One reservation per distinct request, durable before this returns.
    ///
    /// A key whose stored reservation carries the request's fingerprint returns that reservation
    /// unchanged: the same producer instance, sequence, instant and facts, and writes nothing. Any other
    /// request takes the next sequence at `instant` (millisecond precision) under `facts`, replacing what
    /// the key held. New sequences follow the requests' sorted order; a counter that would overflow mints
    /// a new producer instance. A sequence is never handed out twice. Each returned reservation is held
    /// for the caller until ``finish(_:released:forgetting:)``. Exporters reach it through
    /// `ExchangeProducer.reserve(_:at:)`, which passes the facts the producer prepared once.
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
    /// no call in this process holds it or is about to. `keys` are forgotten whatever they hold, and only
    /// when `released` is true. Opens one transaction when anything is to be removed, none otherwise.
    package func finish(
        _ held: [ExchangeEventReservation.Handle],
        released: Bool,
        forgetting keys: [ExchangeEventKey]
    ) throws {
        let removable = holds.end(held, released: released)
        let forgotten = released ? keys : []
        guard !removable.isEmpty || !forgotten.isEmpty else {
            return
        }
        try storage.transaction { transaction in
            // A reserve whose transaction returned the reservation noted it there, so it stays; a reserve whose
            // transaction runs after this one no longer finds it, as a storage runs a process's transactions one at
            // a time.
            for handle in removable where !holds.isHeld(handle) {
                let key = LedgerKey.event(handle.key)
                guard let value = try transaction.read(key) else {
                    continue
                }
                let stored = try EventEntry(decoding: value, key: key)
                if stored.instance == handle.instance && stored.sequence == handle.sequence {
                    try transaction.remove(key)
                }
            }
            for key in forgotten {
                try transaction.remove(LedgerKey.event(key))
            }
        }
    }
}
