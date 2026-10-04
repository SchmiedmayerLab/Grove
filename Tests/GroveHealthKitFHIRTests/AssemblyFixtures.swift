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


/// The assembly's conversions of one record, read before the exporter maps them to exports. An export's
/// `mobile-omission.unmodeled-metadata` warning states only that its graph withholds some metadata keys; the tests that
/// pin which keys read them here (``HealthKitAssembly/Conversion/withheldMetadataKeys``).
enum AssemblyFixtures {
    /// Every conversion of `record` under `inputs`' facts and options, the record's own first: what the exporter builds
    /// for it, the record's event numbered ``ExportInputs/recordSequence`` and each ECG symptom's the next.
    static func conversions(_ record: HealthKitFHIRExporter.Record, _ inputs: ExportInputs = ExportInputs()) throws -> [HealthKitAssembly.Conversion] {
        let (exporter, _) = try ExporterFixtures.exporter(inputs)
        let plan = try #require(HealthKitContentPlan.plan(for: record.sample))
        let request = try Self.request(for: record.sample, sequence: inputs.recordSequence, exporter: exporter, inputs: inputs)
        switch record {
        case .sample(let sample):
            return try exporter.assembly.convert(sample, plan: plan, request: request)
        case let .electrocardiogram(ecg, voltages, symptoms):
            var symptomRequests: [UUID: HealthKitAssembly.Request] = [:]
            for (offset, symptom) in symptoms.enumerated() {
                let sequence = inputs.recordSequence + UInt64(offset) + 1
                symptomRequests[symptom.uuid] = try Self.request(for: symptom, sequence: sequence, exporter: exporter, inputs: inputs)
            }
            let evidence = try plan.ecgEvidence(ecg, voltages: voltages)
            return try exporter.assembly.convertECG(evidence, symptoms: symptoms, plan: plan, request: request, symptomRequests: symptomRequests)
        case let .heartbeatSeries(series, beats):
            return try exporter.assembly.convertHeartbeatSeries(series, beats: beats, plan: plan, request: request)
        case let .workoutRoute(route, locations):
            return try exporter.assembly.convertWorkoutRoute(route, locations: locations, plan: plan, request: request)
        }
    }

    /// The record's own conversion of `sample`.
    static func conversion(_ sample: HKSample, _ inputs: ExportInputs = ExportInputs()) throws -> HealthKitAssembly.Conversion {
        try #require(try conversions(.sample(sample), inputs).first)
    }

    /// The request the exporter states for `sample` under `inputs`, its event numbered `sequence`.
    private static func request(
        for sample: HKSample,
        sequence: UInt64,
        exporter: HealthKitFHIRExporter,
        inputs: ExportInputs
    ) throws -> HealthKitAssembly.Request {
        HealthKitAssembly.Request(
            event: try ExchangeEventIdentifier(
                system: inputs.base.identityScope.systems.event,
                producerInstance: inputs.base.event.producerInstance,
                sequence: EventSequence(sequence)
            ),
            instant: inputs.instant,
            facts: ExchangeEventFacts(application: inputs.converter, host: inputs.converterHost, studies: inputs.studies),
            converterRole: exporter.options.role.converterRole(for: sample.sourceRevision, application: inputs.converter),
            bundleID: try exporter.bundleID(for: sample.uuid),
            policies: HealthKitFHIRExporter.ResolvedPolicies(sample, options: exporter.options)
        )
    }
}

#endif
