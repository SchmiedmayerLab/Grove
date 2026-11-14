//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@_spi(TestingSupport)
import GroveDevices
import HealthKit
import Testing


/// Every sample a measurement converts to states the zone its time stamp is read in.
@Suite
struct HealthKitTimeZoneMetadataTests {
    private static var currentZone: String {
        Calendar.current.timeZone.identifier
    }

    /// HealthKit silently drops a correlation whose zone differs from its members' (FB25571287, seen on iOS 27.2).
    @Test("A blood pressure correlation and both of its samples state the current zone")
    func bloodPressureStatesTheZone() {
        let correlation = HKCorrelation.mockBloodPressureSample
        #expect(correlation.metadata?[HKMetadataKeyTimeZone] as? String == Self.currentZone)
        #expect(correlation.objects.count == 2)
        for sample in correlation.objects {
            #expect(sample.metadata?[HKMetadataKeyTimeZone] as? String == Self.currentZone)
        }
    }

    @Test("Heart rate, weight, BMI and height samples state the current zone")
    func quantitySamplesStateTheZone() {
        let samples: [HKQuantitySample] = [.mockHeartRateSample, .mockWeighSample, .mockBmiSample, .mockHeightSample]
        for sample in samples {
            #expect(sample.metadata?[HKMetadataKeyTimeZone] as? String == Self.currentZone, "\(sample.quantityType)")
        }
    }
}
