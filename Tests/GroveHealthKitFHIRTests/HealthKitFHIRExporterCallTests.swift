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


/// One call's early exits, and what it compares against.
@Suite
struct HealthKitFHIRExporterCallTests {
    private typealias Fixtures = ExporterFixtures

    /// Whether the record's Observation names a gateway Device.
    private static func statesGateway(_ export: HealthKitFHIRExporter.Export) -> Bool {
        let observation = export.record?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first
        return observation?.extension?.contains { $0.url == Canonicals.gatewayDevice } == true
    }

    @Test("An instant FHIR cannot state ends an export or retraction before anything is built")
    func unstatableInstantEndsTheCall() async throws {
        let exporter = try Fixtures.exporter()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xC5))
        let afterYear9999 = Date(timeIntervalSince1970: 253_402_300_800)
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.export([sample], at: afterYear9999) { _ in Issue.record("nothing is handed over") }
        }
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.retract([Fixtures.deletion(0xC5)], at: afterYear9999) { _ in Issue.record("nothing is handed over") }
        }
    }

    @Test("Under gatewayForOwnWrites a conversion compares the build that runs, so an app update is a new version")
    func gatewayForOwnWritesComparesTheRunningBuild() async throws {
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xD0), writer: GoldenFixtures.selfWriter(revisionVersion: "100"))
        // The app wrote the sample in build 100 and converts it there; the redelivery runs after an update to build 110.
        let exporters = try ["100", "110"].map { build in
            try Fixtures.exporter(try Fixtures.producer(application: GoldenFixtures.selfConverter(version: "1.0", build: build))) {
                $0.role = .gatewayForOwnWrites
            }
        }
        let first = try await Fixtures.collect(exporters[0], samples: [sample])
        #expect(Self.statesGateway(first[0]), "build 100 wrote the sample, so it mediated it")
        let renewed = try await Fixtures.collect(exporters[1], samples: [sample])
        #expect(!Self.statesGateway(renewed[0]), "build 110 did not write the sample")
        #expect(renewed[0].record?.sourceRecord == first[0].record?.sourceRecord)
        #expect(renewed[0].record?.version != first[0].record?.version)
    }

    @Test("A deletion with nothing to retract delivers no record")
    func nothingToRetractDeliversNoRecord() async throws {
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: GoldenFixtures.uuid(0xD4),
            sourceType: .bloodPressureSystolic,
            deletedAfter: nil,
            detectedAt: GoldenFixtures.conversionInstant
        )
        let retractions = try await Fixtures.retract(Fixtures.exporter(), [deletion])
        guard case .nothingToRetract = retractions.first?.outcome else {
            Issue.record("expected nothing to retract, got \(String(describing: retractions.first?.outcome))")
            return
        }
        #expect(retractions.first?.record == nil)
    }
}

#endif
