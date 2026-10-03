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


/// The retractions and the reverse projection: the targets a deletion names, and the sample an Observation
/// projects back to.
extension ContentCorpusRecorder {
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

    /// The deletion of a record of `type`: the targets it retracts, or why it retracts none.
    static func retraction(of type: String) throws -> LosslessJSONValue {
        guard let sourceType = HealthKitSourceType(rawValue: type) else {
            throw ContentCorpusSamples.RebuildError.unknownType(type)
        }
        let context = try GoldenFixtures.context(sequence: sequence)
        let record = HealthKitSourceRecord(uuid: ContentCorpusSamples.uuid, type: sourceType)
        do {
            let targets = try HealthKitConverter().retractionTargets(for: record, context: context) // Port point: the deprecated facade.
            return .object(["targets": .array(targets.map(target))])
        } catch {
            return refusal(error)
        }
    }

    /// One retraction target: its identifier and role, and the resource type and role it retracts.
    private static func target(_ target: RetractionTarget) -> LosslessJSONValue {
        .object([
            "identifier": .string(target.identifier.identifier.value),
            "identifierRole": .string(target.identifier.role.rawValue),
            "resourceType": .string(target.resourceType.rawValue),
            "role": .string(target.role.rawValue)
        ])
    }

    /// A projected sample's type, interval, metadata, value and members, every number as its shortest text.
    private static func sample(_ sample: HKSample, units: [HKUnit]) -> LosslessJSONValue {
        let metadata = sample.metadata ?? [:]
        var members: [String: LosslessJSONValue] = [
            "type": .string(sample.sampleType.identifier),
            "start": .string(String(sample.startDate.timeIntervalSince1970)),
            "end": .string(String(sample.endDate.timeIntervalSince1970)),
            "metadata": .object(metadata.mapValues { .string(metadataText($0)) })
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
