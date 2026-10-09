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
import Testing


/// A retraction receipt forgets the deleted record's active reservation only when its own ledger generation made it and
/// no live call still holds it: a receipt from before `reset()` releases nothing, and a live export keeps its event.
@Suite
struct HealthKitFHIRExporterForgetTests {
    private typealias Fixtures = ExporterFixtures

    @Test("G10/G11: a retraction receipt from before a reset forgets no reservation minted after it", arguments: [false, true])
    func preResetRetractionReceiptKeepsAPostResetReservation(exportLapses: Bool) async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC0))
        let key = try #require(ExchangeEventKey.active(sample))
        // A retraction of the same record, still unreleased when the ledger is reset.
        let retraction = try await Fixtures.retract(exporter, [Fixtures.deletion(0xC0)])
        try exporter.producer.resetLedger()
        // An export after the reset, whose receipt stays live or lapses: either way its redelivery is an exact retry.
        var first: [HealthKitFHIRExporter.Export] = []
        var receipt: ExchangeProducer.Receipt? = try await exporter.export([sample], at: GoldenFixtures.conversionInstant) { first.append($0) }
        if exportLapses {
            receipt = nil
        }
        #expect(first[0].sequence == "1")
        retraction.receipt.release()
        #expect(try storage.holdsReservation(for: key), "a receipt from before the reset releases nothing")
        let (again, againReceipt) = try await Fixtures.collect(exporter, samples: [sample])
        #expect(again[0].event == first[0].event, "a redelivery before release reuses the event")
        #expect(again[0].graph?.json == first[0].graph?.json, "a redelivery before release is byte-identical")
        receipt?.release()
        againReceipt.release()
    }

    @Test("G9/G11: a released retraction leaves a live export's reservation to it; that call's last finish removes it")
    func releasedRetractionLeavesALiveExportItsEvent() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC1))
        let key = try #require(ExchangeEventKey.active(sample))
        var first: [HealthKitFHIRExporter.Export] = []
        var receipt: ExchangeProducer.Receipt? = try await exporter.export([sample], at: GoldenFixtures.conversionInstant) { first.append($0) }
        try await Fixtures.retract(exporter, [Fixtures.deletion(0xC1)]).receipt.release()
        #expect(try storage.holdsReservation(for: key), "the live export still holds its event")
        // A redelivery whose receipt lapses at once, as a call that threw does.
        let again = try await Fixtures.collect(exporter, samples: [sample]).exports
        #expect(again[0].event == first[0].event, "the live export's redelivery is an exact retry")
        #expect(again[0].graph?.json == first[0].graph?.json)
        #expect(try storage.holdsReservation(for: key), "the first call still holds it")
        // No holder released it, but the retraction forgot it: the last holder to finish removes it, even by a lapse.
        #expect(receipt != nil)
        receipt = nil
        #expect(try !storage.holdsReservation(for: key), "the last holder to finish removes what the retraction forgot")
    }
}

#endif
