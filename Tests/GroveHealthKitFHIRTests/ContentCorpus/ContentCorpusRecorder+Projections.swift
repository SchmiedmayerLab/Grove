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


/// The retractions and the reverse projections: the targets a deletion names, and the sample an Observation
/// projects back to, alone or straight from a conversion's wire bytes.
extension ContentCorpusRecorder {
    /// The instant from which HealthKit raises an uncatchable exception for any sample it is asked to create.
    private static let healthKitHorizon = Date(timeIntervalSince1970: 64_092_211_200) // 4000-01-01T00:00:00Z

    /// The sample `observation` projects back to, or why it does not.
    static func reverse(_ observation: Observation) -> LosslessJSONValue {
        do {
            return sample(try observation.healthKitSample(), units: statedUnits(of: observation))
        } catch {
            let refusal = LosslessJSONValue.object([
                "code": .string(error.diagnostic.code),
                "error": .string(String(describing: error))
            ])
            return .object(["refused": refusal])
        }
    }

    /// Converts `source`, then projects every Observation of its graphs, decoded from the wire bytes as a consumer
    /// reads them, back to a sample; a refusal or omission renders as the conversion's own.
    ///
    /// HealthKit raises an uncatchable exception when asked to create a sample after 4000 or shorter than its type's
    /// minimum duration, so such a source is refused here instead of projected.
    static func roundTrip(_ source: ContentCorpusSource) throws -> LosslessJSONValue {
        try requireProjectable(source)
        let outcome = try outcome(of: source)
        guard case .converted(let set) = outcome else {
            return try render(outcome)
        }
        let graphs = try set.all.map { conversion in
            let resources = (try LosslessJSONValue(parsing: conversion.graph.json)["entry"]?.elements ?? []).compactMap { $0["resource"] }
            let samples = try resources.filter { $0["resourceType"]?.text == ResourceType.observation.rawValue }.map { resource in
                reverse(try JSONDecoder().decode(Observation.self, from: Data(resource.canonicalText.utf8)))
            }
            return LosslessJSONValue.object(["samples": .array(samples)])
        }
        return .object(["graphs": .array(graphs)])
    }

    /// The deletion of a record of `type`: the targets it retracts, or why it retracts none.
    static func retraction(of type: String, disclosure: ContentCorpusDisclosure?) throws -> LosslessJSONValue {
        guard let sourceType = HealthKitSourceType(rawValue: type) else {
            throw ContentCorpusSamples.RebuildError.unknownType(type)
        }
        var inputs = GoldenFixtures.Inputs()
        if disclosure == .nativeIdentifier {
            inputs.options.nativeIdentifierDisclosure = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        }
        let context = try GoldenFixtures.context(sequence: sequence, inputs)
        let record = HealthKitSourceRecord(uuid: ContentCorpusSamples.uuid, type: sourceType)
        do {
            let targets = try HealthKitConverter().retractionTargets(for: record, context: context) // Port point: the deprecated facade.
            return .object(["targets": .array(targets.map(target))])
        } catch {
            return refusal(error)
        }
    }

    /// One retraction target: its identifier with system and role, the resource type and role it retracts, and
    /// the native record identifier it carries, or null.
    private static func target(_ target: RetractionTarget) -> LosslessJSONValue {
        let native = target.nativeRecordIdentifier.map { identifier in
            LosslessJSONValue.object(["system": .string(identifier.system.rawValue), "value": .string(identifier.value)])
        }
        return .object([
            "identifier": .string(target.identifier.identifier.value),
            "identifierSystem": .string(target.identifier.identifier.system.rawValue),
            "identifierRole": .string(target.identifier.role.rawValue),
            "resourceType": .string(target.resourceType.rawValue),
            "role": .string(target.role.rawValue),
            "nativeRecordIdentifier": native ?? .null
        ])
    }

    /// Refuses a source whose sample HealthKit would raise on when the projection creates it.
    private static func requireProjectable(_ source: ContentCorpusSource) throws {
        let horizon = healthKitHorizon.timeIntervalSince1970
        guard source.start < horizon, source.end < horizon else {
            throw ContentCorpusSamples.RebuildError.unstatable("a sample after 4000")
        }
        if case .quantity(let type, _, _) = source.record, try ContentCorpusSamples.quantityType(type).isMinimumDurationRestricted {
            throw ContentCorpusSamples.RebuildError.unstatable("an instant of the minimum-duration type \(type)")
        }
    }

    /// A projected sample's type, interval, metadata with each value's kind, value and members, every number as
    /// its shortest text.
    private static func sample(_ sample: HKSample, units: [HKUnit]) -> LosslessJSONValue {
        let metadata = sample.metadata ?? [:]
        var members: [String: LosslessJSONValue] = [
            "type": .string(sample.sampleType.identifier),
            "start": .string(String(sample.startDate.timeIntervalSince1970)),
            "end": .string(String(sample.endDate.timeIntervalSince1970)),
            "metadata": .object(metadata.mapValues { .string(metadataText($0)) }),
            "metadataTypes": .object(metadata.mapValues { .string(metadataKind($0)) })
        ]
        if let quantitySample = sample as? HKQuantitySample {
            members["quantity"] = .string(quantityText(quantitySample.quantity, units: units))
        }
        if let correlation = sample as? HKCorrelation {
            let objects = correlation.objects.map { Self.sample($0, units: units) }.sorted { $0.canonicalText < $1.canonicalText }
            members["objects"] = .array(objects)
        }
        return .object(members)
    }

    /// A metadata value as text: a string as itself, a number as `NSNumber` prints it (a Boolean as 0 or 1).
    private static func metadataText(_ value: Any) -> String {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: String(describing: value)
        }
    }

    /// What kind of value HealthKit kept, which the text alone does not tell: `string`, `boolean`, `integer`,
    /// `double`, or the class of anything else.
    private static func metadataKind(_ value: Any) -> String {
        switch value {
        case is String:
            "string"
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            "boolean"
        case let number as NSNumber:
            CFNumberIsFloatType(number as CFNumber) ? "double" : "integer"
        default:
            String(describing: Swift.type(of: value))
        }
    }

    /// The HealthKit units of the quantities `observation` states, as the published unit bindings read them.
    private static func statedUnits(of observation: Observation) -> [HKUnit] {
        var quantities: [ModelsR4.Quantity] = []
        if case .quantity(let quantity)? = observation.value {
            quantities.append(quantity)
        }
        for case .quantity(let quantity)? in (observation.component ?? []).map(\.value) {
            quantities.append(quantity)
        }
        return quantities.compactMap { $0.code?.value?.string }.compactMap(HealthKitCatalog.unit(forUCUMCode:))
    }

    /// A quantity in the first stated unit that measures it: the unit the projection created it in.
    private static func quantityText(_ quantity: HKQuantity, units: [HKUnit]) -> String {
        guard let unit = units.first(where: quantity.is(compatibleWith:)) else {
            return quantity.description
        }
        return "\(String(quantity.doubleValue(for: unit))) \(unit.unitString)"
    }
}

#endif
