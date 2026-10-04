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


/// Forwards to a storage and blocks the next transaction until signalled, before it starts or after it committed,
/// so a test can run another call in between.
private final class GateStorage: ExchangeEventSequencer.Storage, @unchecked Sendable { // `gate` is guarded by `lock`.
    enum Point {
        /// Before the transaction starts.
        case before
        /// After the transaction committed, before it returns to the sequencer.
        case afterCommit
    }

    let base: any ExchangeEventSequencer.Storage
    /// Signalled when the gated transaction reaches its point.
    let entered = DispatchSemaphore(value: 0)
    /// Lets the gated transaction continue.
    let proceed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var gateNext: Point?

    init(base: any ExchangeEventSequencer.Storage = ExchangeEventSequencer.InMemoryStorage()) {
        self.base = base
    }

    func gate(_ point: Point = .before) {
        lock.lock()
        defer {
            lock.unlock()
        }
        gateNext = point
    }

    func transaction<R>(_ body: (any ExchangeEventSequencer.Transaction) throws -> R) throws -> R {
        lock.lock()
        let gated = gateNext
        gateNext = nil
        lock.unlock()
        if gated == .before {
            wait()
        }
        let result = try base.transaction(body)
        if gated == .afterCommit {
            wait()
        }
        return result
    }

    private func wait() {
        entered.signal()
        proceed.wait()
    }
}


/// Another object in front of one storage, as an application may build per call.
private final class StorageWrapper: ExchangeEventSequencer.Storage {
    let base: any ExchangeEventSequencer.Storage

    init(_ base: any ExchangeEventSequencer.Storage) {
        self.base = base
    }

    func transaction<R>(_ body: (any ExchangeEventSequencer.Transaction) throws -> R) throws -> R {
        try base.transaction(body)
    }
}


/// A value in front of one storage, which has no object identity at all.
private struct StorageValue: ExchangeEventSequencer.Storage {
    let base: any ExchangeEventSequencer.Storage

    func transaction<R>(_ body: (any ExchangeEventSequencer.Transaction) throws -> R) throws -> R {
        try base.transaction(body)
    }
}


/// What a call on another thread reserved, empty when it threw; read only after that thread signalled.
private final class ReservedBox: @unchecked Sendable {
    var reserved: [ExchangeEventRequest: ExchangeEventReservation] = [:]
}


/// A release racing a reuse of the same reservation: what was reserved first, reused, kept and redelivered.
private struct ReuseOutcome {
    let first: ExchangeEventReservation?
    let reused: ExchangeEventReservation?
    let kept: Bool
    let redelivery: ExchangeEventReservation?
}


/// A release racing a reserve of the same key never removes a reservation the reserve is about to hold, through
/// whichever object or value in front of the storage either call goes.
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
        #expect(!Fixtures.isHeld(first[request]?.handle, by: sequencer))
    }

    @Test("G9f: a release whose transaction runs before a waiting reserve's removes the reservation; that reserve holds a new one")
    func releaseBeforeAWaitingReserve() throws {
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
        // The second call waits to open its transaction, so it has seen nothing yet; the last holder releases now.
        storage.entered.wait()
        try sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage.base) == nil)
        storage.proceed.signal()
        reserved.wait()
        let second = try #require(box.reserved[request])
        #expect(second.handle != first[request]?.handle, "the second call's transaction ran after the removal")
        let redelivery = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        #expect(redelivery == box.reserved, "the second call's redelivery is an exact retry of its own event")
    }

    /// The last holder releases through `holder` while a reserve through `reuser` has committed its reuse of the same
    /// reservation but not yet taken its hold; then the reusing call redelivers before it releases.
    private func releaseDuringAReuse(
        holder: any ExchangeEventSequencer.Storage,
        reuser: any ExchangeEventSequencer.Storage,
        gate: GateStorage,
        backing: any ExchangeEventSequencer.Storage
    ) throws -> ReuseOutcome {
        let registry = HoldRegistry()
        let holding = ExchangeEventSequencer(storage: holder, holds: registry)
        let reusing = ExchangeEventSequencer(storage: reuser, holds: registry)
        let request = Fixtures.request("wrapped")
        let facts = try Fixtures.facts()
        let first = try holding.reserve([request], at: Fixtures.instant, facts: facts)
        let box = ReservedBox()
        let reserved = DispatchSemaphore(value: 0)
        gate.gate(.afterCommit)
        Thread {
            box.reserved = (try? reusing.reserve([request], at: Fixtures.instant, facts: facts)) ?? [:]
            reserved.signal()
        }.start()
        // The reuse committed and returns to its sequencer, which has not taken its hold yet.
        gate.entered.wait()
        try holding.finish(first.values.map(\.handle), released: true, forgetting: [])
        let kept = try Fixtures.stored(LedgerKey.event(request.key), in: backing) != nil
        gate.proceed.signal()
        reserved.wait()
        let redelivery = try reusing.reserve([request], at: Fixtures.instant, facts: facts)
        return ReuseOutcome(first: first[request], reused: box.reserved[request], kept: kept, redelivery: redelivery[request])
    }

    @Test("G9f: a release keeps a reservation a call is about to hold through another object or value over one storage", arguments: [false, true])
    func releaseKeepsAReuseThroughAnotherFront(throughValues: Bool) throws {
        let backing = ExchangeEventSequencer.InMemoryStorage()
        let gate = GateStorage(base: backing)
        let holder: any ExchangeEventSequencer.Storage = throughValues ? StorageValue(base: backing) : StorageWrapper(backing)
        let reuser: any ExchangeEventSequencer.Storage = throughValues ? StorageValue(base: gate) : gate
        let outcome = try releaseDuringAReuse(holder: holder, reuser: reuser, gate: gate, backing: backing)
        #expect(outcome.reused != nil && outcome.reused == outcome.first, "the second call reused the reservation")
        #expect(outcome.kept, "the release removed a reservation the second call is about to hold")
        #expect(outcome.redelivery == outcome.reused, "the second call's redelivery is an exact retry")
    }

    @Test("G9f: a release keeps a reservation a call is about to hold through another file storage on the same directory")
    func releaseKeepsAReuseThroughAnotherFileStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let holder = try FileStorage(directory: directory)
        let gate = GateStorage(base: try FileStorage(directory: directory))
        let outcome = try releaseDuringAReuse(holder: holder, reuser: gate, gate: gate, backing: holder)
        #expect(outcome.reused != nil && outcome.reused == outcome.first, "the second call reused the reservation")
        #expect(outcome.kept, "the release removed a reservation the second call is about to hold")
        #expect(outcome.redelivery == outcome.reused, "the second call's redelivery is an exact retry")
    }

    @Test("G9f: a reservation another ledger is about to hold under the same key does not keep this ledger's")
    func reserveOfTheKeyElsewhereKeepsNothing() throws {
        let registry = HoldRegistry()
        let other = GateStorage()
        let request = Fixtures.request("race")
        let facts = try Fixtures.facts()
        let reserved = DispatchSemaphore(value: 0)
        other.gate(.afterCommit)
        Thread {
            _ = try? ExchangeEventSequencer(storage: other, holds: registry).reserve([request], at: Fixtures.instant, facts: facts)
            reserved.signal()
        }.start()
        // Another ledger committed a reservation of the same key and is about to hold it while this one releases.
        other.entered.wait()
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let sequencer = ExchangeEventSequencer(storage: storage, holds: registry)
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        try sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage) == nil)
        other.proceed.signal()
        reserved.wait()
    }

    @Test("G9f: over a storage whose transactions overlap, a release can remove a reservation a call just reused; a duplicate, never a reuse")
    func overlappingTransactionsDuplicateNeverReuse() throws {
        let storage = OptimisticStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("overlap")
        let facts = try Fixtures.facts()
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        let finished = DispatchSemaphore(value: 0)
        storage.gate()
        Thread {
            try? sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
            finished.signal()
        }.start()
        // The release found no holder and staged its removal; a reuse commits before the release validates.
        storage.entered.wait()
        let second = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        storage.proceed.signal()
        finished.wait()
        let held = try #require(second[request])
        #expect(second == first, "the reuse committed first")
        // As the storage article states: the holder's redelivery takes a new sequence, never one handed out before.
        let redelivery = try #require(try sequencer.reserve([request], at: Fixtures.instant, facts: facts)[request])
        #expect(redelivery.handle.instance == held.handle.instance)
        #expect(redelivery.handle.sequence > held.handle.sequence)
    }

    /// G9d under a race: the last holder releases while another call reuses the reservation, either committed but not yet
    /// holding it (`reuseHoldsBeforeRemoval` false) or fully holding it before the release's transaction opens (true).
    @Test("G9d: a release racing a reuse keeps its mark; the reusing call's lapse removes the reservation", arguments: [false, true])
    func releaseRacingAReuseThenLapse(reuseHoldsBeforeRemoval: Bool) throws {
        let storage = GateStorage()
        let sequencer = Fixtures.sequencer(storage)
        let request = Fixtures.request("race")
        let facts = try Fixtures.facts()
        let first = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
        let reused: [ExchangeEventRequest: ExchangeEventReservation]
        if reuseHoldsBeforeRemoval {
            // The last holder ended its hold and waits to open its removal transaction; another call reuses it now.
            let finished = DispatchSemaphore(value: 0)
            storage.gate()
            Thread {
                try? sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
                finished.signal()
            }.start()
            storage.entered.wait()
            reused = try sequencer.reserve([request], at: Fixtures.instant, facts: facts)
            storage.proceed.signal()
            finished.wait()
        } else {
            // Another call's reuse committed and is still noted as reserving when the last holder releases.
            let box = ReservedBox()
            let reserved = DispatchSemaphore(value: 0)
            storage.gate(.afterCommit)
            Thread {
                box.reserved = (try? sequencer.reserve([request], at: Fixtures.instant, facts: facts)) ?? [:]
                reserved.signal()
            }.start()
            storage.entered.wait()
            try sequencer.finish(first.values.map(\.handle), released: true, forgetting: [])
            storage.proceed.signal()
            reserved.wait()
            reused = box.reserved
        }
        #expect(reused == first, "the second call reused the reservation")
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage.base) != nil, "the second call still holds it")
        // The reusing call is dropped unreleased, as the loser of an anchor compare-exchange is; it is the last holder.
        try sequencer.finish(reused.values.map(\.handle), released: false, forgetting: [])
        #expect(!Fixtures.isHeld(first[request]?.handle, by: sequencer))
        #expect(try Fixtures.stored(LedgerKey.event(request.key), in: storage.base) == nil, "a holder released it; the last finisher removes it")
    }
}
