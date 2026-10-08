//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


/// Runs one corpus vector through `HealthKitFHIRExporter` and renders what came out as JSON tokens.
///
/// An export renders, per graph, the output resources exactly as the wire carries them, the envelope around them
/// (each entry's resource type, each Provenance target, and a digest of the Bundle's own members and every entry that
/// is not an output), and the warnings in order, each as its registry code and location. A refusal renders as its
/// registry code, location and Swift error, and a policy omission as such.
enum ContentCorpusRecorder {
    /// What exporting one source record produced.
    enum Outcome {
        /// The record's graphs, the record's own first, then an ECG's symptoms.
        case converted([HealthKitFHIRExporter.Export])
        /// A policy chose to emit nothing.
        case omitted
        /// The record was refused.
        case refused(HealthKitConversionError)
    }

    /// The event sequence every vector exports under; an ECG's symptoms take the sequences after it.
    static let sequence: UInt64 = 300

    /// The output resources a graph's content layer produces; every other entry is envelope.
    private static let outputResourceTypes: Set<String> = [ResourceType.observation.rawValue, ResourceType.documentReference.rawValue]

    /// The corpus line's output for `input`; a vector the fixtures cannot rebuild throws instead.
    static func output(for input: ContentCorpusInput) async throws -> LosslessJSONValue {
        switch input {
        case .convert(let source): try await render(try outcome(of: source))
        case .roundTrip(let source): try await roundTrip(source)
        case let .retract(type, disclosure): try await retraction(of: type, disclosure: disclosure)
        case .catalog(let projection): try ContentCorpusCatalog.projection(projection)
        case .reverse(let observation): reverse(try observation.decoded(as: Observation.self))
        }
    }

    /// Exports `source` as the record its payload takes.
    static func outcome(of source: ContentCorpusSource) async throws -> Outcome {
        let record: HealthKitFHIRExporter.Record
        switch source.record {
        case .electrocardiogram(let reading):
            record = try ContentCorpusSamples.electrocardiogram(source, reading: reading)
        case .heartbeatSeries(let beats):
            record = try ContentCorpusSamples.heartbeatSeries(source, beats: beats)
        case .workoutRoute(let locations, _):
            record = try ContentCorpusSamples.workoutRoute(source, locations: locations)
        default:
            record = .sample(try ContentCorpusSamples.sample(source))
        }
        let exports = try await ExporterFixtures.exports(record, inputs(for: source))
        if exports.count == 1, case .refused(let error) = exports[0].outcome {
            return .refused(error)
        }
        return exports.isEmpty ? .omitted : .converted(exports)
    }

    /// The tokens an outcome renders as.
    static func render(_ outcome: Outcome) throws -> LosslessJSONValue {
        switch outcome {
        case .converted(let exports):
            .object(["graphs": .array(try exports.map(graph))])
        case .omitted:
            .object(["omitted": .boolean(true)])
        case .refused(let error):
            refusal(error)
        }
    }

    /// The suite's fixed inputs, under a gateway converter with one study when the vector asks for every link, and
    /// with routes disclosed when its route is.
    static func inputs(for source: ContentCorpusSource) -> ExportInputs {
        var inputs = ExportInputs()
        inputs.sequence = sequence
        if source.context == .linked {
            inputs.options.role = .gateway
            inputs.studies = [.test("study-a")]
        }
        if case .workoutRoute(_, disclosed: true) = source.record {
            inputs.options.route = .authorized
        }
        return inputs
    }

    /// A refusal as its registry code, location and Swift error.
    static func refusal(_ error: HealthKitConversionError) -> LosslessJSONValue {
        let refusal = LosslessJSONValue.object([
            "code": .string(error.diagnostic.code),
            "location": .string(error.diagnostic.location),
            "error": .string(String(describing: error))
        ])
        return .object(["refused": refusal])
    }

    /// One export's output resources as its graph's wire bytes state them, its envelope, and its warnings, each as its
    /// registry code and the element it names.
    static func graph(_ export: HealthKitFHIRExporter.Export) throws -> LosslessJSONValue {
        guard let graph = export.graph else {
            return .string("unexpected outcome \(export.outcome)")
        }
        let bundle = try LosslessJSONValue(parsing: graph.json)
        let entries = bundle["entry"]?.elements ?? []
        return .object([
            "outputs": .array(entries.compactMap { $0["resource"] }.filter(isOutput)),
            "envelope": envelope(of: bundle, entries: entries),
            "warnings": .array(export.warnings.map { .string("\($0.code)@\($0.location)") })
        ])
    }

    /// Whether a resource is one the content layer produces.
    private static func isOutput(_ resource: LosslessJSONValue) -> Bool {
        outputResourceTypes.contains(resource["resourceType"]?.text ?? "")
    }

    /// The graph around its outputs: every entry's resource type in Bundle order, every Provenance target as the
    /// index of the entry it names, and a SHA-256 digest of the Bundle's own members and every entry that is not
    /// an output, so a change to a Device, the Provenance or the Bundle shows here even where no golden pins it.
    private static func envelope(of bundle: LosslessJSONValue, entries: [LosslessJSONValue]) -> LosslessJSONValue {
        let fullURLs = entries.map { $0["fullUrl"]?.text ?? "" }
        let targets = entries.compactMap { $0["resource"] }
            .filter { $0["resourceType"]?.text == ResourceType.provenance.rawValue }
            .flatMap { $0["target"]?.elements ?? [] }
            .map { target -> LosslessJSONValue in
                guard let reference = target["reference"]?.text, let index = fullURLs.firstIndex(of: reference) else {
                    return target
                }
                return .number(String(index))
            }
        var head: [String: LosslessJSONValue] = [:]
        if case .object(let members) = bundle {
            head = members.filter { $0.key != "entry" }
        }
        let others = entries.filter { !isOutput($0["resource"] ?? .null) }
        let digested = LosslessJSONValue.object(["bundle": .object(head), "entries": .array(others)]).canonicalText
        return .object([
            "entries": .array(entries.map { .string($0["resource"]?["resourceType"]?.text ?? "") }),
            "provenanceTargets": .array(targets),
            "digest": .string(SHA256.hash(data: Data(digested.utf8)).map { String(format: "%02x", $0) }.joined())
        ])
    }
}

#endif
