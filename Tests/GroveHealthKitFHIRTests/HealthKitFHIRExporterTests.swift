//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


/// The exporter numbers events and applies its policies around the conversion the goldens pin: a graph it delivers
/// within a call is byte-identical to the one it delivers for the same record alone under the same event.
@Suite(.serialized)
struct HealthKitFHIRExporterTests {
    private static let base = ExchangeEventContext.test()

    private static func exporter(
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in },
        storage: any ExchangeProducer.Storage = ExchangeProducer.InMemoryStorage()
    ) throws -> HealthKitFHIRExporter {
        let producer = try ExchangeProducer(
            identityScope: base.identityScope,
            subject: base.subject,
            application: base.application,
            host: base.host,
            storage: storage
        )
        var options = HealthKitFHIRExporter.Options()
        configure(&options)
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: base.repositoryScope, options: options)
    }

    private static func collect(
        _ exporter: HealthKitFHIRExporter,
        _ samples: [HKSample],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.export(samples, at: instant) { exports.append($0) }
        return (exports, receipt)
    }

    /// The sequences a call minted, in the order the exports name them.
    private static func sequences(_ exports: [HealthKitFHIRExporter.Export]) -> [String] {
        exports.compactMap(\.sequence)
    }

    @Test("Graphs equal the ones each record exports to alone under the same event, with the same warnings")
    func graphsEqualReference() throws {
        let exporter = try Self.exporter()
        let withDevice = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let withoutToken = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(2), device: GoldenFixtures.watchWithoutUnitToken)
        let (exports, _) = try Self.collect(exporter, [withDevice, withoutToken])
        try #require(exports.count == 2)
        let first = try ExporterFixtures.standalone(.sample(withDevice), as: exports[0].event)
        let second = try ExporterFixtures.standalone(.sample(withoutToken), as: exports[1].event)
        #expect(exports[0].graph?.json == first.graph.json)
        #expect(exports[1].graph?.json == second.graph.json)
        #expect(exports[0].source == HealthKitFHIRExporter.Export.Source(uuid: GoldenFixtures.uuid(1), typeIdentifier: HKQuantityTypeIdentifier.heartRate.rawValue))
        #expect(exports[0].source.sourceType == .heartRate)
        #expect(exports[0].warnings.isEmpty)
        #expect(exports[1].warnings == second.warnings)
        #expect(exports[1].warnings == [ExchangeGraphRule.mobileOmissionRecordingDevice.diagnostic])
        // New events number consecutively in the sorted order of their requests, under one producer instance.
        #expect(Set(Self.sequences(exports)) == ["1", "2"])
        #expect(exports[0].event?.producerInstance == exports[1].event?.producerInstance)
    }

    @Test("A redelivery before release reproduces the same bytes; after release it is a new event")
    func redeliveryReproducesEvents() throws {
        let exporter = try Self.exporter()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(3))
        let (first, receipt) = try Self.collect(exporter, [sample])
        let (again, _) = try Self.collect(exporter, [sample], at: GoldenFixtures.conversionInstant.addingTimeInterval(3_600))
        #expect(first[0].graph?.json == again[0].graph?.json)
        receipt.release()
        let (afterRelease, _) = try Self.collect(exporter, [sample])
        #expect(afterRelease[0].sequence == "2")
        #expect(afterRelease[0].graph?.json != first[0].graph?.json)
    }

    @Test("An unconvertible record is refused in place, holds its reservation until the receipt is released, and the export continues")
    func refusalsDoNotEndTheExport() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Self.exporter(storage: storage)
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            facts: GoldenCase.seriesFacts(uuid: 4, duration: 30)
        )
        let heartRate = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(5))
        let (exports, receipt) = try Self.collect(exporter, [ecg, heartRate])
        try #require(exports.count == 2)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.evidenceRequired))
        #expect(exports[0].graph == nil)
        #expect(["1", "2"].contains(exports[1].sequence ?? ""))
        // Nothing is released mid-call: the refused ECG keeps its reservation until the receipt is released.
        let ecgKey = try #require(ExchangeEventKey.active(ecg))
        #expect(try storage.holdsReservation(for: ecgKey))
        let (retry, retryReceipt) = try Self.collect(exporter, [ecg])
        guard case .refused = retry[0].outcome else {
            Issue.record("expected a refusal")
            return
        }
        let (next, _) = try Self.collect(exporter, [try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(6))])
        #expect(next[0].sequence == "3", "the refused ECG's redelivery reused its reservation")
        receipt.release()
        retryReceipt.release()
        #expect(try !storage.holdsReservation(for: ecgKey))
    }

    @Test("The omit policies state nothing and never warn; the legacy Bundle.id keeps the HealthKit UUID")
    func policiesApply() throws {
        let exporter = try Self.exporter { options in
            options.recordingDevice = .omit
            options.writer = .omit
            options.legacyBundleID = .healthKitUUID
            options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            options.udi = .authorized
            options.role = .gatewayForOwnWrites
        }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(9), device: GoldenFixtures.watchWithoutUnitToken, writer: GoldenFixtures.foreignWriter)
        let (exports, _) = try Self.collect(exporter, [sample])
        let bundle = try #require(exports[0].graph?.bundle)
        #expect(exports[0].warnings.isEmpty)
        #expect(bundle.id?.value?.string == GoldenFixtures.uuid(9).uuidString)
        let devices = bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        #expect(devices.allSatisfy { $0.meta?.profile?.contains(Profile.groveRecordingDevice) == false })
        #expect(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first?.entity?.first?.agent == nil)
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first)
        #expect(observation.identifier?.contains { $0.system?.value?.url.absoluteString == GoldenFixtures.nativeIdentifierSystem.rawValue } == true)
        var referenceInputs = ExportInputs()
        referenceInputs.options.udi = .authorized
        referenceInputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        referenceInputs.options.role = .gatewayForOwnWrites
        let reference = try ExporterFixtures.standalone(.sample(sample), as: exports[0].event, referenceInputs)
        // Only `Bundle.id` differs from the graph under the default device, writer and Bundle.id policies.
        var expected = reference.graph.bundle
        expected.id = GoldenFixtures.uuid(9).uuidString.asFHIRStringPrimitive()
        #expect(bundle == expected)
    }

    @Test("The UDI an HKDevice supplies reaches its recording Device only under Options.udi .authorized")
    func udiFollowsItsOption() throws {
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(13), device: GoldenFixtures.watch)
        func carriedUDIs(_ udi: HealthKitFHIRExporter.Disclosure) throws -> [String] {
            let (exports, _) = try Self.collect(Self.exporter { $0.udi = udi }, [sample])
            let devices = exports.first?.graph?.bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
            return devices.flatMap { $0.udiCarrier ?? [] }.compactMap { $0.deviceIdentifier?.value?.string }
        }
        #expect(try carriedUDIs(.authorized) == ["(01)00844588003288"])
        #expect(try carriedUDIs(.omit).isEmpty)
    }

    @Test("Both bounds of an effective Period keep their milliseconds in the source's offset")
    func effectivePeriodKeepsMilliseconds() throws {
        let start = GoldenFixtures.sampleStart.addingTimeInterval(0.2514)
        let steps = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 120),
            start: start,
            end: start.addingTimeInterval(60.4982),
            metadata: GoldenFixtures.timeZoneMetadata
        )
        let sample = try StoredSampleFixtures.stored(steps, uuid: GoldenFixtures.uuid(14))
        let (exports, _) = try Self.collect(Self.exporter(), [sample])
        let observation = try #require(exports.first?.graph?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first)
        guard case .period(let period)? = observation.effective else {
            Issue.record("A step count is effective over a Period")
            return
        }
        #expect(period.start?.value?.description == "2026-08-17T15:30:00.251-07:00")
        #expect(period.end?.value?.description == "2026-08-17T15:31:00.750-07:00")
    }

    @Test("A native identifier under a deployment system is refused at configuration")
    func reservedNativeIdentifierSystemIsRefused() throws {
        let system = Self.base.identityScope.systems.sourceRecord
        #expect(throws: HealthKitFHIRExporter.ConfigurationError.reservedNativeIdentifierSystem(system)) {
            try Self.exporter { $0.nativeIdentifier = .authorized(system: system) }
        }
    }

    @Test("Retractions take their own events and recompute the targets a retraction of each deletion alone computes")
    func retractionsMatchReference() throws {
        let exporter = try Self.exporter()
        let detectedAt = GoldenFixtures.conversionInstant
        let deletions = [
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(10), sourceType: .heartRate, deletedAfter: GoldenFixtures.sampleStart, detectedAt: detectedAt),
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(11), sourceType: .bloodPressureSystolic, deletedAfter: nil, detectedAt: detectedAt),
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(12), sourceType: .bloodPressure, deletedAfter: nil, detectedAt: detectedAt)
        ]
        var retractions: [HealthKitFHIRExporter.Retraction] = []
        let receipt = try exporter.retract(deletions, at: detectedAt) { retractions.append($0) }
        try #require(retractions.count == 3)
        // Outcomes arrive in input order; the systolic component never emitted outputs.
        guard case .nothingToRetract = retractions[1].outcome else {
            Issue.record("a systolic component never emitted outputs; expected nothingToRetract, got \(retractions[1].outcome)")
            return
        }
        #expect(retractions.map(\.deletion) == deletions)
        #expect(Set(retractions.compactMap(\.sequence)) == ["1", "2"])
        for (retraction, deletion) in [(retractions[0], deletions[0]), (retractions[2], deletions[2])] {
            let reference = try ExporterFixtures.standalone(deletion, as: retraction.event)
            #expect(retraction.graph?.json == reference?.json)
        }
        receipt.release()
        let (afterRelease, _) = try Self.collect(exporter, [try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(13))])
        #expect(afterRelease[0].sequence == "3")
    }

    @Test("Deletions of types without outputs touch no ledger; a skewed lower bound is dropped, Bundle.id follows the legacy policy")
    func retractionBoundsAndLedger() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Self.exporter({ $0.legacyBundleID = .healthKitUUID }, storage: storage)
        let detectedAt = GoldenFixtures.conversionInstant
        var retractions: [HealthKitFHIRExporter.Retraction] = []
        _ = try exporter.retract(
            [HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(20), sourceType: .bloodPressureSystolic, deletedAfter: nil, detectedAt: detectedAt)],
            at: detectedAt
        ) { retractions.append($0) }
        #expect(storage.take().transactions == 0)
        _ = try exporter.export([HKSample](), at: detectedAt) { _ in }
        #expect(storage.take().transactions == 0)
        _ = try exporter.retract(
            [HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(21), sourceType: .heartRate, deletedAfter: detectedAt + 60, detectedAt: detectedAt)],
            at: detectedAt
        ) { retractions.append($0) }
        let bundle = try #require(retractions.last?.graph?.bundle)
        #expect(bundle.id?.value?.string == GoldenFixtures.uuid(21).uuidString)
        let provenance = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        guard case .period(let period)? = provenance.occurred else {
            Issue.record("expected a period")
            return
        }
        #expect(period.start == nil)
        #expect(period.end != nil)
    }

    @Test("F1: an exported workout is its session alone, and its retraction targets exactly that session")
    func workoutExportAndRetraction() throws {
        let exporter = try Self.exporter()
        let workout = try StoredSampleFixtures.stored(GoldenFixtures.workout(withEvents: true), uuid: GoldenFixtures.uuid(0xA3))
        let (exports, _) = try Self.collect(exporter, [workout])
        let observations = try #require(exports.first?.graph?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) })
        try #require(observations.count == 1)
        let session = try #require(observations[0].identifier?.first { (try? RoledIdentifier($0).role) == .sourceOutput }?.value?.value?.string)
        var retractions: [HealthKitFHIRExporter.Retraction] = []
        let deletion = HealthKitFHIRExporter.Deletion(uuid: workout.uuid, sourceType: .workout, deletedAfter: nil, detectedAt: GoldenFixtures.conversionInstant)
        _ = try exporter.retract([deletion], at: GoldenFixtures.conversionInstant) { retractions.append($0) }
        let provenance = try #require(retractions.first?.graph?.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        #expect(provenance.target.compactMap { $0.identifier?.value?.value?.string } == [session])
    }

    /// One refusal per record, chosen in a fixed order whatever the options: content, then writer, then sync pair.
    @Test("A record with several faults reports its content first, then its writer, then its sync pair")
    func refusalOrderIsContentWriterSyncPair() throws {
        let exporter = try Self.exporter { $0.writer = .classify { _ in .application } }
        var writer = GoldenFixtures.foreignWriter
        writer.bundleIdentifier = "not a bundle id"
        func heartRate(_ ordinal: UInt8, _ metadata: [String: Any]) throws -> HKQuantitySample {
            try StoredSampleFixtures.withMetadata(GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(ordinal), writer: writer), metadata)
        }
        let samples = [
            try heartRate(0xD1, [HKMetadataKeyHeartRateMotionContext: 99, HKMetadataKeySyncIdentifier: "half"]),
            try heartRate(0xD2, [HKMetadataKeySyncIdentifier: "half"])
        ]
        let (exports, _) = try Self.collect(exporter, samples)
        let reasons = exports.map { export -> HealthKitConversionError? in
            guard case .refused(let reason) = export.outcome else {
                return nil
            }
            return reason
        }
        #expect(reasons == [.invalidValue(.heartRate, .unsupportedMetadataValue(.heartRateMotionContext)), .sourceApplicationInvalid])
    }

    @Test("An export shares one receipt; an error in the receiver ends the call with the reservations kept")
    func receiverErrorsPropagate() throws {
        struct Stop: Error {}
        let exporter = try Self.exporter()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(14))
        #expect(throws: Stop.self) {
            try exporter.export([sample]) { _ in throw Stop() }
        }
        let (again, _) = try Self.collect(exporter, [sample])
        #expect(again[0].sequence == "1")
    }
}


#endif
