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
import ModelsR4
import Testing


/// One call's ledger budget, its early exits, and what its receipt keeps.
@Suite
struct HealthKitFHIRExporterCallTests {
    private typealias Fixtures = ExporterFixtures

    /// Whether the graph's Observation names a gateway Device.
    private static func statesGateway(_ export: HealthKitFHIRExporter.Export) -> Bool {
        let observation = export.graph?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first
        return observation?.extension?.contains { $0.url == Canonicals.gatewayDevice } == true
    }

    @Test("An instant FHIR cannot state ends an export or retraction before the ledger is touched")
    func unstatableInstantEndsTheCall() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC5))
        let afterYear9999 = Date(timeIntervalSince1970: 253_402_300_800)
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.export([sample], at: afterYear9999) { _ in }
        }
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.retract([Fixtures.deletion(0xC5)], at: afterYear9999) { _ in }
        }
        #expect(storage.take() == (transactions: 0, writes: 0))
    }

    @Test("G2: under gatewayForOwnWrites a redelivery after an app update compares with the frozen build, byte for byte")
    func gatewayForOwnWritesComparesTheFrozenBuild() async throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xD0), writer: GoldenFixtures.selfWriter(revisionVersion: "100"))
        // The app wrote the sample in build 100 and converts it there; the redelivery runs after an update to build 110.
        let exporters = try ["100", "110"].map { build in
            try Fixtures.exporter(try Fixtures.producer(application: GoldenFixtures.selfConverter(version: "1.0", build: build), storage: storage)) {
                $0.role = .gatewayForOwnWrites
            }
        }
        let (first, firstReceipt) = try await Fixtures.collect(exporters[0], samples: [sample])
        #expect(Self.statesGateway(first[0]), "build 100 wrote the sample, so it mediated it")
        let (again, againReceipt) = try await Fixtures.collect(exporters[1], samples: [sample])
        #expect(again[0].event == first[0].event)
        #expect(again[0].graph?.json == first[0].graph?.json)
        firstReceipt.release()
        againReceipt.release()
        let (renewed, _) = try await Fixtures.collect(exporters[1], samples: [sample])
        #expect(renewed[0].event != first[0].event)
        #expect(!Self.statesGateway(renewed[0]), "a new event compares with build 110, which did not write the sample")
    }

    @Test("A retraction reserves every deletion in one transaction, and its release takes one more")
    func retractionTakesOneReserveTransaction() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let (retractions, receipt) = try await Fixtures.retract(exporter, [Fixtures.deletion(0xD1), Fixtures.deletion(0xD2), Fixtures.deletion(0xD3)])
        #expect(Set(retractions.compactMap(\.sequence)) == ["1", "2", "3"])
        #expect(storage.take().transactions == 1)
        receipt.release()
        #expect(storage.take().transactions == 1)
    }

    @Test("A retraction with nothing to retract reserves nothing, so its release owns nothing to forget and touches no ledger")
    func nothingToRetractForgetsNothing() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: GoldenFixtures.uuid(0xD4),
            sourceType: .bloodPressureSystolic,
            deletedAfter: nil,
            detectedAt: GoldenFixtures.conversionInstant
        )
        let (retractions, receipt) = try await Fixtures.retract(exporter, [deletion])
        guard case .nothingToRetract = retractions.first?.outcome else {
            Issue.record("expected nothing to retract, got \(String(describing: retractions.first?.outcome))")
            return
        }
        #expect(storage.take().transactions == 0)
        receipt.release()
        #expect(storage.take() == (transactions: 0, writes: 0))
    }

    @Test("A released receipt dropped while another call holds the same event leaves the event to that call")
    func releasedReceiptDroppedKeepsTheOtherHold() async throws {
        let storage = LedgerCountingStorage()
        let exporter = try Fixtures.exporter(storage: storage)
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xD5))
        let key = try #require(ExchangeEventKey.active(sample))
        var released: ExchangeProducer.Receipt? = try await Fixtures.collect(exporter, samples: [sample]).receipt
        let (_, holding) = try await Fixtures.collect(exporter, samples: [sample])
        released?.release()
        released = nil
        #expect(try storage.holdsReservation(for: key), "dropping a released receipt ends no hold a second time")
        holding.release()
        #expect(try !storage.holdsReservation(for: key))
    }
}

#endif
