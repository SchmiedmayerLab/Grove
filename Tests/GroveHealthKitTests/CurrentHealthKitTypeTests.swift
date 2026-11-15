//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKit
import Testing
#if canImport(HealthKit)
import HealthKit
#endif


struct CurrentHealthKitTypeTests {
    @Test
    func typedHypertensionLookupMatchesTheSDKAndHasExplicitTranslations() throws {
        if #available(iOS 26.2, macOS 26.2, watchOS 26.2, visionOS 26.2, *) {
            let type = try #require(SampleType<HKCategorySample>(.hypertensionEvent))
            #expect(type == .hypertensionEvent)
            #expect(type.hkSampleType.identifier == HKCategoryTypeIdentifier.hypertensionEvent.rawValue)
            for locale in ["en", "en_GB", "de", "fr", "es", "es_US"] {
                #expect(type.localizedTitle(in: .init(identifier: locale))?.isEmpty == false)
            }
        }
    }

    @Test
    func currentSDKTypesHaveTypedSelectorsCanonicalUnitsAndTranslations() throws {
        if #available(iOS 27, macOS 27, watchOS 27, visionOS 27, *) {
            let quantity = try #require(SampleType<HKQuantitySample>(.heartRateVariabilityRMSSD))
            #expect(quantity == .heartRateVariabilityRMSSD)
            #expect(quantity.canonicalUnit == .secondUnit(with: .milli))
            let types: [SampleType<HKCategorySample>] = [.bleedingAfterMenopause, .menopausalState]
            for type in types {
                #expect(SampleType<HKCategorySample>(type.hkSampleType) == type)
                for locale in ["en", "en_GB", "de", "fr", "es", "es_US"] {
                    #expect(type.localizedTitle(in: .init(identifier: locale))?.isEmpty == false)
                    #expect(quantity.localizedTitle(in: .init(identifier: locale))?.isEmpty == false)
                }
            }
        }
    }
}
