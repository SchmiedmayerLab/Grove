//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Which reservations the live calls of this process hold or are about to hold, and whether any holder released one.
///
/// The ledger's entries hold no per-call state: a reservation is removed when the last live holder in this
/// process finishes and any holder released it, so overlapping exports of one record never remove each
/// other's reservation, and a call that throws leaves its reservations for the redelivery. A reserve notes the
/// reservations its transaction returns from inside that transaction and turns them into holds in one step after
/// it, so a reservation it is about to hold is never seen unused in between. A removal that finds such a holder
/// hands the release over to it, so the release mark survives until the last holder finishes. Handles include
/// the producer instance, which every ledger mints for itself, so they are unique across ledgers and the same
/// through every storage object or producer in front of one ledger; one registry serves every storage. Holds do
/// not span processes; the lock is never held across I/O.
final class HoldRegistry: @unchecked Sendable { // `holds` and `reserving` are guarded by `lock`.
    /// The reservations one reserve call noted, so an attempt the storage runs again notes nothing twice.
    final class Notes: @unchecked Sendable { // `handles` is guarded by the registry's `lock`.
        fileprivate var handles: Set<ExchangeEventReservation.Handle> = []
    }

    private struct Hold {
        var live: Int
        var released: Bool
    }

    /// The registry every ledger of this process shares.
    static let shared = HoldRegistry()

    private let lock = NSLock()
    private var holds: [ExchangeEventReservation.Handle: Hold] = [:]
    /// The reservations reserving transactions returned whose calls have not yet taken their holds.
    private var reserving: [ExchangeEventReservation.Handle: Int] = [:]

    /// Notes that the reserve call `notes` belongs to is about to hold `handles`; called inside its transaction,
    /// before the commit, by every attempt.
    func beginReserving(_ handles: some Sequence<ExchangeEventReservation.Handle>, in notes: Notes) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for handle in handles where notes.handles.insert(handle).inserted {
            reserving[handle, default: 0] += 1
        }
    }

    /// Ends the notes of one reserve call and takes one hold per handle in `acquired`, in one step; `acquired` is
    /// empty when the reserving transaction did not commit.
    func endReserving(_ notes: Notes, acquiring acquired: some Sequence<ExchangeEventReservation.Handle>) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for handle in acquired {
            holds[handle, default: Hold(live: 0, released: false)].live += 1
        }
        for handle in notes.handles {
            let remaining = (reserving[handle] ?? 1) - 1
            reserving[handle] = remaining > 0 ? remaining : nil
            // A release handed over to a reserve that then did not commit has no holder left to finish it; the
            // reservation stays, as after a failed release.
            if remaining <= 0, holds[handle]?.live == 0 {
                holds[handle] = nil
            }
        }
        notes.handles = []
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

    /// Whether a live call holds `handle` or a reserving transaction returned it to a call about to hold it; if so,
    /// the release passes to that call, so the last holder to finish removes the reservation. Called inside the
    /// removing transaction; marking again, when a storage runs that body again, changes nothing.
    func handOver(_ handle: ExchangeEventReservation.Handle) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard holds[handle] != nil || reserving[handle] != nil else {
            return false
        }
        // A call still reserving takes its hold on this entry, and with it the release mark.
        holds[handle, default: Hold(live: 0, released: true)].released = true
        return true
    }

    /// Whether a live call holds `handle`, or a reserving transaction returned it and its call is about to hold it.
    func isHeld(_ handle: ExchangeEventReservation.Handle) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return holds[handle] != nil || reserving[handle] != nil
    }
}
