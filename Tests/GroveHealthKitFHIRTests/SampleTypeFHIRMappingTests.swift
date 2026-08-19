//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveHealthKit
@testable import GroveHealthKitFHIR
import ModelsR4
import Testing


@Suite
struct SampleTypeFHIRMappingTests {
    @Test
    func completeness() {
        let mapping = SampleTypesFHIRMapping.default
        #expect(Set(mapping.quantityTypesMapping.keys) == SampleType<HKQuantitySample>.allKnownQuantities)
        #expect(Set(mapping.correlationTypesMapping.keys) == SampleType<HKCorrelation>.allKnownCorrelations)
        #expect(Set(mapping.categoryTypesMapping.keys) == SampleType<HKCategorySample>.allKnownCategories)
    }


    /// A standard code, where one exists, has to come first: consumers read `code.coding[0]` as the
    /// concept and the platform identifier as the fallback, never the other way round.
    ///
    /// Types with no standard coding at all are expected — Grove deliberately does not mint a concept
    /// vocabulary for the residue — so this pins the ordering, not the coverage.
    @Test
    func standardCodingsPrecedeThePlatformIdentifier() {
        let mapping = SampleTypesFHIRMapping.default
        func check(_ codings: [Coding], of sampleType: any AnySampleType) {
            guard let platformCoding = codings.last else {
                Issue.record("'\(sampleType.id)' has no coding at all")
                return
            }
            #expect(platformCoding.system?.value?.url.absoluteString == SupportedCodeSystem.apple.rawValue)
            #expect(platformCoding.code?.value?.string == sampleType.id)
            for standardCoding in codings.dropLast() {
                let system = standardCoding.system?.value?.url.absoluteString
                #expect(
                    system.flatMap(SupportedCodeSystem.init(rawValue:)) == .loinc
                        || system.flatMap(SupportedCodeSystem.init(rawValue:)) == .snomed,
                    "'\(sampleType.id)' codes '\(system ?? "nil")' ahead of the platform identifier"
                )
            }
        }
        for (sampleType, quantityMapping) in mapping.quantityTypesMapping {
            check(quantityMapping.codings, of: sampleType)
        }
        for (sampleType, categoryMapping) in mapping.categoryTypesMapping {
            check(categoryMapping.codings, of: sampleType)
            #expect(!categoryMapping.categories.isEmpty, "'\(sampleType.id)' carries no observation category")
            for category in categoryMapping.categories {
                #expect(category.system?.value?.url.absoluteString == SupportedCodeSystem.observationCategory.rawValue)
            }
        }
    }


    @Test
    func quantityTypeUnits() throws {
        /// hardcoded case where the FHIR mapping intentionally diverges from matching HealthKit's canonical unit.
        struct KnownDivergence: Hashable {
            let sampleType: SampleType<HKQuantitySample>
            let ucumUnitString: String
            let healthKitCanUnit: HKUnit
        }
        /// ucum → HealthKit
        let ucumToHealthKitEquivalences: [String: String] = [
            "kcal": "Cal",
            "Cel": "degC",
            "mm[Hg]": "mmHg",
            "/min": "count/min",
            "ug": "mcg",
            "uS": "mcS",
            "[iU]": "IU"
        ]
        let knownDivergences: Set<KnownDivergence> = [
            .init(sampleType: .bodyMassIndex, ucumUnitString: "kg/m2", healthKitCanUnit: .count()),
            .init(sampleType: .physicalEffort, ucumUnitString: "kcal/(kg.h)", healthKitCanUnit: HKUnit(from: "kcal/hr·kg")),
            // UCUM has no A-weighted bel, so the weighting rides along as an annotation.
            .init(sampleType: .headphoneAudioExposure, ucumUnitString: "dB[SPL]{A}", healthKitCanUnit: HKUnit(from: "dBASPL")),
            .init(sampleType: .environmentalAudioExposure, ucumUnitString: "dB[SPL]{A}", healthKitCanUnit: HKUnit(from: "dBASPL")),
            .init(sampleType: .environmentalSoundReduction, ucumUnitString: "dB{A}", healthKitCanUnit: HKUnit(from: "dBASPL")),
            .init(sampleType: .vo2Max, ucumUnitString: "mL/min/kg{body_wt}", healthKitCanUnit: HKUnit(from: "mL/min·kg"))
        ]
        func checkIsUCUMUnit(_ ucumUnit: String, equivalentTo hkUnit: HKUnit) -> Bool {
            let hkUnit = hkUnit.unitString
            if ucumUnit == hkUnit {
                return true
            } else if let ucumUnit = ucumToHealthKitEquivalences[ucumUnit] {
                return ucumUnit == hkUnit
            } else {
                return false
            }
        }
        for (sampleType, mapping) in SampleTypesFHIRMapping.default.quantityTypesMapping {
            #expect(mapping.unit.hkUnit == sampleType.canonicalUnit)
            #expect((mapping.unit.code?.value?.string == nil) == (mapping.unit.system?.value?.url == nil))
            guard let nonHKUnitString = mapping.unit.code?.value?.string else {
                continue
            }
            let hkUnit = mapping.unit.hkUnit
            let nonHKUnitSystem = try #require(mapping.unit.system)
            switch nonHKUnitSystem {
            case .unitsOfMeasureSystem:
                let ucumUnit = nonHKUnitString
                if ucumUnit.hasPrefix("{") && ucumUnit.hasSuffix("}") {
                    // UCUM annotations ({steps}, {score}, ...) are dimensionless by
                    // definition, matching HealthKit's count-style units.
                    continue
                }
                if checkIsUCUMUnit(ucumUnit, equivalentTo: hkUnit) {
                    continue
                } else if knownDivergences.contains(.init(sampleType: sampleType, ucumUnitString: ucumUnit, healthKitCanUnit: hkUnit)) {
                    continue
                } else {
                    Issue.record(
                        "'\(ucumUnit)' could not be confirmed to be semantically-equivalent to '\(sampleType.canonicalUnit)' (\(sampleType.id))"
                    )
                }
            default:
                Issue.record("Unhandled coding system: '\(nonHKUnitSystem)'")
            }
        }
    }
}

#endif
