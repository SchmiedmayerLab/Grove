//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@_spi(Testing)
@testable import GroveHealthKit
import Testing


@Suite
struct SampleTypesTests {
    #if canImport(HealthKit)
    @Test
    func isSampleType() {
        let quantitySample = HKQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: HKQuantity(unit: .largeCalorie(), doubleValue: 128),
            start: .now,
            end: .now
        )
        #expect(quantitySample.is(.activeEnergyBurned))
        #expect(!quantitySample.is(.sleepAnalysis))
        #expect(!quantitySample.is(.bloodPressure))
        
        let categorySample = HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            start: .now,
            end: .now
        )
        #expect(categorySample.is(.sleepAnalysis))
        #expect(!categorySample.is(.activeEnergyBurned))
        #expect(!categorySample.is(.bloodPressure))
        
        let correlation = HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: .now,
            end: .now,
            objects: [
                HKQuantitySample(
                    type: HKQuantityType(.bloodPressureSystolic),
                    quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 420),
                    start: .now,
                    end: .now
                ),
                HKQuantitySample(
                    type: HKQuantityType(.bloodPressureDiastolic),
                    quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 69),
                    start: .now,
                    end: .now
                )
            ]
        )
        #expect(correlation.is(.bloodPressure))
        #expect(!correlation.is(.activeEnergyBurned))
        #expect(!correlation.is(.sleepAnalysis))
    }
    #endif
    
    
    @Test
    func displayTitles() {
        for sampleType in HKObjectType.allKnownObjectTypes.compactMap(\.sampleType) + SampleType<HKQuantitySample>.otherSampleTypes {
            // SampleType uses the underlying HKSampleType's identifier as its fallback title if no localized title exists;
            // we need to ensure this never happens.
            // Note: since the translations are bundled with the package, rather than fetched dynamically from HealthKit,
            // this test passing for a version GroveHealthKit means that that version will always have proper display titles for
            // the various sample types, regardless of the OS version the package is running on.
            #expect(sampleType.displayTitle != sampleType.hkSampleType.identifier)
            // Additionally, we want to ensure that, even if other languages might be missing, the english translation is always available.
            #expect(sampleType.localizedTitle(in: .init(identifier: "en")) != nil)
        }
    }
    
    
    @Test
    func localizations() throws {
        let english = Locale.Language(identifier: "en")
        let englishUK = Locale.Language(identifier: "en_GB")
        let german = Locale.Language(identifier: "de")
        let french = Locale.Language(identifier: "fr")
        let spanish = Locale.Language(identifier: "es")
        let spanishUS = Locale.Language(identifier: "es_US")
        
        let heartRate = SampleType.heartRate
        #expect(heartRate.localizedTitle(in: english) == "Heart Rate")
        #expect(heartRate.localizedTitle(in: englishUK) == "Heart Rate")
        #expect(heartRate.localizedTitle(in: german) == "Herzfrequenz")
        #expect(heartRate.localizedTitle(in: french) == "Fréquence cardiaque")
        #expect(heartRate.localizedTitle(in: spanish) == "Frecuencia cardiaca")
        #expect(heartRate.localizedTitle(in: spanishUS) == "Frecuencia cardiaca")
        
        let food = SampleType.food
        #expect(food.displayTitle == "Nutrition")
        #expect(food.localizedTitle(in: english) == "Nutrition")
        #expect(food.localizedTitle(in: englishUK) == "Nutrition")
        #expect(food.localizedTitle(in: german) == "Ernährung")
        #expect(food.localizedTitle(in: french) == "Nutrition")
        #expect(food.localizedTitle(in: spanish) == "Nutrición")
        #expect(food.localizedTitle(in: spanishUS) == "Nutrición")
        
        let walkingAsymetry = SampleType.walkingAsymmetryPercentage
        #expect(walkingAsymetry.localizedTitle(in: english) == "Walking Asymmetry")
        #expect(walkingAsymetry.localizedTitle(in: englishUK) == "Walking Asymmetry")
        #expect(walkingAsymetry.localizedTitle(in: german) == "Asymmetrischer Gang")
        #expect(walkingAsymetry.localizedTitle(in: french) == "Asymétrie de la marche")
        #expect(walkingAsymetry.localizedTitle(in: spanish) == "Asimetría de la marcha")
        #expect(walkingAsymetry.localizedTitle(in: spanishUS) == "Asimetría al caminar")
        
        let thiamin = SampleType.dietaryThiamin
        #expect(thiamin.localizedTitle(in: english) == "Thiamin")
        #expect(thiamin.localizedTitle(in: englishUK) == "Thiamine")
    }
    
    
    @Test
    func bundleLocalizationUtils() throws {
        let bundle = HealthKit.bundle
        #expect(bundle.developmentLocalization == "en")
        
        func fallbackKey(
            key: String,
            tables: [Bundle.LocalizationLookupTable],
            localizations: [Locale.Language]
        ) -> String? {
            let primary = bundle.localizedString(forKey: key, tables: tables, localizations: localizations)
            let fallback = bundle.localizedStringForKeyFallback(key: key, tables: tables, localizations: localizations)
            #expect(primary == fallback)
            return fallback
        }
        
        #expect(fallbackKey(
            key: SampleType.food.id,
            tables: [.custom("Localizable-HKTypes")],
            localizations: [.init(identifier: "en")]
        ) == "Nutrition")
        #expect(fallbackKey(
            key: SampleType.food.id,
            tables: [.custom("Localizable-HKTypes"), .default],
            localizations: [.init(identifier: "en")]
        ) == "Nutrition")
        #expect(fallbackKey(
            key: SampleType.food.id,
            tables: [.default],
            localizations: [.init(identifier: "en")]
        ) == nil)
        #expect(fallbackKey(
            key: SampleType.food.id,
            tables: [.custom("Localizable-HKTypes"), .default],
            localizations: [.init(identifier: "jp")]
        ) == "Nutrition")
        #expect(fallbackKey(
            key: SampleType.food.id,
            tables: [.custom("Localizable-HKTypes"), .default],
            localizations: [.init(identifier: "jp"), .init(identifier: "en")]
        ) == "Nutrition")
    }
    
    
    @Test
    func sampleTypeSwitching() {
        let sampleType = SampleTypeProxy(.heartburn)
        guard case .category(.heartburn) = sampleType else {
            Issue.record("Pattern matching failed.")
            return
        }
    }
    
    #if canImport(HealthKit)
    @Test
    func allKnown() {
        #expect(SampleType<HKQuantitySample>.allKnownQuantities.mapIntoSet(\.hkSampleType) == HKQuantityType.allKnownQuantities)
        #expect(SampleType<HKCorrelation>.allKnownCorrelations.mapIntoSet(\.hkSampleType) == HKCorrelationType.allKnownCorrelations)
        #expect(SampleType<HKCategorySample>.allKnownCategories.mapIntoSet(\.hkSampleType) == HKCategoryType.allKnownCategories)
    }
    #endif
    
    
    @Test
    func canUnit() {
        for quantityType in SampleType<HKQuantitySample>.allKnownQuantities {
            #expect(
                quantityType.hkSampleType.is(compatibleWith: quantityType.canonicalUnit),
                "invalid canUnit '\(quantityType.canonicalUnit)' for sample type '\(quantityType)' (hk suggestion: \(quantityType.hkCanonicalUnit))"
            )
        }
    }
    
    @Test(arguments: [Locale.enUS, .enGB, .esUS, .deDE, .frFR])
    func diaplayUnitValidity(locale: Locale) {
        for quantityType in SampleType<HKQuantitySample>.allKnownQuantities {
            #expect(quantityType.displayUnit(for: locale).isCompatible(with: quantityType.canonicalUnit))
        }
    }
}


extension HKQuantityType {
    var hkCanonicalUnit: HKUnit {
        #if canImport(Darwin)
        // SAFETY: we're in the tests here
        self.value(forKey: "canonicalUnit") as! HKUnit // swiftlint:disable:this force_cast
        #else
        // we're on Linux are are using our custom `HKQuantityType` implementation instead of the HealthKit one.
        self._canonicalUnit! // swiftlint:disable:this force_unwrapping
        #endif
    }
}
