//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import ModelsR4
import SpeziHealthKit
@testable import SpeziHealthKitFHIR
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
            "l": "L",
            "[iU]": "IU"
        ]
        let knownDivergences: Set<KnownDivergence> = [
            .init(sampleType: .bodyMassIndex, ucumUnitString: "kg/m2", healthKitCanUnit: .count()),
            .init(sampleType: .physicalEffort, ucumUnitString: "kcal/(kg.h)", healthKitCanUnit: HKUnit(from: "kcal/hr·kg")),
            .init(sampleType: .headphoneAudioExposure, ucumUnitString: "dB[SPL]", healthKitCanUnit: HKUnit(from: "dBASPL")),
            .init(sampleType: .environmentalAudioExposure, ucumUnitString: "dB[SPL]", healthKitCanUnit: HKUnit(from: "dBASPL")),
            .init(sampleType: .environmentalSoundReduction, ucumUnitString: "dB[SPL]", healthKitCanUnit: HKUnit(from: "dBASPL")),
            .init(sampleType: .vo2Max, ucumUnitString: "mL/kg/min", healthKitCanUnit: HKUnit(from: "mL/min·kg"))
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
