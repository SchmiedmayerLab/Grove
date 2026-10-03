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


/// One event an exporter needs: its key, and the digest of every input that shapes its graph but is not
/// rebuilt from the frozen facts. Equal requests share one reservation; a stored reservation is reused only
/// for a request with the same fingerprint, so an event identifier never carries different content.
package struct ExchangeEventRequest: Hashable, Sendable {
    package let key: ExchangeEventKey
    /// SHA-256, base64url without padding; opaque to the sequencer.
    package let fingerprint: String

    package init(key: ExchangeEventKey, fingerprint: String) {
        self.key = key
        self.fingerprint = fingerprint
    }
}


/// What an event is minted and rebuilt from: its producer instance and sequence, its instant, and the
/// facts it was minted under, all read in the same transaction.
package struct ExchangeEventReservation: Hashable, Sendable {
    /// Identifies this exact reservation, so a release never removes a successor's. Unique across ledgers,
    /// as every ledger mints its own producer instance.
    package struct Handle: Hashable, Sendable {
        let key: ExchangeEventKey
        let instance: UUID
        let sequence: UInt64
    }

    package let handle: Handle
    package let sequence: EventSequence
    /// The instant of the first reservation, at millisecond precision, the same on every return of the key.
    package let instant: Date
    /// Always decoded from the ledger's stored facts entry.
    package let facts: ExchangeEventFacts

    /// The producer instance the sequence was handed out under.
    package var producerInstance: UUID { handle.instance }
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
