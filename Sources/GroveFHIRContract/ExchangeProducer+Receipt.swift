//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension ExchangeProducer {
    /// What one export or retraction call reserved.
    ///
    /// Call ``release()`` once every produced graph is durably stored AND the source cursor (a HealthKit anchor, a
    /// bulk-export checkpoint) is committed. Until then an exact redelivery of the same records reproduces the
    /// same events, byte for byte. Releasing is idempotent, also across copies of this reference, and makes
    /// one ledger transaction at most. An export's receipt makes none when nothing was reserved, or while
    /// another call in this process still holds the same events. A retraction's receipt makes one whenever it
    /// reserved a retraction, as it also forgets each deleted record's active reservation, and none otherwise.
    ///
    /// A receipt dropped unreleased (the call threw, or its commit action was discarded) leaves its
    /// reservations for the redelivery. When another call in this process released the same event, the last
    /// one to finish removes it, which may run one ledger transaction on the thread that drops the receipt. A
    /// release that fails keeps the reservations; a later release of the same events, a later exact export,
    /// or ``ExchangeProducer/resetLedger()`` removes them.
    public final class Receipt: @unchecked Sendable { // `isFinished` is guarded by `lock`.
        private let ledger: Ledger
        private let held: [ExchangeEventReservation.Handle]
        private let forgetting: [ExchangeEventKey]
        private let lock = NSLock()
        private var isFinished = false

        init(ledger: Ledger, held: [ExchangeEventReservation.Handle], forgetting: [ExchangeEventKey]) {
            self.ledger = ledger
            self.held = held
            self.forgetting = forgetting
        }

        /// Ends this call's hold on its reservations, so the next export of the same records is a new event.
        ///
        /// Only the first call counts. Storage failures are swallowed: a reservation that stays behind only
        /// makes a later exact export reproduce the same event.
        public func release() {
            guard claim() else {
                return
            }
            try? ledger.finish(held, released: true, forgetting: forgetting)
        }

        private func claim() -> Bool {
            lock.lock()
            defer {
                lock.unlock()
            }
            guard !isFinished else {
                return false
            }
            isFinished = true
            return true
        }

        deinit {
            if !isFinished, !held.isEmpty {
                try? ledger.finish(held, released: false, forgetting: [])
            }
        }
    }
}
