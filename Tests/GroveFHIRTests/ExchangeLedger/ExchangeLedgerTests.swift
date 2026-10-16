//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Testing


/// The ledger's reservation, hold, release, reset and pruning semantics over the in-memory storage.
@Suite
struct ExchangeLedgerTests {
    private typealias Fixtures = LedgerFixtures

    private static func producer(in storage: any ExchangeProducer.Storage) throws -> ProducerEntry? {
        try Fixtures.stored(LedgerKey.producer, in: storage).map { try ProducerEntry(decoding: $0) }
    }

    @Test("G1: new keys take 1..n in sorted request order, each naming the ledger's instance, at the millisecond instant")
    func newKeysTakeConsecutiveSequences() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let requests = ["a", "b", "c", "d"].map { Fixtures.request($0) }
        let reserved = try ledger.reserve(requests, at: Fixtures.instant, facts: Fixtures.facts())
        let sorted = requests.sorted { $0.key.rawValue < $1.key.rawValue }
        #expect(sorted.map { reserved[$0]?.sequence.rawValue } == ["1", "2", "3", "4"])
        let producer = try #require(try Self.producer(in: storage))
        #expect(producer.next == 5)
        #expect(reserved.values.allSatisfy { $0.producerInstance == producer.instance && $0.handle.instance == producer.instance })
        #expect(reserved.values.allSatisfy { ExchangeInstant.millisecondsSinceEpoch($0.instant) == Fixtures.instantMilliseconds })
        let next = try ledger.reserve([Fixtures.request("e")], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(next.values.map(\.sequence.rawValue) == ["5"])
    }

    @Test("A reserved key under the same fingerprint returns its reservation and facts unchanged and writes nothing")
    func reservedKeyIsReturnedUnchanged() throws {
        let storage = CountingStorage()
        let ledger = Fixtures.ledger(storage)
        let request = Fixtures.request("a")
        let first = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "100"))
        _ = storage.takeCounts()
        let again = try ledger.reserve([request], at: Fixtures.instant.addingTimeInterval(3600), facts: Fixtures.facts(build: "110"))
        #expect(again == first)
        #expect(again[request]?.facts == (try Fixtures.facts(build: "100").facts))
        let counts = storage.takeCounts()
        #expect(counts.writes == 0 && counts.removals == 0)
        #expect(counts.transactions == 1)
    }

    @Test("Equal requests in one call share a reservation; one key under two fingerprints is two events")
    func requestsAreDistinctByFingerprint() throws {
        let ledger = Fixtures.ledger()
        let first = Fixtures.request("a", fingerprint: "bounds-1")
        let second = Fixtures.request("a", fingerprint: "bounds-2")
        let reserved = try ledger.reserve([first, second, first], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(reserved.count == 2)
        #expect(reserved[first]?.sequence.rawValue == "1")
        #expect(reserved[second]?.sequence.rawValue == "2")
        // The later request replaced the stored reservation, so only it is reused.
        let again = try ledger.reserve([second], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(again[second] == reserved[second])
        let changed = try ledger.reserve([first], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(changed[first]?.sequence.rawValue == "3", "a changed fingerprint takes a new sequence")
    }

    @Test("An active event and its retraction never share a reservation")
    func kindsDoNotShareReservations() throws {
        let ledger = Fixtures.ledger()
        let active = Fixtures.request("a", kind: .active)
        let retraction = Fixtures.request("a", kind: .retraction)
        #expect(active.key != retraction.key)
        let reserved = try ledger.reserve([active, retraction], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(reserved[active]?.sequence != reserved[retraction]?.sequence)
    }

    @Test("Ledgers over one storage share its producer instance and counter")
    func ledgersShareOneStorage() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let first = try Fixtures.ledger(storage).reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts())
        let second = try Fixtures.ledger(storage).reserve([Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(first.values.first?.producerInstance == second.values.first?.producerInstance)
        #expect(second.values.first?.sequence.rawValue == "2")
        let other = try Fixtures.ledger().reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(other.values.first?.producerInstance != first.values.first?.producerInstance)
    }

    @Test("The instant is kept at millisecond precision, the same the lexeme prints")
    func instantIsKeptAtMillisecondPrecision() throws {
        let ledger = Fixtures.ledger()
        let inputs = [
            Date(timeIntervalSince1970: 1_791_023_400.2504),
            Date(timeIntervalSince1970: 1_791_023_400.2506),
            Date(timeIntervalSinceReferenceDate: 0.0015),
            Date(timeIntervalSince1970: 1_791_023_400)
        ]
        for (index, input) in inputs.enumerated() {
            let request = Fixtures.request("input-\(index)")
            let reservation = try #require(try ledger.reserve([request], at: input, facts: Fixtures.facts())[request])
            #expect(ExchangeInstant.utcLexeme(reservation.instant) == ExchangeInstant.utcLexeme(input))
            #expect(ExchangeInstant.millisecondsSinceEpoch(reservation.instant) == ExchangeInstant.millisecondsSinceEpoch(input))
        }
    }

    @Test("Event keys are deterministic, opaque and distinct per kind, adapter, record and revision")
    func eventKeysAreDeterministic() {
        let key = ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "v0:test:1:abc")
        #expect(key.rawValue == "QJYnsrPbiZst-026qKmvDi4tFo-IhLG57U8UgeV8dnA")
        #expect(ExchangeEventKey(kind: .retraction, adapterID: "healthkit", sourceRecord: "v0:test:1:abc").rawValue
            == "1DUNhw48VqO1miswNf2NyCKooKbEEJalqwILpnSnI1c")
        #expect(ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "v0:test:1:abc", revision: "2").rawValue
            == "LFumTOqgPPVowwziZlkJe38Fny6WhwuXWsybuA0q5NU")
        #expect(ExchangeEventKey(kind: .active, adapterID: "health-connect", sourceRecord: "record|東京").rawValue
            == "5KcJSfyiuPprLQxytaPUofKJanVJndVBMWcjPPlWdW4")
        #expect(key != ExchangeEventKey(kind: .active, adapterID: "sensorkit", sourceRecord: "v0:test:1:abc"))
        #expect(key != ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "v0:test:1:abc", revision: ""))
        #expect(key.rawValue.utf8.count == 43)
        #expect(LedgerKey.event(key).utf8.count <= 64 && LedgerKey.facts(key.rawValue).utf8.count <= 64)
        // Framing, not delimiting: moving a boundary changes the key.
        #expect(ExchangeEventKey(kind: .active, adapterID: "healthkita", sourceRecord: "bc")
            != ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "abc"))
    }

    @Test("The entries follow the documented layout")
    func entriesFollowTheLayout() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let request = Fixtures.request("a")
        let reservation = try #require(
            try Fixtures.ledger(storage).reserve([request], at: Fixtures.instant, facts: Fixtures.facts())[request]
        )
        let instance = reservation.producerInstance.uuidString.lowercased()
        let producer = try #require(try Fixtures.stored(LedgerKey.producer, in: storage))
        #expect(String(decoding: producer, as: UTF8.self) == #"{"instance":"\#(instance)","next":"2","v":1}"#)
        let event = try #require(try Fixtures.stored(LedgerKey.event(request.key), in: storage))
        let digest = try Fixtures.facts().digest
        #expect(String(decoding: event, as: UTF8.self)
            == #"{"facts":"\#(digest)","fingerprint":"context-a","instance":"\#(instance)","instant":1791023400251,"sequence":"1","v":1}"#)
        #expect(try Fixtures.keys("", in: storage) == [LedgerKey.producer, LedgerKey.event(request.key), LedgerKey.facts(digest)])
    }
}
