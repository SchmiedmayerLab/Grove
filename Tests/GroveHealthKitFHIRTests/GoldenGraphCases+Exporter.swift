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


/// The exporter configurations and records the exporter goldens use.
enum ExporterGolden {
    /// The deployment's own application, in the build it runs.
    static let deploymentApplication = ApplicationDevice.test(name: "Grove Study", bundleIdentifier: "org.example.study", version: "4.1.0", build: "412")
    static let deploymentStudies: [StudyEnrollment] = [.test("study-a")]
    /// The deployment's own system for the HealthKit UUID; not an example URL, so the HL7 validator accepts it.
    static let deploymentNativeIdentifierSystem: IdentifierSystem = "https://grovealliance.org/fhir/testing/identifiers/native-healthkit-record"

    /// A sample the deployment's own application wrote in the build it runs.
    static let deploymentWriter = StoredSampleFixtures.Writer(
        name: deploymentApplication.name,
        bundleIdentifier: deploymentApplication.bundleIdentifier,
        version: deploymentApplication.build,
        productType: "iPhone17,1"
    )

    /// An Apple per-device source: the watch that recorded the sample, as HealthKit names it.
    static let watchSource = StoredSampleFixtures.Writer(
        name: "Lukas's Apple Watch",
        bundleIdentifier: "com.apple.health.6C4B1D1E-0000-4000-8000-0000000000B0",
        version: "26.1",
        productType: "Watch7,12"
    )

    /// Options equal to MyHeartCounts' `Options.myHeartCounts` (`HealthKitGroveConversion.swift`, MyHeartCounts
    /// 79d70dbf) under the fix round's writer policy: the HealthKit UUID disclosed under the deployment's own system
    /// and kept as `Bundle.id`, the deployment's own writes mediated by it in the build that wrote them, its own
    /// bundle identifier the one source classified as an application, and every other option at its default.
    static var deploymentOptions: HealthKitFHIRExporter.Options {
        var options = HealthKitFHIRExporter.Options()
        options.nativeIdentifier = .authorized(system: deploymentNativeIdentifierSystem)
        options.legacyBundleID = .healthKitUUID
        options.role = .gatewayForOwnWrites
        options.writer = .applications([deploymentApplication.bundleIdentifier])
        return options
    }

    /// An exporter whose fresh ledger hands out `sequence` next under the fixed producer instance, with the
    /// deployment's application, studies and options, or with the test application and default options.
    static func exporter(sequence: UInt64, deployment: Bool) throws -> HealthKitFHIRExporter {
        let storage = ExchangeEventSequencer.InMemoryStorage()
        let instance = ExchangeEventContext.test().event.producerInstance
        try storage.transaction { try $0.write(ProducerEntry(instance: instance, next: sequence).encoded(), for: LedgerKey.producer) }
        let producer = try ExporterFixtures.producer(
            application: deployment ? deploymentApplication : .test,
            studies: deployment ? deploymentStudies : [],
            sequencer: ExchangeEventSequencer(storage: storage)
        )
        return try ExporterFixtures.exporter(producer) { options in
            if deployment {
                options = deploymentOptions
            }
        }
    }

    /// The graph at `index` of the `count` exports one call delivers for `inputs`, in delivery order.
    static func output(
        of inputs: [HealthKitFHIRExporter.Input],
        sequence: UInt64,
        deployment: Bool,
        index: Int = 0,
        of count: Int = 1
    ) throws -> GoldenOutput {
        let (exports, _) = try ExporterFixtures.collect(exporter(sequence: sequence, deployment: deployment), inputs)
        guard exports.count == count else {
            throw GoldenCaseError.unexpectedCompanions(exports.count - 1)
        }
        return try GoldenOutput(exports[index])
    }

    /// The one export of a call.
    static func single(_ exports: [HealthKitFHIRExporter.Export]) throws -> HealthKitFHIRExporter.Export {
        guard exports.count == 1, let export = exports.first else {
            throw GoldenCaseError.unexpectedCompanions(exports.count - 1)
        }
        return export
    }

    /// The sinus-rhythm ECG with one correlated symptom, through the exporter's evidence seam.
    static func electrocardiogram() throws -> HealthKitFHIRExporter.Input {
        try ExporterFixtures.electrocardiogram(uuid: 0xB2, symptoms: [GoldenCase.symptom(uuid: GoldenFixtures.uuid(0xB3))])
    }

    #if !os(watchOS)
    /// A lab result the provider issued in `version`, carried byte for byte.
    static func clinicalRecord(uuid ordinal: UInt8, version: HKFHIRVersion, payload: String) throws -> HKClinicalRecord {
        try StoredSampleFixtures.clinicalRecord(
            .labResultRecord,
            shape: GoldenCase.seriesShape(uuid: ordinal, duration: 0),
            displayName: "Hemoglobin A1c",
            resource: StoredSampleFixtures.ClinicalResource(version: version, type: .observation, identifier: "a1c", data: Data(payload.utf8))
        )
    }
    #endif
}


/// The graphs `HealthKitFHIRExporter` itself delivers: its ledger, its options and the facts frozen with each
/// reservation, which the converter's goldens never reach.
extension GoldenCase {
    /// Sequences 100-119. Each case exports through a fresh ledger that hands out its sequence next under the fixed
    /// producer instance every golden states, so an exporter golden is as reproducible as a converter golden.
    static let exporter: [GoldenCase] = [
        // The exporter's defaults on an Apple per-device source: no writer and no author, and a recording Device
        // only because the sample's HKDevice names its unit.
        GoldenCase("exporter-default-apple-watch-heart-rate", sequence: 100) { sequence in
            let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xB0), device: GoldenFixtures.watch, writer: ExporterGolden.watchSource)
            return try ExporterGolden.output(of: [.record(.sample(sample))], sequence: sequence, deployment: false)
        },
        // The same source whose HKDevice names no unit: no recording Device at all, and that omission reported.
        GoldenCase("exporter-default-apple-watch-heart-rate-without-unit-token", sequence: 109) { sequence in
            let sample = try GoldenFixtures.heartRate(
                uuid: GoldenFixtures.uuid(0xBB),
                device: GoldenFixtures.watchWithoutUnitToken,
                writer: ExporterGolden.watchSource
            )
            return try ExporterGolden.output(of: [.record(.sample(sample))], sequence: sequence, deployment: false)
        },
        // The deployment's own write in the build that runs, starting at a sub-second instant: its gateway role,
        // its classified writer, the disclosed UUID, the legacy Bundle.id and the study context.
        GoldenCase("exporter-deployment-own-heart-rate", sequence: 101) { sequence in
            let start = GoldenFixtures.sampleStart.addingTimeInterval(0.512)
            let heartRate = HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: GoldenFixtures.beatsPerMinute, doubleValue: 64),
                start: start,
                end: start,
                device: GoldenFixtures.watch,
                metadata: GoldenFixtures.timeZoneMetadata
            )
            let sample = try StoredSampleFixtures.stored(heartRate, uuid: GoldenFixtures.uuid(0xB1), writer: ExporterGolden.deploymentWriter)
            return try ExporterGolden.output(of: [.record(.sample(sample))], sequence: sequence, deployment: true)
        },
        GoldenCase("exporter-deployment-electrocardiogram", sequence: 102) { sequence in
            try ExporterGolden.output(of: [ExporterGolden.electrocardiogram()], sequence: sequence, deployment: true, index: 0, of: 2)
        },
        GoldenCase("exporter-deployment-electrocardiogram-symptom", sequence: 102) { sequence in
            try ExporterGolden.output(of: [ExporterGolden.electrocardiogram()], sequence: sequence, deployment: true, index: 1, of: 2)
        },
        GoldenCase("exporter-deployment-blood-pressure", sequence: 104) { sequence in
            let correlation = try bloodPressure(uuid: 0xB4, components: (0xB5, 0xB6))
            return try ExporterGolden.output(of: [.record(.sample(correlation))], sequence: sequence, deployment: true)
        },
        GoldenCase("exporter-deployment-state-of-mind", sequence: 105) { sequence in
            let stateOfMind = HKStateOfMind(
                date: GoldenFixtures.sampleStart,
                kind: .dailyMood,
                valence: -0.25,
                labels: [.stressed],
                associations: [.health],
                metadata: GoldenFixtures.timeZoneMetadata
            )
            let sample = try StoredSampleFixtures.stored(stateOfMind, uuid: GoldenFixtures.uuid(0xB7))
            return try ExporterGolden.output(of: [.record(.sample(sample))], sequence: sequence, deployment: true)
        },
        // A deletion noted between two queries, both stated at sub-second precision.
        GoldenCase("exporter-deployment-retraction", sequence: 106) { sequence in
            let deletion = HealthKitFHIRExporter.Deletion(
                uuid: GoldenFixtures.uuid(0xB8),
                sourceType: .heartRate,
                deletedAfter: GoldenFixtures.sampleStart.addingTimeInterval(0.125),
                detectedAt: GoldenFixtures.conversionInstant.addingTimeInterval(-0.25)
            )
            let (exports, _) = try ExporterFixtures.retract(ExporterGolden.exporter(sequence: sequence, deployment: true), [deletion])
            return try GoldenOutput(ExporterGolden.single(exports))
        }
    ] + exporterClinicalRecords

    #if os(watchOS)
    static let exporterClinicalRecords: [GoldenCase] = []
    #else
    /// `HKClinicalRecord` has no initializer; the stored-sample fixtures build one per release the guide admits.
    static let exporterClinicalRecords: [GoldenCase] = [
        GoldenCase("exporter-clinical-record-r4", sequence: 107) { sequence in
            let record = try ExporterGolden.clinicalRecord(uuid: 0xB9, version: .primaryR4(), payload: #"{"resourceType":"Observation","id":"a1c-r4","status":"final"}"#)
            return try ExporterGolden.output(of: [.record(.sample(record))], sequence: sequence, deployment: false)
        },
        GoldenCase("exporter-clinical-record-dstu2", sequence: 108) { sequence in
            let record = try ExporterGolden.clinicalRecord(uuid: 0xBA, version: .primaryDSTU2(), payload: #"{"resourceType":"Observation","id":"a1c-dstu2","status":"final"}"#)
            return try ExporterGolden.output(of: [.record(.sample(record))], sequence: sequence, deployment: false)
        }
    ]
    #endif
}


extension GoldenOutput {
    /// What one export delivered: its graph, the record it reported the graph for, which the golden test checks
    /// against the graph's source identity, and, as the outline spells them, the diagnostics it reported.
    init(_ export: HealthKitFHIRExporter.Export) throws {
        guard let graph = export.graph else {
            throw GoldenCaseError.notExported(String(describing: export.outcome))
        }
        guard let type = export.source.sourceType else {
            throw GoldenCaseError.notExported("a graph reported for the unregistered type \(export.source.typeIdentifier)")
        }
        self.init(
            graph: graph,
            renderedWarnings: export.warnings.map { "\($0.code)@\($0.location)" },
            source: HealthKitSourceRecord(uuid: export.source.uuid, type: type),
            identifiers: nil
        )
    }
}

#endif
