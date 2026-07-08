//
// This source file is part of the Stanford SpeziDevices open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import HealthKit
@_spi(TestingSupport)
import SpeziDevices
import SwiftUI


@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
struct MeasurementLayer: View {
    private let measurement: HealthKitMeasurement

    var body: some View {
        VStack(spacing: 15) {
            switch measurement {
            case let .weight(sample, bmiSample, heightSample):
                WeightMeasurementLabel(sample, bmi: bmiSample, height: heightSample)
            case let .bloodPressure(bloodPressure, heartRate):
                BloodPressureMeasurementLabel(bloodPressure, heartRate: heartRate)
            }
        }
            .accessibilityElement(children: .combine)
            .multilineTextAlignment(.center)
    }


    init(measurement: HealthKitMeasurement) {
        self.measurement = measurement
    }
}


#if DEBUG
@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    MeasurementLayer(measurement: .weight(.mockWeighSample))
}

@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    MeasurementLayer(measurement: .weight(.mockWeighSample, bmi: .mockBmiSample, height: .mockHeightSample))
}

@available(iOS 17, macOS 14, macCatalyst 17, visionOS 1, *)
#Preview {
    MeasurementLayer(measurement: .bloodPressure(.mockBloodPressureSample, heartRate: .mockHeartRateSample))
}
#endif
