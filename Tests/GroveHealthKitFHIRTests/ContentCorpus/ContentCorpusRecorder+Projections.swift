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
import Testing


/// The retractions and the reverse projections: the targets a deletion names, and the sample an Observation
/// projects back to, alone or straight from an export's wire bytes.
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

    /// Exports `source`, then projects every Observation of its graphs, decoded from the wire bytes as a consumer
    /// reads them, back to a sample; a refusal or omission renders as the export's own.
    ///
    /// HealthKit raises an uncatchable exception when asked to create a sample after 4000 or shorter than its type's
    /// minimum duration, so such a source is refused here instead of projected.
    static func roundTrip(_ source: ContentCorpusSource) async throws -> LosslessJSONValue {
        try requireProjectable(source)
        let outcome = try await outcome(of: source)
        guard case .converted(let exports) = outcome else {
            return try render(outcome)
        }
        let graphs = try exports.compactMap(\.graph).map { graph in
            let resources = (try LosslessJSONValue(parsing: graph.json)["entry"]?.elements ?? []).compactMap { $0["resource"] }
            let samples = try resources.filter { $0["resourceType"]?.text == ResourceType.observation.rawValue }.map { resource in
                reverse(try JSONDecoder().decode(Observation.self, from: Data(resource.canonicalText.utf8)))
            }
            return LosslessJSONValue.object(["samples": .array(samples)])
        }
        return .object(["graphs": .array(graphs)])
    }

    /// The retraction of a deleted record of `type`: the targets its graph names, or why it names none. Routes are
    /// disclosed, so a route deletion names its targets too; a type without outputs has nothing to retract.
    static func retraction(of type: String, disclosure: ContentCorpusDisclosure?) async throws -> LosslessJSONValue {
        guard let sourceType = HealthKitSourceType(rawValue: type) else {
            throw ContentCorpusSamples.RebuildError.unknownType(type)
        }
        var inputs = ExportInputs()
        inputs.sequence = sequence
        inputs.options.route = .authorized
        if disclosure == .nativeIdentifier {
            inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
        }
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: ContentCorpusSamples.uuid,
            sourceType: sourceType,
            deletedAfter: nil,
            detectedAt: GoldenFixtures.conversionInstant
        )
        let graph: ExchangeGraph
        do {
            graph = try await ExporterFixtures.retraction(deletion, inputs)
        } catch ExportFixtureError.nothingToRetract {
            return .object(["nothingToRetract": .boolean(true)])
        } catch let error as HealthKitConversionError {
            return refusal(error)
        }
        let provenance = graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first
        return .object(["targets": .array(try (provenance?.target ?? []).map(target))])
    }

    /// One retraction target as its Provenance target states it: its identifier with system and role, the resource
    /// type and role it retracts, and the native record identifier it carries, or null.
    private static func target(_ target: Reference) throws -> LosslessJSONValue {
        let identifier = try RoledIdentifier(#require(target.identifier))
        func extensionValue(_ url: FHIRPrimitive<FHIRURI>) -> Extension.ValueX? {
            target.extension?.first { $0.url == url }?.value
        }
        var role = LosslessJSONValue.null
        if case .code(let code)? = extensionValue(Canonicals.retractionTargetRole) {
            role = .string(code.value?.string ?? "")
        }
        var native = LosslessJSONValue.null
        if case .identifier(let identifier)? = extensionValue(Canonicals.retractionTargetNativeIdentifier) {
            native = .object([
                "system": .string(identifier.system?.value?.url.absoluteString ?? ""),
                "value": .string(identifier.value?.value?.string ?? "")
            ])
        }
        return .object([
            "identifier": .string(identifier.identifier.value),
            "identifierSystem": .string(identifier.identifier.system.rawValue),
            "identifierRole": .string(identifier.role.rawValue),
            "resourceType": .string(target.type?.value?.url.absoluteString ?? ""),
            "role": role,
            "nativeRecordIdentifier": native
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
