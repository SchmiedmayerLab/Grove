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
    /// for it.
    static func conversions(_ record: HealthKitFHIRExporter.Record, _ inputs: ExportInputs = ExportInputs()) throws -> [HealthKitAssembly.Conversion] {
        let exporter = try ExporterFixtures.exporter(inputs)
        let plan = try #require(HealthKitContentPlan.plan(for: record.sample))
        let request = Self.request(for: record.sample, exporter: exporter, inputs: inputs)
        switch record {
        case .sample(let sample):
            return try exporter.assembly.convert(sample, plan: plan, request: request)
        case let .electrocardiogram(ecg, voltages, symptoms):
            var symptomRequests: [UUID: HealthKitAssembly.Request] = [:]
            for symptom in symptoms {
                symptomRequests[symptom.uuid] = Self.request(for: symptom, exporter: exporter, inputs: inputs)
            }
            let evidence = try plan.ecgEvidence(ecg, voltages: voltages)
            return try exporter.assembly.convertECG(evidence, symptoms: symptoms, plan: plan, request: request, symptomRequests: symptomRequests)
        case let .heartbeatSeries(series, _):
            let recording = try #require(record.recording(content: plan)).get()
            return try exporter.assembly.convertHeartbeatSeries(series, recording: recording, plan: plan, request: request)
        case let .workoutRoute(route, _):
            // The exporter plans nothing for a route its options omit.
            guard inputs.options.route == .authorized else {
                return []
            }
            let recording = try #require(record.recording(content: plan)).get()
            return try exporter.assembly.convertWorkoutRoute(route, recording: recording, plan: plan, request: request)
        }
    }

    /// The record's own conversion of `sample`.
    static func conversion(_ sample: HKSample, _ inputs: ExportInputs = ExportInputs()) throws -> HealthKitAssembly.Conversion {
        try #require(try conversions(.sample(sample), inputs).first)
    }

    /// The request the exporter states for `sample` under `inputs`.
    private static func request(for sample: HKSample, exporter: HealthKitFHIRExporter, inputs: ExportInputs) -> HealthKitAssembly.Request {
        exporter.assemblyRequest(for: sample, policies: HealthKitFHIRExporter.ResolvedPolicies(sample, options: exporter.options), at: inputs.instant)
    }
}

#endif
