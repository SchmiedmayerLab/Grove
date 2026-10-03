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


/// Runs one corpus vector through the converter's public entry points and renders what came out as JSON tokens.
///
/// A conversion renders, per graph, the output resources exactly as the wire carries them and the warnings in
/// order; a refusal renders as its registry code, location and Swift error, and a policy omission as such. The rest
/// of the envelope (Provenance, Devices) stays out: the goldens pin it.
///
/// Converted Observations are not projected back here: `Observation.healthKitSample()` builds the sample through
/// HealthKit's initializers, which raise an uncatchable exception for an instant HealthKit refuses (after 4000, or
/// shorter than a type's minimum duration). The `reverse/` vectors project curated Observations instead.
enum ContentCorpusRecorder {
    /// What converting one source record produced.
    enum Outcome {
        case converted(HealthKitConversionSet)
        case omitted
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
        case .retract(let type): try retraction(of: type)
        case .catalog(let projection): try ContentCorpusCatalog.projection(projection)
        }
    }

    /// Converts `source` through the entry point its record takes.
    static func outcome(of source: ContentCorpusSource) throws -> Outcome {
        let context = try context(for: source)
        let converter = HealthKitConverter()
        switch source.record {
        case .electrocardiogram(let reading):
            let record = try ContentCorpusSamples.electrocardiogram(source, reading: reading)
            let symptomContexts = try (0..<(reading.symptomContexts ?? reading.symptoms.count)).map { index in
                try GoldenFixtures.context(sequence: sequence + 1 + UInt64(index))
            }
            return capture { () throws(HealthKitConversionError) in
                try converter.convert(record, context: context, symptomContexts: symptomContexts)
            }
        case .heartbeatSeries(let beats):
            let record = try ContentCorpusSamples.heartbeatSeries(source, beats: beats)
            return capture { () throws(HealthKitConversionError) in try converter.convert(record, context: context) }
        case .workoutRoute(let locations, _):
            let record = try ContentCorpusSamples.workoutRoute(source, locations: locations)
            do {
                return try converter.convert(record, context: context).map(Outcome.converted) ?? .omitted
            } catch {
                return .refused(error)
            }
        default:
            let sample = try ContentCorpusSamples.sample(source)
            return capture { () throws(HealthKitConversionError) in try converter.convert(sample, context: context) }
        }
    }

    static func render(_ outcome: Outcome) throws -> LosslessJSONValue {
        switch outcome {
        case .converted(let set):
            .object(["graphs": .array(try set.all.map(graph))])
        case .omitted:
            .object(["omitted": .boolean(true)])
        case .refused(let error):
            refusal(error)
        }
    }

    /// The suite's fixed context, under a gateway converter with one study when the vector asks for every link.
    private static func context(for source: ContentCorpusSource) throws -> HealthKitConversionContext {
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

    private static func capture(_ convert: () throws(HealthKitConversionError) -> HealthKitConversionSet) -> Outcome {
        do {
            return .converted(try convert())
        } catch {
            return .refused(error)
        }
    }

    private static func refusal(_ error: HealthKitConversionError) -> LosslessJSONValue {
        let refusal = LosslessJSONValue.object([
            "code": .string(error.diagnostic.code),
            "location": .string(error.diagnostic.location),
            "error": .string(String(describing: error))
        ])
        return .object(["refused": refusal])
    }

    /// One graph's output resources as its wire bytes state them, and its warnings.
    private static func graph(_ conversion: HealthKitConversion) throws -> LosslessJSONValue {
        let bundle = try LosslessJSONValue(parsing: conversion.graph.json)
        let outputs = (bundle["entry"]?.elements ?? []).compactMap { $0["resource"] }.filter { resource in
            outputResourceTypes.contains(resource["resourceType"]?.text ?? "")
        }
        return .object([
            "outputs": .array(outputs),
            "warnings": .array(GoldenOutput(conversion).renderedWarnings.map(LosslessJSONValue.string))
        ])
    }

    /// The deletion of a record of `type`: the targets it retracts, or why it retracts none.
    private static func retraction(of type: String) throws -> LosslessJSONValue {
        guard let sourceType = HealthKitSourceType(rawValue: type) else {
            throw ContentCorpusSamples.RebuildError.unknownType(type)
        }
        let context = try GoldenFixtures.context(sequence: sequence)
        let record = HealthKitSourceRecord(uuid: ContentCorpusSamples.uuid, type: sourceType)
        do {
            let targets = try HealthKitConverter().retractionTargets(for: record, context: context).map { target in
                LosslessJSONValue.object([
                    "identifier": .string(target.identifier.identifier.value),
                    "identifierRole": .string(target.identifier.role.rawValue),
                    "resourceType": .string(target.resourceType.rawValue),
                    "role": .string(target.role.rawValue)
                ])
            }
            return .object(["targets": .array(targets)])
        } catch {
            return refusal(error)
        }
    }

    /// The sample `observation` projects back to, or why it does not.
    static func reverse(_ observation: Observation) -> LosslessJSONValue {
        do {
            return sample(try observation.healthKitSample())
        } catch {
            let refusal = LosslessJSONValue.object([
                "code": .string(error.diagnostic.code),
                "error": .string(String(describing: error))
            ])
            return .object(["refused": refusal])
        }
    }

    /// A projected sample's type, interval, metadata, value and members, every number as its shortest text.
    private static func sample(_ sample: HKSample) -> LosslessJSONValue {
        var members: [String: LosslessJSONValue] = [
            "type": .string(sample.sampleType.identifier),
            "start": .string(String(sample.startDate.timeIntervalSince1970)),
            "end": .string(String(sample.endDate.timeIntervalSince1970)),
            "metadata": .object((sample.metadata ?? [:]).mapValues { .string(metadataText($0)) })
        ]
        if let quantitySample = sample as? HKQuantitySample {
            members["quantity"] = .string(quantityText(quantitySample.quantity))
        }
        if let correlation = sample as? HKCorrelation {
            let objects = correlation.objects.map(Self.sample).sorted { $0.canonicalText < $1.canonicalText }
            members["objects"] = .array(objects)
        }
        return .object(members)
    }

    private static func metadataText(_ value: Any) -> String {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: String(describing: value)
        }
    }

    /// A quantity in the unit it was created with, which HealthKit keeps but does not publish.
    private static func quantityText(_ quantity: HKQuantity) -> String {
        guard let unit = quantity.value(forKey: "unit") as? HKUnit else {
            return quantity.description
        }
        return "\(String(quantity.doubleValue(for: unit))) \(unit.unitString)"
    }
}

#endif
