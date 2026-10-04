//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import ModelsR4


/// Fixtures the ledger tests share.
enum LedgerFixtures {
    struct InvalidCanonical: Error {}
    struct UnfreezableFacts: Error {}

    static let instant = Date(timeIntervalSince1970: 1_791_023_400.251)
    static let instantMilliseconds: Int64 = 1_791_023_400_251

    static func key(_ record: String, kind: ExchangeGraph.Kind = .active) -> ExchangeEventKey {
        ExchangeEventKey(kind: kind, adapterID: "healthkit", sourceRecord: record)
    }

    static func request(_ record: String, fingerprint: String = "context-a", kind: ExchangeGraph.Kind = .active) -> ExchangeEventRequest {
        ExchangeEventRequest(key: key(record, kind: kind), fingerprint: fingerprint)
    }

    /// Facts naming application build `build`, so tests can tell facts apart, prepared as a producer prepares them.
    static func facts(build: String = "100", operatingSystem: String = "26.0", studies: [StudyEnrollment] = []) throws -> PreparedFacts {
        try prepared(ExchangeEventFacts(
            application: try ApplicationDevice(name: "Grove Test", bundleIdentifier: "org.grovealliance.test", version: "1.0", build: build),
            host: try HostDevice(operatingSystemVersion: operatingSystem, name: "Host", manufacturer: "Example", modelNumber: "Phone1"),
            studies: studies
        ))
    }

    static func prepared(_ facts: ExchangeEventFacts) throws -> PreparedFacts {
        guard let prepared = PreparedFacts(facts) else {
            throw UnfreezableFacts()
        }
        return prepared
    }

    static func enrollment(_ name: String, protocolURL: String, version: String = "1") throws -> StudyEnrollment {
        let system: IdentifierSystem = "https://study.example.org/fhir/study"
        let enrollments: IdentifierSystem = "https://study.example.org/fhir/enrollment"
        guard let canonical = protocolURL.asFHIRCanonicalPrimitive() else {
            throw InvalidCanonical()
        }
        return try StudyEnrollment(
            study: BusinessIdentifier(system: system, value: name),
            protocolURL: canonical,
            protocolVersion: version,
            enrollment: BusinessIdentifier(system: enrollments, value: "\(name)-p-1")
        )
    }

    /// A sequencer with its own hold registry, so a test sees only its own holds; a new registry over the
    /// same storage simulates a new process.
    static func sequencer(_ storage: any ExchangeEventSequencer.Storage = ExchangeEventSequencer.InMemoryStorage()) -> ExchangeEventSequencer {
        ExchangeEventSequencer(storage: storage, holds: HoldRegistry())
    }

    /// Whether a call through `sequencer`'s registry holds `handle` or is about to.
    static func isHeld(_ handle: ExchangeEventReservation.Handle?, by sequencer: ExchangeEventSequencer) -> Bool {
        handle.map { sequencer.holds.isHeld($0) } ?? false
    }

    /// The raw value stored under `key`.
    static func stored(_ key: String, in storage: any ExchangeEventSequencer.Storage) throws -> Data? {
        try storage.transaction { try $0.read(key) }
    }

    /// Writes raw entries, bypassing the sequencer.
    static func seed(_ entries: [String: String], in storage: any ExchangeEventSequencer.Storage) throws {
        try storage.transaction { transaction in
            for (key, value) in entries {
                try transaction.write(Data(value.utf8), for: key)
            }
        }
    }

    /// Every stored key under `prefix`.
    static func keys(_ prefix: String, in storage: any ExchangeEventSequencer.Storage) throws -> Set<String> {
        Set(try storage.transaction { try $0.keys(prefixedBy: prefix) })
    }
}
