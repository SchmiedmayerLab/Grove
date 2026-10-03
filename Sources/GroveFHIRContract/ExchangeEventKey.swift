//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
package import Foundation


/// What a key holds while it is reserved: the event's sequence and the instant it was reserved at.
package struct ExchangeEventReservation: Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case sequence
        case instantMilliseconds
    }

    package let sequence: EventSequence
    /// The caller's instant at reservation, at millisecond precision, the same on every return of the key.
    package let instant: Date

    init(_ stored: ExchangeEventSequencer.State.Reservation) {
        self.sequence = EventSequence(stored.sequence)
        self.instant = ExchangeInstant.date(millisecondsSinceEpoch: stored.instantMilliseconds)
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sequence = try EventSequence(container.decode(String.self, forKey: .sequence))
        self.instant = ExchangeInstant.date(millisecondsSinceEpoch: try container.decode(Int64.self, forKey: .instantMilliseconds))
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence.rawValue, forKey: .sequence)
        try container.encode(ExchangeInstant.millisecondsSinceEpoch(instant), forKey: .instantMilliseconds)
    }
}


/// The key one exchange event is reserved under: deterministic for one source-record version, and
/// opaque, so the ledger holds no clear record identity.
package struct ExchangeEventKey: Hashable, Codable, Sendable {
    package let rawValue: String
}


extension ExchangeEventKey {
    /// The key of one source record's event under one adapter.
    ///
    /// SHA-256, base64url without padding, over the length-framed UTF-8 parts `grove-event-key-v0`,
    /// the kind (`active` or `retraction`), the adapter id, the source-record identifier value and,
    /// when the source versions its records, the revision evidence: a re-recorded record is a new
    /// event, an active event and its retraction never share a reservation.
    ///
    /// - Precondition: Every part is shorter than 4 GiB.
    package init(kind: ExchangeGraph.Kind, adapterID: String, sourceRecord: String, revision: String? = nil) {
        let kindLabel = switch kind {
        case .active: "active"
        case .retraction: "retraction"
        }
        var parts = ["grove-event-key-v0", kindLabel, adapterID, sourceRecord]
        if let revision {
            parts.append(revision)
        }
        let framed: Data
        do {
            framed = try LengthFramedUTF8.encode(parts)
        } catch {
            preconditionFailure("An event key part exceeds the framing limit: \(error)")
        }
        self.rawValue = Data(SHA256.hash(data: framed)).base64URLEncodedStringWithoutPadding
    }
}
