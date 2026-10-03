//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension ExchangeEventSequencer {
    /// The persisted ledger: the producer instance, the next sequence, and the keyed reservations.
    ///
    /// Stored as JSON under a schema version, so a later layout is recognised rather than misread.
    struct State: Codable, Equatable, Sendable {
        /// One key's reservation, with every instant as whole milliseconds since 1970-01-01T00:00:00Z.
        struct Reservation: Codable, Equatable, Sendable {
            let sequence: UInt64
            let instantMilliseconds: Int64
            /// When the reservation was made, for retention; the same instant the reservation hands out.
            let reservedAtMilliseconds: Int64
        }

        static let currentSchemaVersion: UInt = 1

        let schemaVersion: UInt
        let producerInstance: UUID
        var nextSequence: UInt64
        var reservations: [String: Reservation]

        /// A fresh ledger under a new producer instance, numbering from one.
        init() {
            self.schemaVersion = Self.currentSchemaVersion
            self.producerInstance = UUID()
            self.nextSequence = 1
            self.reservations = [:]
        }

        /// The stored ledger, or `nil` for an empty storage.
        static func decode(_ data: Data?) throws -> State? {
            guard let data else {
                return nil
            }
            let state = try JSONDecoder().decode(State.self, from: data)
            guard state.schemaVersion == currentSchemaVersion else {
                throw StateError.unsupportedSchemaVersion(state.schemaVersion)
            }
            return state
        }

        func encoded() throws -> Data {
            try JSONEncoder().encode(self)
        }

        /// The key's reservation, or a new one under the next sequence.
        mutating func reservation(for key: ExchangeEventKey, instantMilliseconds: Int64) throws -> Reservation {
            if let existing = reservations[key.rawValue] {
                return existing
            }
            let (next, overflow) = nextSequence.addingReportingOverflow(1)
            guard !overflow else {
                throw StateError.sequencesExhausted
            }
            let reservation = Reservation(
                sequence: nextSequence,
                instantMilliseconds: instantMilliseconds,
                reservedAtMilliseconds: instantMilliseconds
            )
            nextSequence = next
            reservations[key.rawValue] = reservation
            return reservation
        }

        /// Forgets every reservation made before `cutoff`; `nil` keeps them all.
        mutating func prune(reservedBefore cutoff: Int64?) {
            guard let cutoff, reservations.contains(where: { $0.value.reservedAtMilliseconds < cutoff }) else {
                return
            }
            reservations = reservations.filter { $0.value.reservedAtMilliseconds >= cutoff }
        }
    }
}
