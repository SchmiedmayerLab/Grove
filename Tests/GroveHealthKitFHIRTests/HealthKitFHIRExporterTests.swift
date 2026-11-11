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


/// The exporter applies its policies around the conversion the goldens pin: a record it delivers within a call is
/// byte-identical to the one it delivers for the same input alone.
@Suite
struct HealthKitFHIRExporterTests {
    private static let base = TestDeployment.test()

    private static func exporter(_ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }) throws -> HealthKitFHIRExporter {
        try ExporterFixtures.exporter(configure)
    }

    private static func collect(
        _ exporter: HealthKitFHIRExporter,
        _ samples: [HKSample],
        at instant: Date = GoldenFixtures.conversionInstant
    ) async throws -> [HealthKitFHIRExporter.Export] {
        try await ExporterFixtures.collect(exporter, samples: samples, at: instant)
    }

    @Test("Records equal the ones each input exports to alone, with the same warnings")
    func recordsEqualReference() async throws {
        let exporter = try Self.exporter()
        let withDevice = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(1), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let withoutToken = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(2), device: GoldenFixtures.watchWithoutUnitToken)
        let exports = try await Self.collect(exporter, [withDevice, withoutToken])
        try #require(exports.count == 2)
        let first = try await ExporterFixtures.export(.sample(withDevice))
        let second = try await ExporterFixtures.export(.sample(withoutToken))
        #expect(exports[0].record == first.record)
        #expect(exports[1].record == second.record)
        #expect(exports[0].source == HealthKitFHIRExporter.Export.Source(uuid: GoldenFixtures.uuid(1), typeIdentifier: HKQuantityTypeIdentifier.heartRate.rawValue))
        #expect(exports[0].source.sourceType == .heartRate)
        #expect(exports[0].warnings.isEmpty)
        #expect(exports[1].warnings == second.warnings)
        #expect(exports[1].warnings.isEmpty, "a recording Device needs no unit token, so nothing is lost")
    }

    @Test("A redelivery at the same instant is an exact retry; a later conversion is a new version of the same source record")
    func redeliveryKeepsTheRecordVersion() async throws {
        let exporter = try Self.exporter()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(3))
        let first = try #require(try await Self.collect(exporter, [sample]).first?.record)
        let again = try #require(try await Self.collect(exporter, [sample]).first?.record)
        #expect(first == again)
        let nextHour = GoldenFixtures.conversionInstant.addingTimeInterval(3_600)
        let later = try #require(try await Self.collect(exporter, [sample], at: nextHour).first?.record)
        #expect(later.sourceRecord == first.sourceRecord)
        #expect(later.outputFullURLs == first.outputFullURLs)
        #expect(later.version != first.version, "`Provenance.recorded` is part of the record's content")
    }

    @Test("Records pack into one Bundle: shared nodes are stated once, and every record keeps its version")
    func recordsPackIntoOneBundle() async throws {
        let samples = try [0x41, 0x42, 0x43].map { try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid($0), device: GoldenFixtures.watch) }
        let records = try await Self.collect(Self.exporter(), samples).compactMap(\.record)
        try #require(records.count == 3)
        #expect(Set(records.map(\.sharedNodeFullURLs)).count == 1, "equal content is one snapshot in every record")

        var packer = ExchangeBundlePacker(kind: .active)
        for record in records {
            #expect(try packer.insert(record) == .inserted)
        }
        let graph = try packer.bundle(packedAt: GoldenFixtures.conversionInstant)
        let entries = try #require(graph.bundle.entry)
        #expect(entries.compactMap { $0.resource?.get(if: Observation.self) }.count == 3)
        #expect(entries.compactMap { $0.resource?.get(if: Provenance.self) }.count == 3)
        #expect(entries.compactMap { $0.resource?.get(if: Device.self) }.count == records[0].sharedNodeFullURLs.count)
        #expect(try graph.records().map(\.version) == records.map(\.version))
        for record in records {
            try record.verifyVersion(in: Self.base.identityScope)
        }
    }

    @Test("A packed Bundle reads back the samples its records read back")
    func packedBundleReadsBackItsRecordsSamples() async throws {
        let samples = try [0x44, 0x45].map { try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid($0)) }
        let records = try await Self.collect(Self.exporter(), samples).compactMap(\.record)
        var packer = ExchangeBundlePacker(kind: .active)
        for record in records {
            _ = try packer.insert(record)
        }
        let packed = try packer.bundle(packedAt: GoldenFixtures.conversionInstant).healthKitSamples()
        let separate = records.map { $0.healthKitSamples() }
        #expect(packed.failures.isEmpty && separate.allSatisfy(\.failures.isEmpty))
        #expect(packed.conversions.count == 2)
        func syncIdentifiers(_ samples: [HKSample]) -> [String?] {
            samples.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        }
        #expect(syncIdentifiers(packed.conversions) == syncIdentifiers(separate.flatMap(\.conversions)))
    }

    @Test("Provenance.recorded is the call's instant, on every record of the call")
    func provenanceRecordedIsTheCallsInstant() async throws {
        let instant = GoldenFixtures.conversionInstant.addingTimeInterval(0.25)
        let samples = try [GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x31)), GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0x32))]
        let exports = try await Self.collect(Self.exporter(), samples, at: instant)
        let provenances = exports.compactMap { $0.record?.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first }
        let recorded = provenances.map { $0.recorded.value?.description }
        #expect(recorded == ["2026-08-17T23:30:00.25Z", "2026-08-17T23:30:00.25Z"])
    }

    @Test("An unconvertible record is refused in place, and the export continues")
    func refusalsDoNotEndTheExport() async throws {
        let ecg = try StoredSampleFixtures.seriesSample(
            HKElectrocardiogram.self,
            sampleType: HKObjectType.electrocardiogramType(),
            facts: GoldenCase.seriesFacts(uuid: 4, duration: 30)
        )
        let heartRate = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(5))
        let exports = try await Self.collect(Self.exporter(), [ecg, heartRate])
        try #require(exports.count == 2)
        guard case .refused(let reason) = exports[0].outcome else {
            Issue.record("expected a refusal, got \(exports[0].outcome)")
            return
        }
        #expect(reason == .ecgEvidence(.evidenceRequired))
        #expect(exports[0].record == nil)
        #expect(exports[1].record != nil)
    }

    @Test("A refusal reports the registry's most specific reason, and the export continues")
    func refusalsReportTheirRegisteredReason() async throws {
        let start = GoldenFixtures.sampleStart
        // A Period measurement over a minute, so the value is checked, not the effective time.
        let fractionalSteps = try StoredSampleFixtures.stored(
            HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: 1.5),
                start: start,
                end: start.addingTimeInterval(60),
                metadata: GoldenFixtures.timeZoneMetadata
            ),
            uuid: GoldenFixtures.uuid(7)
        )
        let food = HKCorrelation(
            type: HKCorrelationType(.food),
            start: start,
            end: start,
            objects: [HKQuantitySample(type: HKQuantityType(.dietaryEnergyConsumed), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 320), start: start, end: start)]
        )
        let audiogram = try StoredSampleFixtures.seriesSample(
            HKAudiogramSample.self,
            sampleType: HKObjectType.audiogramSampleType(),
            facts: GoldenCase.seriesFacts(uuid: 0xF5, duration: 0)
        )
        let prescription = try StoredSampleFixtures.seriesSample(
            HKVisionPrescription.self,
            sampleType: HKObjectType.visionPrescriptionType(),
            facts: GoldenCase.seriesFacts(uuid: 0xF6, duration: 0)
        )
        let notYetConvertible = ExchangeGraphRule.mobileInputNotYetConvertible.diagnostic(at: "HKSample.sampleType")
        let expected: [(HealthKitConversionError, ProducerDiagnostic)] = [
            (.invalidValue(.stepCount, .outsideDomain), ExchangeGraphRule.mobileInputValueOutsideDomain.diagnostic(at: "HKSample.value")),
            (.notYetConvertible(.food), notYetConvertible),
            (.notYetConvertible(.audiogram), notYetConvertible),
            (.notYetConvertible(.visionPrescription), notYetConvertible)
        ]
        let samples: [HKSample] = [fractionalSteps, food, audiogram, prescription, try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(8))]
        let exports = try await Self.collect(Self.exporter(), samples)
        try #require(exports.count == expected.count + 1)
        for (export, (error, diagnostic)) in zip(exports, expected) {
            guard case .refused(let reason) = export.outcome else {
                Issue.record("expected a refusal, got \(export.outcome)")
                continue
            }
            #expect(reason == error)
            #expect(reason.diagnostic == diagnostic)
        }
        #expect(exports.last?.record != nil)
    }

    @Test("The policies state what they name and never warn, and a record carries no Bundle.id or Bundle.identifier")
    func policiesApply() async throws {
        let exporter = try Self.exporter { options in
            options.unitToken = .none
            options.writer = .omit
            options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            options.role = .gatewayForOwnWrites
        }
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(9), device: GoldenFixtures.watch, writer: GoldenFixtures.foreignWriter)
        let exports = try await Self.collect(exporter, [sample])
        let bundle = try #require(exports[0].record?.bundle)
        #expect(exports[0].warnings.isEmpty)
        #expect(bundle.id == nil)
        #expect(bundle.identifier == nil)
        let devices = bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        #expect(devices.contains { $0.meta?.profile?.contains(Profile.groveRecordingDevice) == true })
        #expect(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first?.entity?.first?.agent == nil)
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first)
        #expect(observation.identifier?.contains { $0.system?.value?.url.absoluteString == GoldenFixtures.nativeIdentifierSystem.rawValue } == true)
    }

    @Test("Both bounds of an effective Period keep their milliseconds in the source's offset")
    func effectivePeriodKeepsMilliseconds() async throws {
        let start = GoldenFixtures.sampleStart.addingTimeInterval(0.2514)
        let steps = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 120),
            start: start,
            end: start.addingTimeInterval(60.4982),
            metadata: GoldenFixtures.timeZoneMetadata
        )
        let sample = try StoredSampleFixtures.stored(steps, uuid: GoldenFixtures.uuid(14))
        let exports = try await Self.collect(Self.exporter(), [sample])
        let observation = try #require(exports.first?.record?.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) }.first)
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

    @Test("Retractions arrive in input order and equal what each deletion retracts alone")
    func retractionsMatchReference() async throws {
        let exporter = try Self.exporter()
        let detectedAt = GoldenFixtures.conversionInstant
        let deletions = [
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(10), sourceType: .heartRate, deletedAfter: GoldenFixtures.sampleStart, detectedAt: detectedAt),
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(11), sourceType: .bloodPressureSystolic, deletedAfter: nil, detectedAt: detectedAt),
            HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(12), sourceType: .bloodPressure, deletedAfter: nil, detectedAt: detectedAt)
        ]
        let retractions = try await ExporterFixtures.retract(exporter, deletions, at: detectedAt)
        try #require(retractions.count == 3)
        // Outcomes arrive in input order; the systolic component never emitted outputs.
        guard case .nothingToRetract = retractions[1].outcome else {
            Issue.record("a systolic component never emitted outputs; expected nothingToRetract, got \(retractions[1].outcome)")
            return
        }
        #expect(retractions.map(\.deletion) == deletions)
        for (retraction, deletion) in [(retractions[0], deletions[0]), (retractions[2], deletions[2])] {
            let reference = try await ExporterFixtures.retract(exporter, [deletion], at: detectedAt)
            #expect(retraction.record == reference.first?.record)
        }
    }

    @Test("A skewed lower bound is dropped, and a retraction carries no Bundle.id")
    func retractionBounds() async throws {
        let detectedAt = GoldenFixtures.conversionInstant
        let retractions = try await ExporterFixtures.retract(
            Self.exporter(),
            [HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(21), sourceType: .heartRate, deletedAfter: detectedAt + 60, detectedAt: detectedAt)],
            at: detectedAt
        )
        let bundle = try #require(retractions.last?.record?.bundle)
        #expect(bundle.id == nil)
        let provenance = try #require(bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        guard case .period(let period)? = provenance.occurred else {
            Issue.record("expected a period")
            return
        }
        #expect(period.start == nil)
        #expect(period.end != nil)
    }

    @Test("An exported workout includes every segment, and its deletion retracts their source record")
    func workoutExportAndRetraction() async throws {
        let exporter = try Self.exporter()
        let workout = try StoredSampleFixtures.stored(GoldenFixtures.workout(withEvents: true), uuid: GoldenFixtures.uuid(0xA3))
        let exports = try await Self.collect(exporter, [workout])
        let entries = try #require(exports.first?.record?.bundle.entry)
        let observationEntries = entries.filter { $0.resource?.get(if: Observation.self) != nil }
        let observations = observationEntries.compactMap { $0.resource?.get(if: Observation.self) }
        let segments = (workout.workoutEvents ?? []).count + workout.workoutActivities.count
        try #require(observations.count == 1 + segments)
        let session = try #require(observations.first)
        #expect(session.hasMember?.compactMap { $0.reference?.value?.string }
            == observationEntries.dropFirst().compactMap { $0.fullUrl?.value?.url.absoluteString })
        let source = try #require(entries.compactMap { $0.resource?.get(if: Provenance.self) }.first?.entity?.first?.what.identifier)
        #expect(try RoledIdentifier(source).role == .sourceRecord)
        let deletion = HealthKitFHIRExporter.Deletion(uuid: workout.uuid, sourceType: .workout, deletedAfter: nil, detectedAt: GoldenFixtures.conversionInstant)
        let retractions = try await ExporterFixtures.retract(exporter, [deletion])
        let provenance = try #require(retractions.first?.record?.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        try #require(provenance.target.count == 1)
        let target = try #require(provenance.target.first)
        #expect(target.identifier == source)
        #expect(target.type == nil)
        let role = target.extension?.first { $0.url == Canonicals.retractionTargetRole }
        #expect(role?.value == .code("source-record".asFHIRStringPrimitive()))
    }

    /// One refusal per record, chosen in a fixed order whatever the options: content, then writer, then sync pair.
    @Test("A record with several faults reports its content first, then its writer, then its sync pair")
    func refusalOrderIsContentWriterSyncPair() async throws {
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
        let exports = try await Self.collect(exporter, samples)
        let reasons = exports.map { export -> HealthKitConversionError? in
            guard case .refused(let reason) = export.outcome else {
                return nil
            }
            return reason
        }
        #expect(reasons == [.invalidValue(.heartRate, .unsupportedMetadataValue(.heartRateMotionContext)), .sourceApplicationInvalid])
    }

    @Test("An error in the receiver ends the call")
    func receiverErrorsPropagate() async throws {
        struct Stop: Error {}
        let exporter = try Self.exporter()
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(14))
        await #expect(throws: Stop.self) {
            try await exporter.export([sample]) { _ in throw Stop() }
        }
        let again = try await Self.collect(exporter, [sample])
        #expect(again[0].record != nil)
    }
}


#endif
