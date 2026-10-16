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


/// Runs the next transaction's body once and discards that attempt, then runs the body again and commits it: what a
/// storage that retries a conflicting attempt does.
private final class RetryingStorage: ExchangeProducer.Storage, @unchecked Sendable { // `retryNext` is guarded by `lock`.
    private struct Discarded: Error {}

    let base = ExchangeProducer.InMemoryStorage()
    private let lock = NSLock()
    private var retryNext = false

    /// Discards the next transaction's first attempt.
    func retry() {
        lock.lock()
        defer {
            lock.unlock()
        }
        retryNext = true
    }

    func transaction<R>(_ body: (any ExchangeProducer.Transaction) throws -> R) throws -> R {
        lock.lock()
        let retrying = retryNext
        retryNext = false
        lock.unlock()
        if retrying {
            _ = try? base.transaction { transaction -> R in
                _ = try body(transaction)
                throw Discarded()
            }
        }
        return try base.transaction(body)
    }
}


/// Holds, releases, lapses and the receipts' transaction budget.
@Suite
struct ExchangeEventHoldTests {
    private typealias Fixtures = LedgerFixtures

    private static func isReserved(_ request: ExchangeEventRequest, in storage: any ExchangeProducer.Storage) throws -> Bool {
        try Fixtures.stored(LedgerKey.event(request.key), in: storage) != nil
    }

    @Test("G8: a lapsed hold keeps the reservation; the redelivery reuses event and facts and its release removes it")
    func lapseKeepsTheReservation() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let request = Fixtures.request("a")
        let first = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "100"))
        try ledger.finish(first.values.map(\.handle), released: false, forgetting: [])
        #expect(try Self.isReserved(request, in: storage))
        let again = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "110"))
        #expect(again == first)
        try ledger.finish(again.values.map(\.handle), released: true, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
        #expect(!Fixtures.isHeld(again[request]?.handle, by: ledger))
    }

    @Test("G8: after a crash between reserve and release, the next process reuses and removes the reservation")
    func crashLeavesTheReservationForTheNextProcess() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let request = Fixtures.request("a")
        let first = try Fixtures.ledger(storage).reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "100"))
        let restarted = Fixtures.ledger(storage)
        let again = try restarted.reserve([request], at: Fixtures.instant, facts: Fixtures.facts(build: "110"))
        #expect(again == first)
        try restarted.finish(again.values.map(\.handle), released: true, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
    }

    @Test("G9a: of two overlapping holders, the first release keeps the event and the last finisher removes it")
    func overlappingHoldersRemoveOnLastFinish() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let request = Fixtures.request("a")
        let live = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        let bulk = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(live == bulk)
        try ledger.finish(live.values.map(\.handle), released: true, forgetting: [])
        #expect(try Self.isReserved(request, in: storage), "the slower call still holds the event")
        #expect(try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts()) == live, "its redelivery is an exact retry")
        try ledger.finish(live.values.map(\.handle), released: false, forgetting: [])
        #expect(try Self.isReserved(request, in: storage))
        try ledger.finish(bulk.values.map(\.handle), released: true, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
    }

    @Test("G9d: when the releasing holder finishes first and the other is dropped, the dropped one removes the event")
    func lapseAfterAnotherReleaseRemoves() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let request = Fixtures.request("a")
        let winner = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        let loser = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(winner.values.map(\.handle), released: true, forgetting: [])
        try ledger.finish(loser.values.map(\.handle), released: false, forgetting: [])
        #expect(try !Self.isReserved(request, in: storage))
        #expect(!Fixtures.isHeld(winner[request]?.handle, by: ledger))
    }

    @Test("G9: a reserve whose body the storage runs twice notes each reservation once; the release removes it")
    func retriedReserveNotesOnce() throws {
        let storage = RetryingStorage()
        let ledger = Fixtures.ledger(storage)
        let request = Fixtures.request("a")
        let first = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        storage.retry()
        let again = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(again == first, "both attempts reuse the reservation")
        try ledger.finish(first.values.map(\.handle) + again.values.map(\.handle), released: true, forgetting: [])
        #expect(!Fixtures.isHeld(first[request]?.handle, by: ledger), "nothing stays noted after the retried call")
        #expect(try !Self.isReserved(request, in: storage.base), "the release removes the reservation")
    }

    @Test("G10: a handle from before a reset releases nothing, and a replaced reservation is not removed")
    func releaseIsOwned() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let request = Fixtures.request("a")
        let before = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.reset()
        let after = try ledger.reserve([request], at: Fixtures.instant, facts: Fixtures.facts())
        #expect(after[request]?.producerInstance != before[request]?.producerInstance)
        #expect(after[request]?.sequence.rawValue == "1")
        try ledger.finish(before.values.map(\.handle), released: true, forgetting: [])
        #expect(try Self.isReserved(request, in: storage))
        let replaced = Fixtures.request("a", fingerprint: "context-b")
        let successor = try ledger.reserve([replaced], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(after.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.ledger(storage).reserve([replaced], at: Fixtures.instant, facts: Fixtures.facts()) == successor)
    }

    @Test("G10: nothing to release opens no transaction; a reserve and its release take one each")
    func releaseIsCheap() throws {
        let storage = CountingStorage()
        let ledger = Fixtures.ledger(storage)
        try ledger.finish([], released: true, forgetting: [])
        try ledger.finish([], released: false, forgetting: [Fixtures.key("a")])
        #expect(storage.takeCounts().transactions == 0)
        let reserved = try ledger.reserve([Fixtures.request("a"), Fixtures.request("b")], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(reserved.values.map(\.handle), released: true, forgetting: [Fixtures.key("c")])
        #expect(storage.takeCounts().transactions == 2)
        let lapsed = try ledger.reserve([Fixtures.request("d")], at: Fixtures.instant, facts: Fixtures.facts())
        _ = storage.takeCounts()
        try ledger.finish(lapsed.values.map(\.handle), released: false, forgetting: [])
        #expect(storage.takeCounts().transactions == 0, "a lapse with no released holder touches nothing")
    }

    @Test("Forgetting removes a key's reservation of the caller's own instance, and only on release")
    func forgettingIsOwnedAndOnlyOnRelease() throws {
        let storage = CountingStorage()
        let ledger = Fixtures.ledger(storage)
        let active = Fixtures.request("a")
        let retraction = Fixtures.request("a", kind: .retraction)
        let lapsed = try ledger.reserve([active], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(lapsed.values.map(\.handle), released: false, forgetting: [])
        let dropped = try ledger.reserve([retraction], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(dropped.values.map(\.handle), released: false, forgetting: [active.key])
        #expect(try Self.isReserved(active, in: storage), "a lapse forgets nothing")
        _ = storage.takeCounts()
        try ledger.finish([], released: true, forgetting: [active.key])
        #expect(storage.takeCounts().transactions == 0, "a caller that holds nothing owns nothing to forget")
        #expect(try Self.isReserved(active, in: storage))
        let released = try ledger.reserve([retraction], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(released.values.map(\.handle), released: true, forgetting: [active.key])
        #expect(try !Self.isReserved(active, in: storage))
    }

    @Test("G10: forgetting from before a reset removes nothing minted after it")
    func forgettingFromBeforeAResetRemovesNothing() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let active = Fixtures.request("a")
        let retraction = try ledger.reserve([Fixtures.request("a", kind: .retraction)], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.reset()
        let after = try ledger.reserve([active], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(after.values.map(\.handle), released: false, forgetting: [])
        try ledger.finish(retraction.values.map(\.handle), released: true, forgetting: [active.key])
        #expect(try Self.isReserved(active, in: storage), "a receipt from before the reset releases nothing")
        #expect(try ledger.reserve([active], at: Fixtures.instant, facts: Fixtures.facts()) == after)
    }

    @Test("G9: forgetting a reservation a live call holds leaves it to that call, whose finish removes it")
    func forgettingAHeldReservationHandsItOver() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let ledger = Fixtures.ledger(storage)
        let active = Fixtures.request("a")
        let live = try ledger.reserve([active], at: Fixtures.instant, facts: Fixtures.facts())
        let retraction = try ledger.reserve([Fixtures.request("a", kind: .retraction)], at: Fixtures.instant, facts: Fixtures.facts())
        try ledger.finish(retraction.values.map(\.handle), released: true, forgetting: [active.key])
        #expect(try Self.isReserved(active, in: storage), "the live call still holds it")
        #expect(try ledger.reserve([active], at: Fixtures.instant, facts: Fixtures.facts()) == live, "its redelivery is an exact retry")
        try ledger.finish(live.values.map(\.handle), released: false, forgetting: [])
        #expect(try Self.isReserved(active, in: storage), "the redelivery still holds it")
        try ledger.finish(live.values.map(\.handle), released: false, forgetting: [])
        #expect(try !Self.isReserved(active, in: storage), "the last holder to finish removes what the retraction forgot")
        #expect(!Fixtures.isHeld(live[active]?.handle, by: ledger))
    }
}
