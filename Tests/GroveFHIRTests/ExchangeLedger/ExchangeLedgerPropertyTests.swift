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


/// SplitMix64: a seeded generator, so a failing interleaving reproduces.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}


/// Maps every handed-out (instance, sequence) to what it was handed out for; a second, different use is a reuse.
private final class ReuseOracle: @unchecked Sendable { // `events` and `reuses` are guarded by `lock`.
    struct Event: Equatable {
        let key: ExchangeEventKey
        let fingerprint: String
        let instant: Date
        let facts: ExchangeEventFacts
    }

    private struct Identifier: Hashable {
        let instance: UUID
        let sequence: UInt64
    }

    private let lock = NSLock()
    private var events: [Identifier: Event] = [:]
    private(set) var reuses: [String] = []
    private(set) var observed = 0

    func record(_ reserved: [ExchangeEventRequest: ExchangeEventReservation]) {
        lock.lock()
        defer {
            lock.unlock()
        }
        for (request, reservation) in reserved {
            observed += 1
            let identifier = Identifier(instance: reservation.handle.instance, sequence: reservation.handle.sequence)
            let event = Event(key: request.key, fingerprint: request.fingerprint, instant: reservation.instant, facts: reservation.facts)
            if let earlier = events[identifier], earlier != event {
                reuses.append("\(identifier.instance):\(identifier.sequence)")
            }
            events[identifier] = event
        }
    }
}


/// Sequences are never reused, under any interleaving and under concurrency.
@Suite
struct ExchangeLedgerPropertyTests {
    private typealias Fixtures = LedgerFixtures

    /// A storage G6 runs over: one that runs transactions one at a time, in memory or in a file, or one whose
    /// serializable transactions overlap.
    enum Backend: CaseIterable, Sendable {
        case memory
        case file
        case optimistic
    }

    /// One random step of the interleaving.
    private static func step(
        _ random: inout SeededGenerator,
        sequencer: inout ExchangeEventSequencer,
        storage: ExchangeEventSequencer.InMemoryStorage,
        pending: inout [[ExchangeEventReservation.Handle]],
        oracle: ReuseOracle
    ) throws {
        let keys = ["a", "b", "c", "d", "e", "f"]
        let instant = Fixtures.instant.addingTimeInterval(Double(Int.random(in: 0..<100, using: &random)))
        switch Int.random(in: 0..<100, using: &random) {
        case 0..<45:
            let requests = keys.filter { _ in Bool.random(using: &random) }.map { key in
                Fixtures.request(key, fingerprint: ["context-a", "context-b"].randomElement(using: &random) ?? "context-a")
            }
            let facts = try Fixtures.facts(build: String(Int.random(in: 1...3, using: &random)))
            let reserved = try sequencer.reserve(requests, at: instant, facts: facts)
            oracle.record(reserved)
            pending.append(reserved.values.map(\.handle))
        case 45..<65 where !pending.isEmpty:
            let forgetting = keys.filter { _ in Int.random(in: 0..<6, using: &random) == 0 }.map { Fixtures.key($0) }
            try sequencer.finish(pending.remove(at: Int.random(in: 0..<pending.count, using: &random)), released: true, forgetting: forgetting)
        case 65..<80 where !pending.isEmpty:
            try sequencer.finish(pending.remove(at: Int.random(in: 0..<pending.count, using: &random)), released: false, forgetting: [])
        case 80..<84:
            try sequencer.reset()
        case 84..<90:
            try sequencer.forgetReservations(madeBefore: instant)
        case 90..<95:
            // A crash: the process's holds vanish; a new process opens the same storage.
            pending.removeAll()
            sequencer = Fixtures.sequencer(storage)
        default:
            break
        }
    }

    @Test("G5: no (instance, sequence) is ever handed out for a second key, fingerprint, instant or facts", arguments: 0..<8)
    func sequencesAreNeverReused(seed: UInt64) throws {
        var random = SeededGenerator(seed: seed)
        let storage = ExchangeEventSequencer.InMemoryStorage()
        var sequencer = Fixtures.sequencer(storage)
        var pending: [[ExchangeEventReservation.Handle]] = []
        let oracle = ReuseOracle()
        for _ in 0..<2_000 {
            try Self.step(&random, sequencer: &sequencer, storage: storage, pending: &pending, oracle: oracle)
        }
        #expect(oracle.observed > 1_000)
        #expect(oracle.reuses.isEmpty, "reused: \(oracle.reuses.prefix(5))")
    }

    @Test("G6: concurrent reservations and releases with a resetting thread never collide", arguments: Backend.allCases)
    func concurrentCallsNeverCollide(backend: Backend) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let storage: any ExchangeEventSequencer.Storage = switch backend {
        case .memory: ExchangeEventSequencer.InMemoryStorage()
        case .file: try FileStorage(directory: directory)
        case .optimistic: OptimisticStorage()
        }
        let sequencer = Fixtures.sequencer(storage)
        let oracle = ReuseOracle()
        let threads = 8
        let calls = 200
        try await withThrowingTaskGroup(of: Void.self) { group in
            for thread in 0..<threads {
                group.addTask {
                    for call in 0..<calls {
                        // A few shared keys overlap across threads; every call releases what it reserved.
                        let requests = [Fixtures.request("thread-\(thread)-call-\(call)"), Fixtures.request("shared-\(call % 5)")]
                        let reserved = try sequencer.reserve(requests, at: Fixtures.instant, facts: Fixtures.facts())
                        oracle.record(reserved)
                        try sequencer.finish(reserved.values.map(\.handle), released: call.isMultiple(of: 2), forgetting: [])
                    }
                }
            }
            group.addTask {
                for _ in 0..<20 {
                    try sequencer.reset()
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            try await group.waitForAll()
        }
        #expect(oracle.observed == threads * calls * 2)
        #expect(oracle.reuses.isEmpty, "reused: \(oracle.reuses.prefix(5))")
    }
}
