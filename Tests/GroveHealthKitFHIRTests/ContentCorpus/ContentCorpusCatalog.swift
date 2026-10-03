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


/// Renders the public catalog surface the content layer publishes: inventory rows with their outputs and field
/// dispositions, the unit bindings, and both unit lookups.
enum ContentCorpusCatalog {
    /// The tokens one catalog projection renders as.
    static func projection(_ projection: ContentCorpusProjection) throws -> LosslessJSONValue {
        switch projection {
        case .entry(let type):
            try entry(type)
        case .unitBindings:
            .array(HealthKitCatalog.unitBindings.map { binding in
                .object([
                    "ucumCode": .string(binding.ucumCode),
                    "displayUnit": .string(binding.displayUnit),
                    "unit": .string(binding.unit.unitString)
                ])
            })
        case .unitSpellings(let spellings):
            .object(Dictionary(uniqueKeysWithValues: spellings.map { spelling in
                (spelling, LosslessJSONValue.object([
                    "ucumCode": unitText(HealthKitCatalog.unit(forUCUMCode: spelling)),
                    "unitSpelling": unitText(HealthKitCatalog.unit(forUnitSpelling: spelling))
                ]))
            }))
        }
    }

    /// One inventory row, the outputs its conversion mints, and what happens to each of its source fields.
    private static func entry(_ type: String) throws -> LosslessJSONValue {
        guard let sourceType = HealthKitSourceType(rawValue: type) else {
            throw ContentCorpusSamples.RebuildError.unknownType(type)
        }
        let entry = HealthKitCatalog[sourceType]
        return .object([
            "title": .string(entry.title),
            "status": .string(entry.implementationStatus.rawValue),
            "requirement": entry.requirement.map(LosslessJSONValue.string) ?? .null,
            "measurements": .array(entry.measurements.map { measurement in
                .object(["id": .string(measurement.id), "profiles": .array(measurement.profiles.map { .string(canonicalText($0)) })])
            }),
            "outputs": .array(HealthKitCatalog.outputs(for: sourceType).map { output in
                .object([
                    "role": .string(output.role),
                    "discriminator": .string(output.discriminator),
                    "resourceType": .string(output.resourceType.rawValue),
                    "retractionRole": .string(output.retractionRole.rawValue)
                ])
            }),
            "fieldDispositions": .object((HealthKitCatalog.fieldDispositions[sourceType] ?? [:]).mapValues { .string($0.rawValue) })
        ])
    }

    /// A unit as its unit string, or null when the lookup found none.
    private static func unitText(_ unit: HKUnit?) -> LosslessJSONValue {
        unit.map { .string($0.unitString) } ?? .null
    }

    /// A canonical as `url|version`, or its url alone.
    private static func canonicalText(_ canonical: FHIRPrimitive<Canonical>) -> String {
        guard let value = canonical.value else {
            return ""
        }
        return [value.url.absoluteString, value.version].compactMap(\.self).joined(separator: "|")
    }
}

#endif
