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


/// The exporter is a facade over the conversion the goldens pin: its graphs are byte-identical to the old
/// entry point's under the same event, and it adds the event bookkeeping and policies the entry point left
/// to the caller.
@Suite(.serialized)
struct HealthKitFHIRExporterTests {
    private static let base = ExchangeEventContext.test()

    private static func exporter(
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in },
        sequencer: ExchangeEventSequencer = .inMemory()
    ) throws -> HealthKitFHIRExporter {
        let producer = try ExchangeProducer(
            identityScope: base.identityScope,
            subject: base.subject,
            application: base.application,
            host: base.host,
            sequencer: sequencer
        )
        var options = HealthKitFHIRExporter.Options()
        configure(&options)
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: base.repositoryScope, options: options)
    }

    /// The old entry point's graph for `sample` under `event`, the one the exporter minted for it.
    private static func reference(
        _ sample: HKSample,
        event: ExchangeEventIdentifier?,
        instant: Date,
        _ configure: (inout HealthKitConversionOptions) -> Void = { _ in }
    ) throws -> HealthKitConversion {
        var options = HealthKitConversionOptions()
        configure(&options)
        let context = HealthKitConversionContext(
            event: ExchangeEventContext(
                subject: base.subject,
                event: try #require(event),
                identityScope: base.identityScope,
                repositoryScope: base.repositoryScope,
                application: base.application,
                host: base.host,
                conversionInstant: instant
            ),
            options: options
        )
        return try HealthKitConverter.convertSample(sample, context: context).primary
    }

    private static func collect(
        _ exporter: HealthKitFHIRExporter,
        _ samples: [HKSample],
        at instant: Date = GoldenFixtures.conversionInstant
    ) throws -> (exports: [HealthKitFHIRExporter.Export], receipt: HealthKitFHIRExporter.Receipt) {
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.export(samples, at: instant) { exports.append($0) }
        return (exports, receipt)
    }

    /// The sequences a call minted, in the order the exports name them.
    private static func sequences(_ exports: [HealthKitFHIRExporter.Export]) -> [String] {
        exports.compactMap(\.sequence)
    }

    @Test("Graphs equal the old entry point's under the same event, with the same warnings")
    func graphsEqualReference() throws {
        let exporter = try Self.exporter()
        let withDevice = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let withoutToken = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(2), device: GoldenFixtures.watchWithoutUnitToken)
        let (exports, _) = try Self.collect(exporter, [withDevice, withoutToken])
        try #require(exports.count == 2)
        let instant = GoldenFixtures.conversionInstant
        let first = try Self.reference(withDevice, event: exports[0].event, instant: instant)
        let second = try Self.reference(withoutToken, event: exports[1].event, instant: instant)
        #expect(exports[0].graph?.json == first.graph.json)
        #expect(exports[1].graph?.json == second.graph.json)
        #expect(exports[0].source == HealthKitFHIRExporter.Export.Source(uuid: GoldenFixtures.uuid(1), typeIdentifier: HKQuantityTypeIdentifier.heartRate.rawValue))
        #expect(exports[0].source.sourceType == .heartRate)
        #expect(exports[0].warnings.isEmpty)
        #expect(exports[1].warnings == second.warnings.map(\.diagnostic))
        #expect(exports[1].warnings.contains(ExchangeGraphRule.mobileOmissionRecordingDevice.diagnostic))
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
        let exporter = try Self.exporter(sequencer: ExchangeEventSequencer(storage: storage))
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            shape: GoldenCase.seriesShape(uuid: 4, duration: 30)
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

    @Test("Under the automatic writer policy an Apple per-device source is the recording Device that authored the sample")
    func automaticWriterClassifiesAppleDeviceSources() throws {
        let exporter = try Self.exporter()
        let watchSource = StoredSampleFixtures.Writer(
            name: "Lukas's Apple Watch",
            bundleIdentifier: "com.apple.health.6C4B1D1E-0000-4000-8000-000000000009",
            version: "26.1",
            productType: "Watch7,12"
        )
        let fromWatch = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(7), writer: watchSource)
        let fromApp = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(8), writer: GoldenFixtures.foreignWriter)
        let (exports, _) = try Self.collect(exporter, [fromWatch, fromApp])
        let watchBundle = try #require(exports[0].graph?.bundle)
        let devices = watchBundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        let recorder = try #require(devices.first { $0.manufacturer?.value?.string == "Apple Inc." })
        #expect(recorder.deviceName?.first?.name.value?.string == "Lukas's Apple Watch")
        #expect(recorder.modelNumber?.value?.string == "Watch7,12")
        #expect(recorder.meta?.profile?.contains(Profile.groveRecordingDevice) == true)
        let provenance = try #require(watchBundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let recorderURL = try #require(watchBundle.entry?.first { $0.resource?.get(if: Device.self) == recorder }?.fullUrl?.value?.url.absoluteString)
        let author = provenance.entity?.first?.agent?.first { agent in
            agent.type?.coding?.contains { $0.code?.value?.string == "author" } == true
        }
        #expect(author?.who.reference?.value?.string == recorderURL)
        #expect(exports[0].warnings.isEmpty)
        // The application source converts exactly as the old entry point's default (`.application`) did.
        let reference = try Self.reference(fromApp, event: exports[1].event, instant: GoldenFixtures.conversionInstant)
        #expect(exports[1].graph?.json == reference.graph.json)
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
        let reference = try Self.reference(sample, event: exports[0].event, instant: GoldenFixtures.conversionInstant) { options in
            options.writer = .omit
            options.udiDisclosure = .authorizedUDI
            options.nativeIdentifierDisclosure = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        }
        // Only `Bundle.id` differs from the entry point's graph under the same policies.
        var expected = reference.graph.bundle
        expected.id = GoldenFixtures.uuid(9).uuidString.asFHIRStringPrimitive()
        #expect(bundle == expected)
    }

    @Test("A native identifier under a deployment system is refused at configuration")
    func reservedNativeIdentifierSystemIsRefused() throws {
        let system = Self.base.identityScope.systems.opaque.sourceRecord
        #expect(throws: HealthKitFHIRExporter.ConfigurationError.reservedNativeIdentifierSystem(system)) {
            try Self.exporter { $0.nativeIdentifier = .authorized(system: system) }
        }
    }

    @Test("Retractions take their own events and recompute the targets the old entry point computed")
    func retractionsMatchReference() throws {
        let exporter = try Self.exporter()
        let detectedAt = GoldenFixtures.conversionInstant
        let deletions = [
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(10), sourceType: .heartRate, deletedAfter: GoldenFixtures.sampleStart, detectedAt: detectedAt),
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(11), sourceType: .bloodPressureSystolic, deletedAfter: nil, detectedAt: detectedAt),
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(12), sourceType: .bloodPressure, deletedAfter: nil, detectedAt: detectedAt)
        ]
        var exports: [HealthKitFHIRExporter.Export] = []
        let receipt = try exporter.retract(deletions, at: detectedAt) { exports.append($0) }
        try #require(exports.count == 3)
        // Outcomes arrive in input order; the systolic component never emitted outputs.
        guard case .nothingToRetract = exports[1].outcome else {
            Issue.record("a systolic component never emitted outputs; expected nothingToRetract, got \(exports[1].outcome)")
            return
        }
        #expect(exports.map(\.source.uuid) == [GoldenFixtures.uuid(10), GoldenFixtures.uuid(11), GoldenFixtures.uuid(12)])
        #expect(Set(Self.sequences(exports)) == ["1", "2"])
        for (export, deletion) in [(exports[0], deletions[0]), (exports[2], deletions[2])] {
            let context = HealthKitConversionContext(event: ExchangeEventContext(
                subject: Self.base.subject,
                event: try #require(export.event),
                identityScope: Self.base.identityScope,
                repositoryScope: Self.base.repositoryScope,
                application: Self.base.application,
                host: Self.base.host,
                conversionInstant: detectedAt
            ))
            let reference = try HealthKitConverter.retraction(
                for: HealthKitSourceRecord(uuid: deletion.uuid, type: deletion.sourceType),
                context: context,
                occurred: .period(start: deletion.deletedAfter, end: detectedAt)
            )
            #expect(export.graph?.json == reference.graph.json)
        }
        receipt.release()
        let (afterRelease, _) = try Self.collect(exporter, [try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(13))])
        #expect(afterRelease[0].sequence == "3")
    }

    @Test("Deletions of types without outputs touch no ledger; a skewed lower bound is dropped, Bundle.id follows the legacy policy")
    func retractionBoundsAndLedger() throws {
        let storage = LedgerCountingStorage()
        let exporter = try Self.exporter({ $0.legacyBundleID = .healthKitUUID }, sequencer: ExchangeEventSequencer(storage: storage))
        let detectedAt = GoldenFixtures.conversionInstant
        var exports: [HealthKitFHIRExporter.Export] = []
        _ = try exporter.retract(
            [HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(20), sourceType: .bloodPressureSystolic, deletedAfter: nil, detectedAt: detectedAt)],
            at: detectedAt
        ) { exports.append($0) }
        #expect(storage.take().transactions == 0)
        _ = try exporter.export([HKSample](), at: detectedAt) { exports.append($0) }
        #expect(storage.take().transactions == 0)
        _ = try exporter.retract(
            [HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(21), sourceType: .heartRate, deletedAfter: detectedAt + 60, detectedAt: detectedAt)],
            at: detectedAt
        ) { exports.append($0) }
        let bundle = try #require(exports.last?.graph?.bundle)
        #expect(bundle.id?.value?.string == GoldenFixtures.uuid(21).uuidString)
        let provenance = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        guard case .period(let period)? = provenance.occurred else {
            Issue.record("expected a period")
            return
        }
        #expect(period.start == nil)
        #expect(period.end != nil)
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
