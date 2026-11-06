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


/// The SensorKit exporter under the test deployment, and the views of a record's one-record Bundle the converter tests read.
enum SensorKitExporterFixtures {
    static let application = ApplicationDevice.test(
        name: "Sensor Conformance",
        bundleIdentifier: "org.grovealliance.sensor-conformance",
        version: "0.5.0"
    )
    static let start = Date(timeIntervalSince1970: 1_787_009_400)
    /// The instant every single-record export converts at.
    static let instant = start.addingTimeInterval(60)
    static let watch = RecordingDevice.test()
    static let nativeSystem: IdentifierSystem = "https://study.example.org/fhir/identifier/sensorkit-source-record"

    static var timeZone: TimeZone {
        get throws {
            guard let zone = TimeZone(identifier: "America/Los_Angeles") else {
                throw CocoaError(.featureUnsupported)
            }
            return zone
        }
    }

    static func producer(application: ApplicationDevice = application, studies: [StudyEnrollment] = []) throws -> ExchangeProducer {
        try ExchangeProducer(
            identityScope: SensorFHIRIdentityTestSupport.identityScope,
            subject: SensorFHIRIdentityTestSupport.subject,
            application: application,
            host: SensorFHIRIdentityTestSupport.converterHost,
            studies: studies
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

    /// Every export of one call, in delivery order.
    static func collect(
        _ exporter: SensorKitFHIRExporter,
        _ records: [SensorKitRecord],
        timeZone: TimeZone? = nil,
        recordingDevice: RecordingDevice? = watch,
        sourceDevices: [RecordingDevice] = [],
        at instant: Date = instant
    ) async throws -> [SensorKitFHIRExporter.Export] {
        var exports: [SensorKitFHIRExporter.Export] = []
        try await exporter.export(
            records,
            sourceTimeZone: timeZone ?? Self.timeZone,
            recordingDevice: recordingDevice,
            sourceDevices: sourceDevices,
            at: instant
        ) { exports.append($0) }
        return exports
    }

    /// `input` exported alone, or the refusal thrown.
    static func record(
        _ input: SensorKitRecord,
        nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit,
        recordingDevice: RecordingDevice? = watch,
        sourceDevices: [RecordingDevice] = []
    ) async throws -> ExchangeRecord {
        let exporter = try exporter(producer(), nativeIdentifier: nativeIdentifier)
        let exports = try await collect(exporter, [input], recordingDevice: recordingDevice, sourceDevices: sourceDevices)
        guard exports.count == 1 else {
            throw CocoaError(.featureUnsupported)
        }
        switch exports[0].outcome {
        case .record(let record):
            return record
        case .refused(let refusal):
            throw refusal
        }
    }

    /// The one-record Bundle of ``record(_:nativeIdentifier:recordingDevice:sourceDevices:)``, decoded for reading.
    static func graph(
        _ input: SensorKitRecord,
        nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit,
        recordingDevice: RecordingDevice? = watch,
        sourceDevices: [RecordingDevice] = []
    ) async throws -> ExchangeGraph {
        try await record(input, nativeIdentifier: nativeIdentifier, recordingDevice: recordingDevice, sourceDevices: sourceDevices).graph
    }
}


extension ExchangeRecord {
    /// The record's one-record Bundle, decoded for reading.
    var graph: ExchangeGraph {
        get throws {
            try ExchangeGraph(validating: json, kind: kind == .active ? .active : .retraction)
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

    var devices: [Device] {
        resources.compactMap { $0 as? Device }
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
