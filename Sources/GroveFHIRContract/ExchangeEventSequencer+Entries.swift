//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The `producer` entry: the current producer instance and the next sequence it hands out.
struct ProducerEntry: Equatable {
    private struct Payload: Codable {
        enum CodingKeys: String, CodingKey {
            case version = "v"
            case instance
            case next
        }

        let version: Int
        let instance: String
        let next: String
    }

    var instance: UUID
    var next: UInt64

    init(instance: UUID, next: UInt64) {
        self.instance = instance
        self.next = next
    }

    init(decoding value: Data) throws {
        let payload = try LedgerEntryCoding.decode(Payload.self, from: value, key: LedgerKey.producer)
        guard let instance = LedgerEntryCoding.instance(payload.instance), let next = LedgerEntryCoding.positiveInteger(payload.next) else {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: LedgerKey.producer)
        }
        self.init(instance: instance, next: next)
    }

    func encoded() throws -> Data {
        try LedgerEntryCoding.encode(Payload(
            version: LedgerEntryCoding.version,
            instance: instance.uuidString.lowercased(),
            next: String(next)
        ))
    }
}


/// An `event/<key>` entry: one key's reservation, the facts it was minted under, and the fingerprint of the
/// context that shaped its graph.
struct EventEntry: Equatable {
    private struct Payload: Codable {
        enum CodingKeys: String, CodingKey {
            case version = "v"
            case instance
            case sequence
            case instant
            case facts
            case fingerprint
        }

        let version: Int
        let instance: String
        let sequence: String
        let instant: Int64
        let facts: String
        let fingerprint: String
    }

    let instance: UUID
    let sequence: UInt64
    /// Whole milliseconds since 1970-01-01T00:00:00Z.
    let instantMilliseconds: Int64
    /// The digest naming the `facts/<digest>` entry.
    let factsDigest: String
    let fingerprint: String

    init(instance: UUID, sequence: UInt64, instantMilliseconds: Int64, factsDigest: String, fingerprint: String) {
        self.instance = instance
        self.sequence = sequence
        self.instantMilliseconds = instantMilliseconds
        self.factsDigest = factsDigest
        self.fingerprint = fingerprint
    }

    init(decoding value: Data, key: String) throws {
        let payload = try LedgerEntryCoding.decode(Payload.self, from: value, key: key)
        guard let instance = LedgerEntryCoding.instance(payload.instance),
              let sequence = LedgerEntryCoding.positiveInteger(payload.sequence),
              ExchangeIdentity.isUnpaddedBase64URLDigest(payload.facts) else {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: key)
        }
        self.init(
            instance: instance,
            sequence: sequence,
            instantMilliseconds: payload.instant,
            factsDigest: payload.facts,
            fingerprint: payload.fingerprint
        )
    }

    func encoded() throws -> Data {
        try LedgerEntryCoding.encode(Payload(
            version: LedgerEntryCoding.version,
            instance: instance.uuidString.lowercased(),
            sequence: String(sequence),
            instant: instantMilliseconds,
            facts: factsDigest,
            fingerprint: fingerprint
        ))
    }
}


extension ExchangeEventReservation {
    /// The reservation a stored or newly written event entry describes.
    init(key: ExchangeEventKey, entry: EventEntry, facts: ExchangeEventFacts) {
        self.init(
            handle: Handle(key: key, instance: entry.instance, sequence: entry.sequence),
            instant: ExchangeInstant.date(millisecondsSinceEpoch: entry.instantMilliseconds),
            facts: facts
        )
    }
}


extension ExchangeEventSequencer {
    /// One `reserve` call inside its transaction: it reads only the entries of its own keys, the producer,
    /// and each distinct facts entry once, and writes only what it mints.
    struct ReserveCall {
        private let transaction: any Transaction
        private let current: PreparedFacts
        private let instantMilliseconds: Int64
        private var factsByDigest: [String: ExchangeEventFacts] = [:]
        private var currentFactsStored = false

        init(transaction: any Transaction, current: PreparedFacts, instantMilliseconds: Int64) {
            self.transaction = transaction
            self.current = current
            self.instantMilliseconds = instantMilliseconds
        }

        mutating func reserve(_ requests: [ExchangeEventRequest]) throws -> [ExchangeEventRequest: ExchangeEventReservation] {
            let stored = try transaction.read(LedgerKey.producer).map { try ProducerEntry(decoding: $0) }
            var producer = stored ?? ProducerEntry(instance: UUID(), next: 1)
            var minted = false
            var reserved: [ExchangeEventRequest: ExchangeEventReservation] = [:]
            for request in requests {
                let key = LedgerKey.event(request.key)
                let event = try transaction.read(key).map { try EventEntry(decoding: $0, key: key) }
                // A reservation at or above the counter of its own instance means the counter regressed.
                if let event, event.instance == producer.instance, event.sequence >= producer.next {
                    throw LedgerError.corruptEntry(key: key)
                }
                if let event, event.fingerprint == request.fingerprint {
                    reserved[request] = ExchangeEventReservation(key: request.key, entry: event, facts: try facts(event.factsDigest, of: key))
                    continue
                }
                if producer.next == .max {
                    producer = ProducerEntry(instance: UUID(), next: 1)
                }
                let entry = EventEntry(
                    instance: producer.instance,
                    sequence: producer.next,
                    instantMilliseconds: instantMilliseconds,
                    factsDigest: current.digest,
                    fingerprint: request.fingerprint
                )
                producer.next += 1
                minted = true
                try storeCurrentFacts()
                try transaction.write(try entry.encoded(), for: key)
                reserved[request] = ExchangeEventReservation(key: request.key, entry: entry, facts: current.facts)
            }
            if minted {
                try transaction.write(try producer.encoded(), for: LedgerKey.producer)
            }
            return reserved
        }

        /// The facts a stored reservation names, decoded once per call; a missing entry makes the reservation corrupt.
        private mutating func facts(_ digest: String, of eventKey: String) throws -> ExchangeEventFacts {
            if let facts = factsByDigest[digest] {
                return facts
            }
            let key = LedgerKey.facts(digest)
            guard let value = try transaction.read(key) else {
                throw LedgerError.corruptEntry(key: eventKey)
            }
            let facts = try PreparedFacts.decode(value, key: key)
            factsByDigest[digest] = facts
            currentFactsStored = currentFactsStored || digest == current.digest
            return facts
        }

        /// Writes the current facts entry once per call, unless the ledger already holds it.
        private mutating func storeCurrentFacts() throws {
            guard !currentFactsStored else {
                return
            }
            let key = LedgerKey.facts(current.digest)
            if try transaction.read(key) == nil {
                try transaction.write(current.bytes, for: key)
            }
            currentFactsStored = true
        }
    }
}
