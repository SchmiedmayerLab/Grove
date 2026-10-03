//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Which reservations the live calls of this process still hold, whether any holder released one, and which keys
/// of which ledger a reserve is in flight for.
///
/// The ledger's entries hold no per-call state: a reservation is removed when the last live holder in this
/// process finishes and any holder released it, so overlapping exports of one record never remove each
/// other's reservation, and a call that throws leaves its reservations for the redelivery. A reserve registers
/// its keys before its transaction and turns them into holds in one step after it, so a reservation it may reuse
/// is never seen unused in between. Handles include the producer instance, which every ledger mints for itself,
/// so holds need no ledger; keys in flight are scoped to their ledger. One registry serves every storage. Holds
/// do not span processes; the lock is never held across I/O.
final class HoldRegistry: @unchecked Sendable { // `holds` and `reserving` are guarded by `lock`.
    private struct Hold {
        var live: Int
        var released: Bool
    }

    /// One event key of one ledger.
    private struct LedgerEventKey: Hashable {
        let ledger: ObjectIdentifier
        let key: ExchangeEventKey
    }

    /// The registry every sequencer of this process shares.
    static let shared = HoldRegistry()

    private let lock = NSLock()
    private var holds: [ExchangeEventReservation.Handle: Hold] = [:]
    private var reserving: [LedgerEventKey: Int] = [:]

    /// Marks a reserve of `keys` in `ledger` as in flight; called before its transaction.
    func beginReserving(_ keys: some Sequence<ExchangeEventKey>, in ledger: ObjectIdentifier) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for key in keys {
            reserving[LedgerEventKey(ledger: ledger, key: key), default: 0] += 1
        }
    }

    /// Ends a reserve begun for `keys` in `ledger` and takes one hold per handle it returned, in one step; `handles`
    /// is empty when the reserving transaction did not commit.
    func endReserving(
        _ keys: some Sequence<ExchangeEventKey>,
        in ledger: ObjectIdentifier,
        acquiring handles: some Sequence<ExchangeEventReservation.Handle>
    ) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for handle in handles {
            holds[handle, default: Hold(live: 0, released: false)].live += 1
        }
        for key in keys {
            let scoped = LedgerEventKey(ledger: ledger, key: key)
            let remaining = (reserving[scoped] ?? 1) - 1
            reserving[scoped] = remaining > 0 ? remaining : nil
        }
    }

    /// Ends one hold per handle and returns the handles whose last live holder just finished and that some
    /// holder released: those reservations are no longer needed by anyone in this process.
    func end(_ handles: some Sequence<ExchangeEventReservation.Handle>, released: Bool) -> [ExchangeEventReservation.Handle] {
        lock.lock()
        defer {
            lock.unlock()
        }
        var removable: [ExchangeEventReservation.Handle] = []
        for handle in handles {
            var hold = holds[handle] ?? Hold(live: 1, released: false)
            hold.live -= 1
            hold.released = hold.released || released
            if hold.live > 0 {
                holds[handle] = hold
            } else {
                holds[handle] = nil
                if hold.released {
                    removable.append(handle)
                }
            }
        }
        return removable
    }

    /// Whether a live call holds `handle`, or a reserve of its key in `ledger` is in flight and may reuse it.
    func mayBeReused(_ handle: ExchangeEventReservation.Handle, in ledger: ObjectIdentifier) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return holds[handle] != nil || reserving[LedgerEventKey(ledger: ledger, key: handle.key)] != nil
    }
}
