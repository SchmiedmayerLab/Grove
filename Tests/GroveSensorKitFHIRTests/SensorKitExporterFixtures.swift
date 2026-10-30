//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4


/// The SensorKit exporter under the test deployment, and the graph views the converter tests read.
enum SensorKitExporterFixtures {
    static let application = ApplicationDevice.test(
        name: "Sensor Conformance",
        bundleIdentifier: "org.grovealliance.sensor-conformance",
        version: "0.5.0"
    )
    static let start = Date(timeIntervalSince1970: 1_787_009_400)
    /// The instant every single-record export reserves its event at.
    static let instant = start.addingTimeInterval(60)
    static let watch = RecordingDevice.test(stableUnitToken: "watch-42", name: "Example Watch")
    static let nativeSystem: IdentifierSystem = "https://study.example.org/fhir/identifier/sensorkit-source-record"

    static var timeZone: TimeZone {
        get throws {
            guard let zone = TimeZone(identifier: "America/Los_Angeles") else {
                throw CocoaError(.featureUnsupported)
            }
            return zone
        }
    }

    /// A producer over `storage` that hands out `sequence` next under the fixed producer instance.
    static func producer(
        sequence: UInt64 = 1,
        application: ApplicationDevice = application,
        studies: [StudyEnrollment] = [],
        storage: ExchangeProducer.InMemoryStorage = ExchangeProducer.InMemoryStorage()
    ) throws -> ExchangeProducer {
        try storage.transaction { transaction in
            if try transaction.read(LedgerKey.producer) == nil {
                let entry = ProducerEntry(instance: SensorFHIRIdentityTestSupport.producerInstance, next: sequence)
                try transaction.write(entry.encoded(), for: LedgerKey.producer)
            }
        }
        return try ExchangeProducer(
            identityScope: SensorFHIRIdentityTestSupport.identityScope,
            subject: SensorFHIRIdentityTestSupport.subject,
            application: application,
            host: SensorFHIRIdentityTestSupport.converterHost,
            studies: studies,
            storage: storage
        )
    }

    static func exporter(
        _ producer: ExchangeProducer,
        nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit,
        visitLocationIdentifierSystem: IdentifierSystem = SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem
    ) throws -> SensorKitFHIRExporter {
        var options = SensorKitFHIRExporter.Options()
        options.nativeIdentifier = nativeIdentifier
        return try SensorKitFHIRExporter(
            producer: producer,
            repositoryScope: SensorFHIRIdentityTestSupport.repositoryScope,
            visitLocationIdentifierSystem: visitLocationIdentifierSystem,
            options: options
        )
    }

    /// Every export of one call, in delivery order, and the call's receipt.
    static func collect(
        _ exporter: SensorKitFHIRExporter,
        _ records: [SensorKitRecord],
        timeZone: TimeZone? = nil,
        recordingDevice: RecordingDevice? = watch,
        at instant: Date = instant
    ) async throws -> (exports: [SensorKitFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        var exports: [SensorKitFHIRExporter.Export] = []
        let receipt = try await exporter.export(
            records,
            sourceTimeZone: timeZone ?? Self.timeZone,
            recordingDevice: recordingDevice,
            at: instant
        ) { exports.append($0) }
        return (exports, receipt)
    }

    /// The graph of `record` exported alone through a fresh ledger, or the refusal thrown.
    static func graph(
        _ record: SensorKitRecord,
        nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit,
        recordingDevice: RecordingDevice? = watch
    ) async throws -> ExchangeGraph {
        let exporter = try exporter(producer(), nativeIdentifier: nativeIdentifier)
        let exports = try await collect(exporter, [record], recordingDevice: recordingDevice).exports
        guard exports.count == 1 else {
            throw CocoaError(.featureUnsupported)
        }
        switch exports[0].outcome {
        case .graph(let graph):
            return graph
        case .refused(let refusal):
            throw refusal
        }
    }
}


extension ExchangeGraph {
    private var resources: [any Resource] {
        bundle.entry?.compactMap { $0.resource?.get() } ?? []
    }

    var observations: [Observation] {
        resources.compactMap { $0 as? Observation }
    }

    var recordingDocument: DocumentReference? {
        resources.lazy.compactMap { $0 as? DocumentReference }.first
    }

    var provenance: Provenance {
        get throws {
            guard let provenance = resources.lazy.compactMap({ $0 as? Provenance }).first else {
                throw CocoaError(.featureUnsupported)
            }
            return provenance
        }
    }

    /// The source-output identity of every Observation and DocumentReference, in entry order.
    var outputIdentifiers: [RoledIdentifier] {
        resources.compactMap { resource in
            let identifiers = (resource as? Observation)?.identifier ?? (resource as? DocumentReference)?.identifier ?? []
            return identifiers.lazy.compactMap { try? RoledIdentifier($0) }.first { $0.role == .sourceOutput }
        }
    }
}
