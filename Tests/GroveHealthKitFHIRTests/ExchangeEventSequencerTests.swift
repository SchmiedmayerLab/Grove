//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Synchronization
import Testing


/// A storage that keeps the blob in memory, counts its writes, and can be reset or made to fail.
private final class LedgerStorage: ExchangeEventSequencer.Storage {
    struct Failure: Error, Equatable {}

    private struct Ledger {
        var data: Data?
        var writes = 0
        var failing = false
    }

    private let state = Mutex(Ledger())

    var data: Data? { state.withLock { $0.data } }
    var writes: Int { state.withLock { $0.writes } }

    func update<R>(_ body: (inout Data?) throws -> R) throws -> R {
        try state.withLock { stored in
            guard !stored.failing else {
                throw Failure()
            }
            var data = stored.data
            let result = try body(&data)
            if data != stored.data {
                stored.data = data
                stored.writes += 1
            }
            return result
        }
    }

    func reset() {
        state.withLock { $0 = Ledger(data: nil, writes: $0.writes, failing: false) }
    }

    func fail(_ failing: Bool) {
        state.withLock { $0.failing = failing }
    }

    func seed(_ json: String) {
        state.withLock { $0.data = Data(json.utf8) }
    }
}


@Suite
struct ExchangeEventSequencerTests {
    private static let instant = Date(timeIntervalSince1970: 1_791_023_400.251)

    private static func key(_ record: String, kind: ExchangeGraph.Kind = .active, revision: String? = nil) -> ExchangeEventKey {
        ExchangeEventKey(kind: kind, adapterID: "healthkit", sourceRecord: record, revision: revision)
    }

    @Test("New keys take consecutive sequences in input order, at the millisecond instant")
    func newKeysTakeConsecutiveSequences() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let reservations = try sequencer.reserve([Self.key("a"), Self.key("b"), Self.key("c")], at: Self.instant)
        #expect(reservations.map(\.sequence.rawValue) == ["1", "2", "3"])
        #expect(reservations.map(\.instant) == Array(repeating: ExchangeInstant.date(millisecondsSinceEpoch: 1_791_023_400_251), count: 3))
        #expect(try sequencer.reserve([Self.key("d")], at: Self.instant).map(\.sequence.rawValue) == ["4"])
    }

    @Test("A reserved key returns the same sequence and instant, whatever the later instant")
    func reservedKeyIsReturnedUnchanged() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let first = try sequencer.reserve([Self.key("a")], at: Self.instant)
        let again = try sequencer.reserve([Self.key("a")], at: Self.instant.addingTimeInterval(3600))
        #expect(again == first)
        #expect(ExchangeInstant.millisecondsSinceEpoch(again[0].instant) == 1_791_023_400_251)
        #expect(try sequencer.reserve([Self.key("b")], at: Self.instant).map(\.sequence.rawValue) == ["2"])
    }

    @Test("After release the key takes a new sequence; a sequence is never reused")
    func releasedKeyTakesNewSequence() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let first = try sequencer.reserve([Self.key("a"), Self.key("b")], at: Self.instant)
        try sequencer.release([Self.key("a")])
        let second = try sequencer.reserve([Self.key("a"), Self.key("b")], at: Self.instant)
        #expect(second[0].sequence.rawValue == "3")
        #expect(second[1] == first[1])
        try sequencer.release([Self.key("a"), Self.key("b"), Self.key("never-reserved")])
        try sequencer.release([])
        #expect(try sequencer.reserve([Self.key("b")], at: Self.instant).map(\.sequence.rawValue) == ["4"])
    }

    @Test("An active event and its retraction never share a reservation")
    func kindsDoNotShareReservations() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let active = Self.key("a", kind: .active)
        let retraction = Self.key("a", kind: .retraction)
        #expect(active != retraction)
        let reservations = try sequencer.reserve([active, retraction], at: Self.instant)
        #expect(reservations[0].sequence != reservations[1].sequence)
    }

    @Test("Duplicate keys in one call map to one reservation")
    func duplicateKeysShareOneReservation() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let reservations = try sequencer.reserve([Self.key("a"), Self.key("a"), Self.key("b"), Self.key("a")], at: Self.instant)
        #expect(reservations.map(\.sequence.rawValue) == ["1", "1", "2", "1"])
        #expect(reservations[0] == reservations[1])
    }

    @Test("The producer instance is minted once and shared by every sequencer over the same storage")
    func producerInstanceIsStableOverOneStorage() throws {
        let storage = LedgerStorage()
        let first = ExchangeEventSequencer(storage: storage)
        let second = ExchangeEventSequencer(storage: storage)
        let instance = try first.producerInstance
        #expect(try second.producerInstance == instance)
        #expect(try first.producerInstance == instance)
        #expect(storage.writes == 1, "the first read persists the minted instance; later reads do not rewrite")
        _ = try second.reserve([Self.key("a")], at: Self.instant)
        #expect(try ExchangeEventSequencer(storage: storage).producerInstance == instance)
        #expect(try ExchangeEventSequencer.inMemory().producerInstance != instance)
    }

    @Test("Reservations are durable before reserve returns, and an exact retry does not rewrite the ledger")
    func reservationsAreDurable() throws {
        let storage = LedgerStorage()
        let sequencer = ExchangeEventSequencer(storage: storage)
        let reserved = try sequencer.reserve([Self.key("a"), Self.key("b")], at: Self.instant)
        #expect(storage.writes == 1)
        let fromStorage = try ExchangeEventSequencer(storage: storage).reserve([Self.key("b"), Self.key("a")], at: Self.instant.addingTimeInterval(60))
        #expect(fromStorage == [reserved[1], reserved[0]])
        #expect(storage.writes == 1)
        let stored = try #require(storage.data)
        let state = try JSONDecoder().decode(ExchangeEventSequencer.State.self, from: stored)
        #expect(state.schemaVersion == ExchangeEventSequencer.State.currentSchemaVersion)
        #expect(state.nextSequence == 3)
        #expect(state.reservations.keys.sorted() == [Self.key("a").rawValue, Self.key("b").rawValue].sorted())
        #expect(state.reservations[Self.key("a").rawValue]?.instantMilliseconds == 1_791_023_400_251)
        #expect(state.reservations[Self.key("a").rawValue]?.reservedAtMilliseconds == 1_791_023_400_251)
    }

    @Test("A storage that restarts from nil yields a new producer instance numbering from one")
    func resetStorageYieldsNewProducerInstance() throws {
        let storage = LedgerStorage()
        let sequencer = ExchangeEventSequencer(storage: storage)
        let before = try sequencer.producerInstance
        _ = try sequencer.reserve([Self.key("a"), Self.key("b")], at: Self.instant)
        storage.reset()
        let after = try sequencer.producerInstance
        #expect(after != before)
        let reservations = try sequencer.reserve([Self.key("a")], at: Self.instant)
        #expect(reservations.map(\.sequence.rawValue) == ["1"])
        #expect(try sequencer.producerInstance == after)
    }

    @Test("Reservations older than the retention are forgotten at the next reservation")
    func retentionPrunesOldReservations() throws {
        let sequencer = ExchangeEventSequencer.inMemory(retention: .init(maximumAge: 60))
        let first = try sequencer.reserve([Self.key("a")], at: Self.instant)
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant.addingTimeInterval(59.999)) == first)
        #expect(try sequencer.reserve([Self.key("b")], at: Self.instant.addingTimeInterval(60)).map(\.sequence.rawValue) == ["2"])
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant.addingTimeInterval(60)) == first, "exactly the retention old is kept")
        _ = try sequencer.reserve([Self.key("c")], at: Self.instant.addingTimeInterval(60.001))
        let renewed = try sequencer.reserve([Self.key("a")], at: Self.instant.addingTimeInterval(60.002))
        #expect(renewed[0].sequence.rawValue == "4")
        #expect(ExchangeInstant.millisecondsSinceEpoch(renewed[0].instant) == ExchangeInstant.millisecondsSinceEpoch(Self.instant.addingTimeInterval(60.002)))
        #expect(try sequencer.reserve([Self.key("b")], at: Self.instant.addingTimeInterval(60.002)).map(\.sequence.rawValue) == ["2"])
    }

    @Test("The default retention keeps a reservation for thirty days")
    func defaultRetention() throws {
        #expect(ExchangeEventSequencer.Retention.default.maximumAge == 30 * 24 * 60 * 60)
        let sequencer = ExchangeEventSequencer.inMemory()
        #expect(sequencer.retention == .default)
        let first = try sequencer.reserve([Self.key("a")], at: Self.instant)
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant.addingTimeInterval(29 * 24 * 60 * 60)) == first)
        _ = try sequencer.reserve([Self.key("b")], at: Self.instant.addingTimeInterval(31 * 24 * 60 * 60))
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant.addingTimeInterval(31 * 24 * 60 * 60)) != first)
    }

    @Test("Storage errors propagate from reserve and release; the ignoring variant swallows them")
    func storageErrorsPropagate() throws {
        let storage = LedgerStorage()
        let sequencer = ExchangeEventSequencer(storage: storage)
        _ = try sequencer.reserve([Self.key("a")], at: Self.instant)
        storage.fail(true)
        #expect(throws: LedgerStorage.Failure()) { try sequencer.reserve([Self.key("b")], at: Self.instant) }
        #expect(throws: LedgerStorage.Failure()) { try sequencer.release([Self.key("a")]) }
        #expect(throws: LedgerStorage.Failure()) { try sequencer.producerInstance }
        sequencer.releaseIgnoringErrors([Self.key("a")])
        storage.fail(false)
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant).map(\.sequence.rawValue) == ["1"], "the failed release left the reservation")
        sequencer.releaseIgnoringErrors([Self.key("a")])
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant).map(\.sequence.rawValue) == ["2"])
    }

    @Test("Release on an empty storage stores nothing")
    func releaseOnEmptyStorageIsANoOp() throws {
        let storage = LedgerStorage()
        let sequencer = ExchangeEventSequencer(storage: storage)
        try sequencer.release([Self.key("a")])
        sequencer.releaseIgnoringErrors([Self.key("a")])
        #expect(storage.data == nil)
        #expect(storage.writes == 0)
    }

    @Test("A ledger of another schema version is refused, not misread")
    func unsupportedSchemaVersionIsRefused() throws {
        let storage = LedgerStorage()
        storage.seed(#"{"schemaVersion":99,"producerInstance":"1F5C58AA-6EC6-4E79-A682-829A9DEBD3F5","nextSequence":7,"reservations":{}}"#)
        let sequencer = ExchangeEventSequencer(storage: storage)
        #expect(throws: ExchangeEventSequencer.StateError.unsupportedSchemaVersion(99)) {
            try sequencer.reserve([Self.key("a")], at: Self.instant)
        }
        #expect(throws: ExchangeEventSequencer.StateError.unsupportedSchemaVersion(99)) { try sequencer.producerInstance }
        #expect(throws: ExchangeEventSequencer.StateError.unsupportedSchemaVersion(99)) { try sequencer.release([Self.key("a")]) }
        #expect(storage.writes == 0)
    }

    @Test("A ledger whose sequences are spent refuses a new key but still returns reserved ones")
    func exhaustedSequencesAreRefused() throws {
        let storage = LedgerStorage()
        let reserved = Self.key("a").rawValue
        storage.seed(
            #"{"schemaVersion":1,"producerInstance":"1F5C58AA-6EC6-4E79-A682-829A9DEBD3F5","nextSequence":18446744073709551615,"#
                + #""reservations":{"\#(reserved)":{"sequence":5,"instantMilliseconds":1791023400251,"reservedAtMilliseconds":1791023400251}}}"#
        )
        let sequencer = ExchangeEventSequencer(storage: storage)
        #expect(try sequencer.producerInstance == UUID(uuidString: "1F5C58AA-6EC6-4E79-A682-829A9DEBD3F5"))
        #expect(try sequencer.reserve([Self.key("a")], at: Self.instant).map(\.sequence.rawValue) == ["5"])
        #expect(throws: ExchangeEventSequencer.StateError.sequencesExhausted) {
            try sequencer.reserve([Self.key("a"), Self.key("b")], at: Self.instant)
        }
        #expect(storage.writes == 0, "a refused reservation stores nothing")
    }

    @Test("The instant is kept at millisecond precision, the same the lexeme prints")
    func instantIsKeptAtMillisecondPrecision() throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let inputs = [
            Date(timeIntervalSince1970: 1_791_023_400.2504),
            Date(timeIntervalSince1970: 1_791_023_400.2506),
            Date(timeIntervalSinceReferenceDate: 0.0015),
            Date(timeIntervalSince1970: 1_791_023_400)
        ]
        let reservations = try sequencer.reserve(inputs.indices.map { Self.key("\($0)") }, at: Self.instant)
        #expect(reservations.allSatisfy { ExchangeInstant.millisecondsSinceEpoch($0.instant) == 1_791_023_400_251 })
        for (index, input) in inputs.enumerated() {
            let reservation = try sequencer.reserve([Self.key("input-\(index)")], at: input)[0]
            #expect(ExchangeInstant.utcLexeme(reservation.instant) == ExchangeInstant.utcLexeme(input))
            #expect(ExchangeInstant.millisecondsSinceEpoch(reservation.instant) == ExchangeInstant.millisecondsSinceEpoch(input))
            #expect(reservation.instant == ExchangeInstant.date(millisecondsSinceEpoch: ExchangeInstant.millisecondsSinceEpoch(input)))
        }
    }

    @Test("Concurrent reservations from several tasks take unique sequences")
    func concurrentReservationsAreUnique() async throws {
        let sequencer = ExchangeEventSequencer.inMemory()
        let tasks = 8
        let keysPerTask = 50
        let sequences = try await withThrowingTaskGroup(of: [String].self) { group in
            for task in 0..<tasks {
                group.addTask {
                    var mine: [String] = []
                    for index in 0..<keysPerTask {
                        mine += try sequencer.reserve([Self.key("task-\(task)-key-\(index)")], at: Self.instant).map(\.sequence.rawValue)
                    }
                    return mine
                }
            }
            var all: [String] = []
            for try await sequences in group {
                all += sequences
            }
            return all
        }
        #expect(sequences.count == tasks * keysPerTask)
        #expect(Set(sequences).count == tasks * keysPerTask)
        #expect(Set(sequences.compactMap(UInt64.init)) == Set(1...UInt64(tasks * keysPerTask)))
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
        #expect(key == ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "v0:test:1:abc"))
        #expect(key != ExchangeEventKey(kind: .active, adapterID: "sensorkit", sourceRecord: "v0:test:1:abc"))
        #expect(key != ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "v0:test:1:abd"))
        #expect(key != ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "v0:test:1:abc", revision: ""))
        #expect(key.rawValue.utf8.count == 43)
        #expect(key.rawValue.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x5F })
        // Framing, not delimiting: moving a boundary changes the key.
        #expect(ExchangeEventKey(kind: .active, adapterID: "healthkita", sourceRecord: "bc")
            != ExchangeEventKey(kind: .active, adapterID: "healthkit", sourceRecord: "abc"))
    }

    @Test("Keys and reservations encode as JSON and decode to themselves")
    func keysAndReservationsRoundTripThroughJSON() throws {
        let key = Self.key("a")
        let decodedKey = try JSONDecoder().decode(ExchangeEventKey.self, from: JSONEncoder().encode(key))
        #expect(decodedKey == key)
        let reservation = try ExchangeEventSequencer.inMemory().reserve([key], at: Self.instant)[0]
        let encoded = try JSONEncoder().encode(reservation)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["sequence"] as? String == "1")
        #expect(object["instantMilliseconds"] as? Int64 == 1_791_023_400_251)
        #expect(try JSONDecoder().decode(ExchangeEventReservation.self, from: encoded) == reservation)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ExchangeEventReservation.self, from: Data(#"{"sequence":"0","instantMilliseconds":1}"#.utf8))
        }
    }
}
