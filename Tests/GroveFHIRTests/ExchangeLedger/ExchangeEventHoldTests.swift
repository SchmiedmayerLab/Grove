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


/// Holds, releases, lapses and the receipts' transaction budget.
@Suite
struct ExchangeEventHoldTests {
    private typealias Fixtures = LedgerFixtures

    private static func isReserved(_ request: ExchangeEventRequest, in storage: any ExchangeEventSequencer.Storage) throws -> Bool {
        try Fixtures.stored(LedgerKey.event(request.key), in: storage) != nil
    }

    @Test("G8: a lapsed hold keeps the reservation; the redelivery reuses event and facts and its release removes it")
    func lapseKeepsTheReservation() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("a")
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "100"))
        try sequencer.finish(first.values.map(\.handle), released: false, forgetting: [])
        #expect(try Self.isReserved(request, in: storage))
        let again = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "110"))
        #expect(again == first)
        try sequencer.finish(again.values.map(\.handle), released: true, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
        #expect(!Fixtures.isHeld(again[request]?.handle, by: sequencer))
    }

    @Test("G8: after a crash between reserve and release, the next process reuses and removes the reservation")
    func crashLeavesTheReservationForTheNextProcess() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let request = Fixtures.request("a")
        let first = try Fixtures.sequencer(storage).reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "100"))
        let restarted = Fixtures.sequencer(storage)
        let again = try restarted.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "110"))
        #expect(again == first)
        try restarted.finish(again.values.map(\.handle), released: true, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
    }

    @Test("G9a: of two overlapping holders, the first release keeps the event and the last finisher removes it")
    func overlappingHoldersRemoveOnLastFinish() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("a")
        let live = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        let bulk = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(live == bulk)
        try sequencer.finish(live.values.map(\.handle), released: true, forgetting: [])
        #expect(try Self.isReserved(request, in: storage), "the slower call still holds the event")
        #expect(try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts()) == live, "its redelivery is an exact retry")
        try sequencer.finish(live.values.map(\.handle), released: false, forgetting: [])
        #expect(try Self.isReserved(request, in: storage))
        try sequencer.finish(bulk.values.map(\.handle), released: true, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
    }

    @Test("G9d: when the releasing holder finishes first and the other is dropped, the dropped one removes the event")
    func lapseAfterAnotherReleaseRemoves() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("a")
        let winner = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        let loser = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        try sequencer.finish(winner.values.map(\.handle), released: true, forgetting: [])
        try sequencer.finish(loser.values.map(\.handle), released: false, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
        #expect(!Fixtures.isHeld(winner[request]?.handle, by: sequencer))
    }

    @Test("G10: a handle from before a reset releases nothing, and a replaced reservation is not removed")
    func releaseIsOwned() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("a")
        let before = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        try sequencer.reset()
        let after = try sequencer.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(after[request]?.producerInstance != before[request]?.producerInstance)
        #expect(after[request]?.sequence.rawValue == "1")
        try sequencer.finish(before.values.map(\.handle), released: true, forgetting: [])
        #expect(try Self.isReserved(request, in: storage))
        let replaced = Fixtures.request("a", fingerprint: "context-b")
        let successor = try sequencer.reserve([replaced], at: Fixtures.instant, facts: Fixtures.facts())
        try sequencer.finish(after.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.sequencer(storage).reserve([replaced], at: Fixtures.instant, facts: Fixtures.facts()) == successor)
    }

    @Test("G10: nothing to release opens no transaction; a reserve and its release take one each")
    func releaseIsCheap() throws {
        let storage = CountingStorage()
        let sequencer = Fixtures.sequencer(storage)
        try sequencer.finish([], released: true, forgetting: [])
        try sequencer.finish([], released: false, forgetting: [Fixtures.key("a")])
        #expect(storage.takeCounts().transactions == 0)
        let reserved = try sequencer.reserve([Fixtures.request("a"), Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        try sequencer.finish(reserved.values.map(\.handle), released: true, forgetting: [Fixtures.key("c")])
        #expect(storage.takeCounts().transactions == 2)
        let lapsed = try sequencer.reserve([Fixtures.request("d")], at: Fixtures.instant, facts: Fixtures.facts())
        _ = storage.takeCounts()
        try sequencer.finish(lapsed.values.map(\.handle), released: false, forgetting: [])
        #expect(storage.takeCounts().transactions == 0, "a lapse with no released holder touches nothing")
    }

    @Test("Forgetting removes a key whatever it holds, and only on release")
    func forgettingRemovesUnconditionally() throws {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = Fixtures.sequencer(storage)
        let active = Fixtures.request("a")
        _ = try sequencer.reserve([active], at: Fixtures.instant, facts: Fixtures.facts())
        try sequencer.finish([], released: false, forgetting: [active.key])
        #expect(try Self.isReserved(active, in: storage))
        try sequencer.finish([], released: true, forgetting: [active.key])
        #expect(try !Self.isReserved(active, in: storage))
    }
}
