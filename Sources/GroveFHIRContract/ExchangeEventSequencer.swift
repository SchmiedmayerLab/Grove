//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Hands out exchange-event sequences under one producer instance.
///
/// Grove owns the logic; the application supplies durable storage through ``Storage``. The sequencer
/// mints the producer instance on first use and persists it with the counter, so every event an
/// installation emits is numbered under one instance until the storage is reset, after which a new
/// instance starts at one and no sequence is reused under the old one.
///
/// Exporters reserve a sequence per event key before building the event and release the key once the
/// source has durably acknowledged the event. A key that is still reserved returns its reservation
/// unchanged, so an exact redelivery after a crash reproduces the same event; a reservation that is
/// never released is forgotten after ``Retention/maximumAge``.
public final class ExchangeEventSequencer: Sendable {
    /// Durable, atomic read-modify-write of one opaque blob.
    ///
    /// A conformance makes the replacement durable before `update` returns and serialises concurrent
    /// callers (a lock, an actor hop or a database transaction). The bytes are the sequencer's own;
    /// a conformance stores them unchanged and never interprets them.
    public protocol Storage: Sendable {
        /// Loads the stored blob, lets `body` replace it, persists the replacement and returns `body`'s result.
        ///
        /// `nil` is what an empty storage loads; a `body` that throws stores nothing.
        func update<R>(_ body: (inout Data?) throws -> R) throws -> R
    }

    /// How long a reservation that is never released is kept.
    public struct Retention: Hashable, Sendable {
        /// Thirty days: long enough for a source to redeliver after a crash, short enough that
        /// keys which were never released do not accumulate for the life of an installation.
        public static let `default` = Retention(maximumAge: 30 * 24 * 60 * 60)

        /// A reservation made further than this before a later reservation's instant is forgotten
        /// at that later reservation; its key then reserves a new sequence.
        public let maximumAge: TimeInterval

        /// A retention of `maximumAge` seconds; `.infinity` keeps every reservation until it is released.
        public init(maximumAge: TimeInterval) {
            precondition(maximumAge > 0, "A reservation is retained for a positive duration.")
            self.maximumAge = maximumAge
        }
    }

    /// Faults in the stored ledger itself; what a ``Storage`` throws propagates unchanged.
    public enum StateError: Error, Equatable, Sendable {
        /// The ledger was written by a schema this version does not read.
        case unsupportedSchemaVersion(UInt)
        /// Every sequence under this producer instance has been handed out.
        case sequencesExhausted
    }

    /// Process-local storage: nothing survives the process, so every launch is a new producer instance.
    private final class MemoryStorage: Storage {
        private let lock = NSLock()
        nonisolated(unsafe) private var data: Data?

        func update<R>(_ body: (inout Data?) throws -> R) throws -> R {
            lock.lock()
            defer { lock.unlock() }
            return try body(&data)
        }
    }

    /// How long a reservation that is never released is kept.
    public let retention: Retention

    private let storage: any Storage
    /// Serialises this sequencer's own read-modify-write cycles; several sequencers over one storage
    /// rely on that storage's serialisation.
    private let lock = NSLock()

    /// The installation's producer instance, minted and persisted on first use.
    public var producerInstance: UUID {
        get throws {
            try withState { $0.producerInstance }
        }
    }

    /// Creates a sequencer over the application's storage.
    ///
    /// Nothing is read here; the stored ledger is loaded, and any storage error surfaces, on first use.
    public init(storage: any Storage, retention: Retention = .default) {
        self.storage = storage
        self.retention = retention
    }

    /// A sequencer whose ledger lives in this process only, for tests and previews.
    public static func inMemory(retention: Retention = .default) -> ExchangeEventSequencer {
        ExchangeEventSequencer(storage: MemoryStorage(), retention: retention)
    }

    /// Loads the ledger, creating it when the storage is empty, and stores it back when `body` changed it.
    private func withState<R>(_ body: (inout State) throws -> R) throws -> R {
        lock.lock()
        defer { lock.unlock() }
        return try storage.update { data in
            let loaded = try State.decode(data)
            var state = loaded ?? State()
            let result = try body(&state)
            if state != loaded {
                data = try state.encoded()
            }
            return result
        }
    }

    /// Mutates a ledger that exists; an empty storage is left empty.
    private func withExistingState(_ body: (inout State) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try storage.update { data in
            guard let loaded = try State.decode(data) else {
                return
            }
            var state = loaded
            try body(&state)
            if state != loaded {
                data = try state.encoded()
            }
        }
    }
}


extension ExchangeEventSequencer {
    /// One reservation per key, in the keys' order.
    ///
    /// A key that is still reserved returns its existing reservation, the same sequence and the same
    /// instant, so an exact redelivery reproduces the event. A new key takes the next sequence and
    /// `instant` at millisecond precision. Duplicate keys in one call map to one reservation.
    /// Reservations older than the retention, measured from `instant`, are forgotten first. Every
    /// reservation is durable before this returns, and a sequence is never handed out twice.
    package func reserve(_ keys: [ExchangeEventKey], at instant: Date) throws -> [ExchangeEventReservation] {
        let instantMilliseconds = ExchangeInstant.millisecondsSinceEpoch(instant)
        let cutoff = retentionCutoff(before: instantMilliseconds)
        return try withState { state in
            state.prune(reservedBefore: cutoff)
            var reservations: [ExchangeEventReservation] = []
            reservations.reserveCapacity(keys.count)
            for key in keys {
                let stored = try state.reservation(for: key, instantMilliseconds: instantMilliseconds)
                reservations.append(ExchangeEventReservation(stored))
            }
            return reservations
        }
    }

    /// Forgets the reservations of these keys; a key that holds none is ignored.
    package func release(_ keys: [ExchangeEventKey]) throws {
        try withExistingState { state in
            for key in keys {
                state.reservations.removeValue(forKey: key.rawValue)
            }
        }
    }

    /// ``release(_:)`` for a commit action that cannot act on a failure: a reservation that stays
    /// behind is harmless, as a redelivery reproduces its event and retention forgets it eventually.
    package func releaseIgnoringErrors(_ keys: [ExchangeEventKey]) {
        try? release(keys)
    }

    /// The instant before which a reservation is forgotten, or `nil` when the retention never expires.
    private func retentionCutoff(before instantMilliseconds: Int64) -> Int64? {
        guard let maximumAge = Int64(exactly: (retention.maximumAge * 1000).rounded(.up)) else {
            return nil
        }
        let (cutoff, overflow) = instantMilliseconds.subtractingReportingOverflow(maximumAge)
        return overflow ? nil : cutoff
    }
}
