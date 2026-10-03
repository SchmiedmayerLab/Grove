//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Which reservations the live calls of this process still hold, and whether any holder released one.
///
/// The ledger's entries hold no per-call state: a reservation is removed when the last live holder in this
/// process finishes and any holder released it, so overlapping exports of one record never remove each
/// other's reservation, and a call that throws leaves its reservations for the redelivery. Handles include
/// the producer instance, which every ledger mints for itself, so one registry serves every storage.
/// Holds do not span processes; the lock is never held across I/O.
final class HoldRegistry: @unchecked Sendable { // `holds` is guarded by `lock`.
    private struct Hold {
        var live: Int
        var released: Bool
    }

    /// The registry every sequencer of this process shares.
    static let shared = HoldRegistry()

    private let lock = NSLock()
    private var holds: [ExchangeEventReservation.Handle: Hold] = [:]

    /// The number of reservations some live call holds.
    var count: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return holds.count
    }

    /// Whether no live call holds any reservation.
    var isEmpty: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return holds.isEmpty
    }

    /// Takes one hold per handle; called only after the reserving transaction committed.
    func acquire(_ handles: some Sequence<ExchangeEventReservation.Handle>) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for handle in handles {
            holds[handle, default: Hold(live: 0, released: false)].live += 1
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
}
