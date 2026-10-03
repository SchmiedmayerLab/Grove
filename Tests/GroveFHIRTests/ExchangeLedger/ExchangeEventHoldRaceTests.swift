//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Dispatch
import Foundation
@testable import GroveFHIRContract
import Testing


/// Blocks the next transaction until signalled, so a test can run another call before it.
private final class GateStorage: ExchangeEventSequencer.Storage, @unchecked Sendable { // `gateNext` is guarded by `lock`.
    let base = ExchangeEventSequencer.InMemoryStorage()
    /// Signalled when the gated transaction is reached.
    let entered = DispatchSemaphore(value: 0)
    /// Lets the gated transaction run.
    let proceed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var gateNext = false

    func gate() {
        lock.lock()
        defer {
            lock.unlock()
        }
        gateNext = true
    }

    func transaction<R>(_ body: (any ExchangeEventSequencer.Transaction) throws -> R) throws -> R {
        lock.lock()
        let gated = gateNext
        gateNext = false
        lock.unlock()
        if gated {
            entered.signal()
            proceed.wait()
        }
        return try base.transaction(body)
    }
}


/// What a call on another thread reserved, empty when it threw; read only after that thread signalled.
private final class ReservedBox: @unchecked Sendable {
    var reserved: [ExchangeEventRequest: ExchangeEventReservation] = [:]
}


/// A release racing a reserve of the same key never removes a reservation the reserve reuses.
@Suite
struct ExchangeEventHoldRaceTests {
    private typealias Fixtures = LedgerFixtures

    @Test("G9f: a reserve that commits between the last holder's end and its removal keeps the reservation")
    func reserveBeforeTheRemovalTransaction() throws {
        let storage = GateStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("race")
        let facts = try Fixtures.facts()
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        let handles = first.values.map(\.handle)
        let finished = DispatchSemaphore(value: 0)
        storage.gate()
        Thread {
            try? sequencer.finish(handles, released: true, forgetting: [])
            finished.signal()
        }.start()
        // The last holder has ended its hold and waits to open its removal transaction; another call reserves now.
        storage.entered.wait()
        let second = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        storage.proceed.signal()
        finished.wait()
        #expect(second == first)
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage.base) != nil, "the second call still holds it")
        let redelivery = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        #expect(redelivery == first, "its redelivery is an exact retry")
        try sequencer.finish(second.values.map(\.handle) + redelivery.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage.base) == nil)
        #expect(!Fixtures.mayBeReused(first[request]?.handle, by: sequencer))
    }

    @Test("G9f: a release while a reserve of the key is in flight keeps the reservation for that reserve")
    func releaseWhileAReserveIsInFlight() throws {
        let storage = GateStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("race")
        let facts = try Fixtures.facts()
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        let box = ReservedBox()
        let reserved = DispatchSemaphore(value: 0)
        storage.gate()
        Thread {
            box.reserved = (try? sequencer.reserve([request], at: Fixtures.instant, facts: facts)) ?? [:]
            reserved.signal()
        }.start()
        // The second call registered its reserve and waits to open its transaction; the last holder releases now.
        storage.entered.wait()
        try sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage.base) != nil)
        storage.proceed.signal()
        reserved.wait()
        #expect(box.reserved == first, "the second call reused the reservation")
    }

    @Test("G9f: a reserve in flight on another storage does not keep this ledger's reservation")
    func reserveInFlightElsewhereKeepsNothing() throws {
        let registry = HoldRegistry()
        let other = GateStorage()
        let request = Fixtures.request("race")
        let facts = try Fixtures.facts()
        let reserved = DispatchSemaphore(value: 0)
        other.gate()
        Thread {
            _ = try? ExchangeEventSequencer(storage: other, holds: registry).reserve([request], at: Fixtures.instant, facts: facts)
            reserved.signal()
        }.start()
        // The same key is in flight on another ledger while this one releases it.
        other.entered.wait()
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = ExchangeEventSequencer(storage: storage, holds: registry)
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        try sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage) == nil)
        other.proceed.signal()
        reserved.wait()
    }
}
