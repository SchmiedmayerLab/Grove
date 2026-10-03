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


/// Runs one corpus vector through the converter's public entry points and renders what came out as JSON tokens.
///
/// A conversion renders, per graph, the output resources exactly as the wire carries them, the envelope around
/// them (each entry's resource type, each Provenance target, and a digest of the Bundle's own members and every
/// entry that is not an output), and the warnings in order. A refusal renders as its registry code, location and
/// Swift error, and a policy omission as such.
///
/// Port points for the cleanup step: every conversion and retraction here goes through the deprecated
/// `HealthKitConverter` facade (each call is marked `Port point`). When the facade is deleted they move to
/// `HealthKitFHIRExporter`, whose rendering of every convert vector `ContentCorpusExporterTests` already pins.
enum ContentCorpusRecorder {
    /// What converting one source record produced.
    enum Outcome {
        /// The record's graphs.
        case converted(HealthKitConversionSet)
        /// A policy chose to emit nothing.
        case omitted
        /// The record was refused.
        case refused(HealthKitConversionError)
    }

    /// The event sequence every vector converts under; an ECG's symptoms take the sequences after it.
    static let sequence: UInt64 = 300

    /// The output resources a graph's content layer produces; every other entry is envelope.
    private static let outputResourceTypes: Set<String> = [ResourceType.observation.rawValue, ResourceType.documentReference.rawValue]

    /// The corpus line's output for `input`; a vector the fixtures cannot rebuild throws instead.
    static func output(for input: ContentCorpusInput) throws -> LosslessJSONValue {
        switch input {
        case .convert(let source): try render(try outcome(of: source))
        case .roundTrip(let source): try roundTrip(source)
        case let .retract(type, disclosure): try retraction(of: type, disclosure: disclosure)
        case .catalog(let projection): try ContentCorpusCatalog.projection(projection)
        case .reverse(let observation): reverse(try observation.decoded(as: Observation.self))
        }
    }

    /// Converts `source` through the entry point its record takes.
    static func outcome(of source: ContentCorpusSource) throws -> Outcome {
        let context = try context(for: source)
        let converter = HealthKitConverter() // Port point: the deprecated facade.
        switch source.record {
        case .electrocardiogram(let reading):
            let record = try ContentCorpusSamples.electrocardiogram(source, reading: reading)
            let symptomContexts = try (0..<(reading.symptomContexts ?? reading.symptoms.count)).map { index in
                try GoldenFixtures.context(sequence: sequence + 1 + UInt64(index))
            }
            return capture { () throws(HealthKitConversionError) in
                try converter.convert(record, context: context, symptomContexts: symptomContexts) // Port point.
            }
        case .heartbeatSeries(let beats):
            let record = try ContentCorpusSamples.heartbeatSeries(source, beats: beats)
            return capture { () throws(HealthKitConversionError) in try converter.convert(record, context: context) } // Port point.
        case .workoutRoute(let locations, _):
            let record = try ContentCorpusSamples.workoutRoute(source, locations: locations)
            do {
                return try converter.convert(record, context: context).map(Outcome.converted) ?? .omitted // Port point.
            } catch {
                return .refused(error)
            }
        default:
            let sample = try ContentCorpusSamples.sample(source)
            return capture { () throws(HealthKitConversionError) in try converter.convert(sample, context: context) } // Port point.
        }
    }

    /// The tokens an outcome renders as.
    static func render(_ outcome: Outcome) throws -> LosslessJSONValue {
        switch outcome {
        case .converted(let set):
            .object(["graphs": .array(try set.all.map { try graph($0.graph, warnings: GoldenOutput($0).renderedWarnings) })])
        case .omitted:
            .object(["omitted": .boolean(true)])
        case .refused(let error):
            refusal(error)
        }
    }

    /// The suite's fixed context, under a gateway converter with one study when the vector asks for every link,
    /// and with routes disclosed when its route is.
    static func context(for source: ContentCorpusSource) throws -> HealthKitConversionContext {
        var inputs = GoldenFixtures.Inputs()
        if source.context == .linked {
            inputs.converterRole = .gateway
            inputs.studies = [.test("study-a")]
        }
        if case .workoutRoute(_, disclosed: true) = source.record {
            inputs.options.routeDisclosure = .authorized
        }
        return try GoldenFixtures.context(sequence: sequence, inputs)
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

    /// One graph's output resources as its wire bytes state them, its envelope, and its warnings as rendered.
    static func graph(_ graph: ExchangeGraph, warnings: [String]) throws -> LosslessJSONValue {
        let bundle = try LosslessJSONValue(parsing: graph.json)
        let entries = bundle["entry"]?.elements ?? []
        return .object([
            "outputs": .array(entries.compactMap { $0["resource"] }.filter(isOutput)),
            "envelope": envelope(of: bundle, entries: entries),
            "warnings": .array(warnings.map(LosslessJSONValue.string))
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

    /// The outcome of one conversion that either produces a set or refuses.
    private static func capture(_ convert: () throws(HealthKitConversionError) -> HealthKitConversionSet) -> Outcome {
        do {
            return .converted(try convert())
        } catch {
            return .refused(error)
        }
    }
}

#endif
