//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// One call's ledger budget, its early exits, and what its receipt keeps.
@Suite
struct HealthKitFHIRExporterCallTests {
    private typealias Fixtures = ExporterFixtures

    @Test("An instant FHIR cannot state ends an export or retraction before the ledger is touched")
    func unstatableInstantEndsTheCall() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(sequencer: ExchangeEventSequencer(storage: storage))
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC5))
        let afterYear9999 = Date(timeIntervalSince1970: 253_402_300_800)
        #expect(throws: ExchangeIdentityError.invalidInstant) {
            try exporter.export([sample], at: afterYear9999) { _ in }
        }
        #expect(throws: ExchangeIdentityError.invalidInstant) {
            try exporter.retract([Fixtures.deletion(0xC5)], at: afterYear9999) { _ in }
        }
        #expect(storage.take() == (transactions: 0, writes: 0))
    }
}

#endif
