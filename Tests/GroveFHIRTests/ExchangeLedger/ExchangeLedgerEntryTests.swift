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


/// A ledger whose `a` reservation or producer entry is corrupt or from a later layout.
struct CorruptLedger: Sendable, CustomTestStringConvertible {
    static let all: [CorruptLedger] = [
        CorruptLedger(name: "non-JSON", event: "not json"),
        CorruptLedger(name: "sequence zero", event: ExchangeLedgerEntryTests.event(sequence: "0")),
        CorruptLedger(name: "non-canonical sequence", event: ExchangeLedgerEntryTests.event(sequence: "05")),
        CorruptLedger(name: "sequence at the counter", event: ExchangeLedgerEntryTests.event(sequence: "7")),
        CorruptLedger(name: "invalid instance", event: ExchangeLedgerEntryTests.event(instance: "not-a-uuid")),
        CorruptLedger(name: "instance without a version", event: ExchangeLedgerEntryTests.event(instance: "00000000-0000-0000-0000-000000000000")),
        CorruptLedger(
            name: "no version",
            event: #"{"facts":"<digest>","fingerprint":"x","instance":"\#(ExchangeLedgerEntryTests.instance)","instant":1,"sequence":"1"}"#
        ),
        CorruptLedger(name: "later version", event: ExchangeLedgerEntryTests.event(version: 2)),
        CorruptLedger(
            name: "counter zero",
            event: ExchangeLedgerEntryTests.event(),
            producer: #"{"instance":"\#(ExchangeLedgerEntryTests.instance)","next":"0","v":1}"#
        ),
        CorruptLedger(
            name: "producer of a later version",
            event: ExchangeLedgerEntryTests.event(),
            producer: #"{"instance":"\#(ExchangeLedgerEntryTests.instance)","next":"9","v":3}"#
        )
    ]

    let name: String
    let event: String
    var producer: String?

    var testDescription: String { name }
}


/// Stored entries: facts, reset, pruning, validation, atomicity and cost.
@Suite
struct ExchangeLedgerEntryTests {
    private typealias Fixtures = LedgerFixtures

    fileprivate static let instance = "1f5c58aa-6ec6-4e79-a682-829a9debd3f5"

    /// A ledger holding one reservation for `a` under `instance`, with the current facts stored.
    private static func seededLedger(event: String, producer: String? = nil) throws -> ExchangeEventSequencer.InMemoryStorage {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let facts = try Fixtures.facts()
        try storage.transaction { try $0.write(facts.bytes, for: LedgerKey.facts(facts.digest)) }
        try Fixtures.seed(
            [
                LedgerKey.producer: producer ?? #"{"instance":"\#(instance)","next":"7","v":1}"#,
                LedgerKey.event(Fixtures.key("a")): event.replacingOccurrences(of: "<digest>", with: facts.digest)
            ],
            in: storage
        )
        return storage
    }

    fileprivate static func event(instance: String = Self.instance, sequence: String = "5", version: Int = 1) -> String {
        #"{"facts":"<digest>","fingerprint":"context-a","instance":"\#(instance)","instant":1791023400251,"sequence":"\#(sequence)","v":\#(version)}"#
    }

    @Test("G18: facts with several studies, a versioned canonical and absent host fields decode to themselves")
    func factsRoundTrip() throws {
        let studies = [
            try Fixtures.enrollment("a", protocolURL: "https://study.example.org/PlanDefinition/a|2.1"),
            try Fixtures.enrollment("b", protocolURL: "https://study.example.org/PlanDefinition/b", version: "7")
        ]
        let facts = ExchangeEventFacts(
            application: try ApplicationDevice(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0"),
            host: try HostDevice(operatingSystemVersion: "26.0.1"),
            studies: studies
        )
        let prepared = try Fixtures.prepared(facts)
        #expect(prepared.facts == facts)
        #expect(try PreparedFacts.decode(prepared.bytes, key: "facts/x") == facts)
        #expect(try Fixtures.prepared(prepared.facts).bytes == prepared.bytes, "encoding is deterministic")
        #expect(try Fixtures.facts(build: "101").digest != prepared.digest)
        let current = ExchangeEventFacts(
            application: try ApplicationDevice(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0"),
            host: HostDevice.current(),
            studies: []
        )
        #expect(try Fixtures.prepared(current).facts == current)
    }

    @Test("Equal facts are stored once and shared across reservations and instances")
    func factsAreDeduplicated() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        _ = try sequencer.reserve([Fixtures.request("a"), Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        _ = try sequencer.reserve([Fixtures.request("c")], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(try Fixtures.keys(LedgerKey.factsPrefix, in: storage).count == 1)
        _ = try sequencer.reserve([Fixtures.request("d")], at: Fixtures.instant, facts: Fixtures.facts(build: "101"))
        #expect(try Fixtures.keys(LedgerKey.factsPrefix, in: storage).count == 2)
    }

    @Test("G12: reset mints a new instance numbering from one, forgets the facts, and old handles are no-ops")
    func resetStartsOver() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let old = try sequencer.reserve([Fixtures.request("a"), Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        try sequencer.reset()
        #expect(try Fixtures.keys("", in: storage).isEmpty)
        let fresh = try sequencer.reserve([Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        let reservation = try #require(fresh.values.first)
        #expect(reservation.sequence.rawValue == "1")
        #expect(!old.values.contains { $0.producerInstance == reservation.producerInstance })
        try sequencer.finish(old.values.map(\.handle), released: true, forgetting: [])
        #expect(try sequencer.reserve([Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts()) == fresh)
    }

    @Test("G13: forgetting removes reservations made before the cutoff and the facts nothing references")
    func forgettingPrunesExplicitly() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let start = Fixtures.instant
        _ = try sequencer.reserve([Fixtures.request("old-1"), Fixtures.request("old-2")], at: start, facts: Fixtures.facts(build: "1"))
        _ = try sequencer.reserve([Fixtures.request("mid")], at: start + 60, facts: Fixtures.facts(build: "2"))
        let kept = try sequencer.reserve([Fixtures.request("new")], at: start + 120, facts: Fixtures.facts(build: "2"))
        #expect(try sequencer.forgetReservations(madeBefore: start) == 0)
        #expect(try sequencer.forgetReservations(madeBefore: start + 60) == 2)
        #expect(try Fixtures.keys(LedgerKey.factsPrefix, in: storage) == [LedgerKey.facts(try Fixtures.facts(build: "2").digest)])
        #expect(try sequencer.forgetReservations(madeBefore: start + 61) == 1)
        #expect(try Fixtures.keys(LedgerKey.eventPrefix, in: storage) == [LedgerKey.event(Fixtures.key("new"))])
        #expect(try sequencer.reserve([Fixtures.request("new")], at: start + 500, facts: Fixtures.facts(build: "3")) == kept)
        let renewed = try sequencer.reserve([Fixtures.request("old-1")], at: start + 500, facts: Fixtures.facts())
        #expect(renewed.values.first?.sequence.rawValue == "5", "a forgotten key is a new event; no sequence is reused")
    }

    @Test("G14: corrupt and future entries throw typed errors, never trap, and reset recovers", arguments: CorruptLedger.all)
    func corruptEntriesAreRefused(_ corrupt: CorruptLedger) throws {
        let storage = try Self.seededLedger(event: corrupt.event, producer: corrupt.producer)
        let sequencer = Fixtures.sequencer(storage)
        #expect(throws: ExchangeEventSequencer.LedgerError.self, "\(corrupt.name)") {
            try sequencer.reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts())
        }
        try sequencer.reset()
        let recovered = try sequencer.reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(recovered.values.first?.sequence.rawValue == "1")
    }

    @Test("G14: each fault names its entry and kind")
    func faultsAreTyped() throws {
        let eventKey = LedgerKey.event(Fixtures.key("a"))
        let request = Fixtures.request("a")
        let facts = try Fixtures.facts()
        let future = Fixtures.sequencer(try Self.seededLedger(event: Self.event(version: 2)))
        #expect(throws: ExchangeEventSequencer.LedgerError.unsupportedEntryVersion(key: eventKey, version: 2)) {
            try future.reserve([request], at: Fixtures.instant, facts: facts)
        }
        let regressed = Fixtures.sequencer(try Self.seededLedger(event: Self.event(sequence: "8")))
        #expect(throws: ExchangeEventSequencer.LedgerError.corruptEntry(key: eventKey)) {
            try regressed.reserve([request], at: Fixtures.instant, facts: facts)
        }
        let retired = try Self.seededLedger(event: Self.event(instance: "2eafba7b-4c21-4bf5-ad46-351b0176b25a", sequence: "8"))
        #expect(try Fixtures.sequencer(retired).reserve([request], at: Fixtures.instant, facts: facts)[request]?.sequence.rawValue == "8")
        let missingFacts = try Self.seededLedger(event: Self.event())
        try missingFacts.transaction { try $0.remove(LedgerKey.facts(facts.digest)) }
        #expect(throws: ExchangeEventSequencer.LedgerError.corruptEntry(key: eventKey)) {
            try Fixtures.sequencer(missingFacts).reserve([request], at: Fixtures.instant, facts: facts)
        }
        let blankName = try Self.seededLedger(event: Self.event())
        let factsKey = LedgerKey.facts(facts.digest)
        let stored = String(decoding: try #require(try Fixtures.stored(factsKey, in: blankName)), as: UTF8.self)
        try Fixtures.seed([factsKey: stored.replacingOccurrences(of: #""name":"Grove Test""#, with: #""name":" ""#)], in: blankName)
        #expect(throws: ExchangeEventSequencer.LedgerError.corruptEntry(key: factsKey)) {
            try Fixtures.sequencer(blankName).reserve([request], at: Fixtures.instant, facts: facts)
        }
        #expect(throws: ExchangeEventSequencer.LedgerError.corruptEntry(key: eventKey)) {
            try Fixtures.sequencer(try Self.seededLedger(event: "[]")).forgetReservations(madeBefore: Fixtures.instant)
        }
    }

    @Test("A reservation under a retired instance stays valid; an overflowing counter mints a new instance")
    func counterOverflowRotatesTheInstance() throws {
        let storage = try Self.seededLedger(
            event: Self.event(sequence: "5"),
            producer: #"{"instance":"\#(Self.instance)","next":"18446744073709551615","v":1}"#
        )
        let sequencer = Fixtures.sequencer(storage)
        let reserved = try sequencer.reserve([Fixtures.request("a"), Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(reserved[Fixtures.request("a")]?.sequence.rawValue == "5")
        let rotated = try #require(reserved[Fixtures.request("b")])
        #expect(rotated.sequence.rawValue == "1")
        #expect(rotated.producerInstance.uuidString.lowercased() != Self.instance)
    }

    @Test("G7: a failure mid-reserve or at commit stores nothing and holds nothing; a retry numbers consecutively")
    func failuresAreAtomic() throws {
        let storage = FaultyStorage()
        let sequencer = Fixtures.sequencer(storage)
        _ = try sequencer.reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts())
        let before = try Fixtures.keys("", in: storage.base)
        let requests = ["b", "c", "d"].map { Fixtures.request($0) }
        for write in 1...4 {
            storage.failWrite(write)
            #expect(throws: FaultyStorage.Fault()) {
                try sequencer.reserve(requests, at: Fixtures.instant, facts: Fixtures.facts(build: "200"))
            }
        }
        storage.failWrite(nil)
        storage.failAtCommit(true)
        #expect(throws: FaultyStorage.Fault()) {
            try sequencer.reserve(requests, at: Fixtures.instant, facts: Fixtures.facts(build: "200"))
        }
        storage.failAtCommit(false)
        #expect(try Fixtures.keys("", in: storage.base) == before)
        #expect(sequencer.holds.count == 1, "only the first call's hold")
        let retried = try sequencer.reserve(requests, at: Fixtures.instant, facts: Fixtures.facts(build: "200"))
        #expect(Set(retried.values.map(\.sequence.rawValue)) == ["2", "3", "4"])
    }

    @Test("Storage errors propagate from reserve, finish, reset and forgetting; a failed release keeps the reservation")
    func storageErrorsPropagate() throws {
        let storage = FaultyStorage()
        let sequencer = Fixtures.sequencer(storage)
        let reserved = try sequencer.reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts())
        storage.failAtCommit(true)
        #expect(throws: FaultyStorage.Fault()) { try sequencer.finish(reserved.values.map(\.handle), released: true, forgetting: []) }
        #expect(throws: FaultyStorage.Fault()) { try sequencer.reset() }
        #expect(throws: FaultyStorage.Fault()) { try sequencer.forgetReservations(madeBefore: .distantFuture) }
        storage.failAtCommit(false)
        #expect(try sequencer.reserve([Fixtures.request("a")], at: Fixtures.instant, facts: Fixtures.facts()) == reserved)
    }

    @Test("G15: an export's cost does not depend on the ledger's size")
    func costIsIndependentOfLedgerSize() throws {
        let storage = CountingStorage()
        let sequencer = Fixtures.sequencer(storage)
        let seeded = (0..<100_000).map { Fixtures.request("seed-\($0)") }
        _ = try sequencer.reserve(seeded, at: Fixtures.instant, facts: Fixtures.facts())
        _ = storage.takeCounts()
        let fresh = ["x", "y", "z"].map { Fixtures.request($0) }
        _ = try sequencer.reserve(fresh, at: Fixtures.instant, facts: Fixtures.facts())
        let minting = storage.takeCounts()
        #expect(minting.transactions == 1 && minting.reads <= 5 && minting.writes <= 5 && minting.listings == 0)
        _ = try sequencer.reserve(fresh, at: Fixtures.instant, facts: Fixtures.facts())
        let reusing = storage.takeCounts()
        #expect(reusing.transactions == 1 && reusing.reads <= 5 && reusing.writes == 0 && reusing.listings == 0)
    }
}
