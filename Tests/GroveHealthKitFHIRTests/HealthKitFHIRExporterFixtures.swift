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


/// An ECG and its voltages, as ``HealthKitFHIRExporter/Record/electrocardiogram(_:voltages:symptoms:)`` carries them
/// beside the symptoms each test chooses.
typealias ECGRecording = (electrocardiogram: HKElectrocardiogram, voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement])


/// What a test varies about one export besides its record: the producer's subject, application, host and studies,
/// the root of the identity systems, the call's instant, and the exporter's options.
struct ExportInputs: Sendable {
    /// The default inputs with every source classified as an application, for the tests that pin how a writer travels;
    /// by default no writer is stated.
    static var applicationWriter: ExportInputs {
        var inputs = ExportInputs()
        inputs.options.writer = .classify { _ in .application }
        return inputs
    }

    var subject: Subject = .testPatient
    var converter: ApplicationDevice = .test
    var converterHost: HostDevice = .test
    var studies: [StudyEnrollment] = []
    /// The root of the identity systems and the repository scope, as `TestDeployment.test(graphIdentifierSystem:)`
    /// takes it.
    var graphIdentifierSystem: IdentifierSystem?
    var instant = GoldenFixtures.conversionInstant
    var options = HealthKitFHIRExporter.Options()

    /// The test deployment whose identity scope and repository scope every export states.
    var base: TestDeployment {
        .test(graphIdentifierSystem: graphIdentifierSystem)
    }
}


/// Why a test's export produced no record to read back.
enum ExportFixtureError: Error {
    /// The call delivered no export: a policy omitted the record.
    case nothingExported
    /// The deletion names no output the exporter can have emitted.
    case nothingToRetract
    /// The export carries no record.
    case noRecord(HealthKitFHIRExporter.Export.Outcome)
}


/// Producers, exporters and records the exporter tests share.
enum ExporterFixtures {
    static let base = TestDeployment.test()

    static func producer(
        identityScope: OpaqueIdentityScope = base.identityScope,
        subject: Subject = base.subject,
        application: ApplicationDevice = base.application,
        host: HostDevice = base.host,
        studies: [StudyEnrollment] = []
    ) throws -> ExchangeProducer {
        try ExchangeProducer(identityScope: identityScope, subject: subject, application: application, host: host, studies: studies)
    }

    static func exporter(
        _ producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier = base.repositoryScope,
        _ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }
    ) throws -> HealthKitFHIRExporter {
        var options = HealthKitFHIRExporter.Options()
        configure(&options)
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: repositoryScope, options: options)
    }

    static func exporter(_ configure: (inout HealthKitFHIRExporter.Options) -> Void = { _ in }) throws -> HealthKitFHIRExporter {
        try exporter(producer(), configure)
    }

    /// Every export of one call.
    static func collect(
        _ exporter: HealthKitFHIRExporter,
        _ records: [HealthKitFHIRExporter.Record],
        at instant: Date = GoldenFixtures.conversionInstant
    ) async throws -> [HealthKitFHIRExporter.Export] {
        var exports: [HealthKitFHIRExporter.Export] = []
        try await exporter.export(records: records, at: instant) { exports.append($0) }
        return exports
    }

    static func collect(
        _ exporter: HealthKitFHIRExporter,
        samples: [HKSample],
        at instant: Date = GoldenFixtures.conversionInstant
    ) async throws -> [HealthKitFHIRExporter.Export] {
        try await collect(exporter, samples.map { .sample($0) }, at: instant)
    }

    static func retract(
        _ exporter: HealthKitFHIRExporter,
        _ deletions: [HealthKitFHIRExporter.Deletion],
        at instant: Date = GoldenFixtures.conversionInstant
    ) async throws -> [HealthKitFHIRExporter.Retraction] {
        var retractions: [HealthKitFHIRExporter.Retraction] = []
        try await exporter.retract(deletions, at: instant) { retractions.append($0) }
        return retractions
    }

    /// The goldens' ECG record with its correlated symptoms, which it states present exactly when there are any.
    static func electrocardiogram(uuid ordinal: UInt8, symptoms: [HKCategorySample]) throws -> HealthKitFHIRExporter.Record {
        try electrocardiogram(GoldenCase.electrocardiogramRecord(uuid: ordinal, symptoms: symptoms), symptoms: symptoms)
    }

    /// `record`'s ECG and voltages with `symptoms`, whatever symptoms status the ECG states.
    static func electrocardiogram(_ record: ECGRecording, symptoms: [HKCategorySample]) -> HealthKitFHIRExporter.Record {
        .electrocardiogram(record.electrocardiogram, voltages: record.voltageMeasurements, symptoms: symptoms)
    }

    static func deletion(_ ordinal: UInt8, deletedAfter: Date? = nil, detectedAt: Date = GoldenFixtures.conversionInstant) -> HealthKitFHIRExporter.Deletion {
        HealthKitFHIRExporter.Deletion(uuid: GoldenFixtures.uuid(ordinal), sourceType: .heartRate, deletedAfter: deletedAfter, detectedAt: detectedAt)
    }
}


extension ExporterFixtures {
    /// An exporter with `inputs`' facts and options.
    static func exporter(_ inputs: ExportInputs) throws -> HealthKitFHIRExporter {
        let producer = try ExchangeProducer(
            identityScope: inputs.base.identityScope,
            subject: inputs.subject,
            application: inputs.converter,
            host: inputs.converterHost,
            studies: inputs.studies
        )
        return try HealthKitFHIRExporter(producer: producer, repositoryScope: inputs.base.repositoryScope, options: inputs.options)
    }

    /// Every export one call delivers for `record`.
    static func exports(
        _ record: HealthKitFHIRExporter.Record,
        _ inputs: ExportInputs = ExportInputs()
    ) async throws -> [HealthKitFHIRExporter.Export] {
        try await collect(exporter(inputs), [record], at: inputs.instant)
    }

    /// Every record one call exports for `record`, read back; a refusal is thrown as the exporter reported it.
    static func export(_ record: HealthKitFHIRExporter.Record, _ inputs: ExportInputs = ExportInputs()) async throws -> ExportedRecord {
        try ExportedRecord(await exports(record, inputs))
    }

    /// Every record one call exports for `sample`, read back; a refusal is thrown as the exporter reported it.
    static func export(_ sample: HKSample, _ inputs: ExportInputs = ExportInputs()) async throws -> ExportedRecord {
        try await export(.sample(sample), inputs)
    }

    /// The retraction record of `deletion` under `inputs`, read back; a refusal is thrown as the exporter reported it.
    static func retraction(_ deletion: HealthKitFHIRExporter.Deletion, _ inputs: ExportInputs = ExportInputs()) async throws -> ExchangeGraph {
        let retractions = try await retract(exporter(inputs), [deletion], at: inputs.instant)
        guard let retraction = retractions.first else {
            throw ExportFixtureError.nothingExported
        }
        switch retraction.outcome {
        case .record(let record):
            return record.graph
        case .refused(let error):
            throw error
        case .nothingToRetract:
            throw ExportFixtureError.nothingToRetract
        }
    }
}

#endif
