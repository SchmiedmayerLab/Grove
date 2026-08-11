//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import HealthKit
@_spi(TestingSupport)
import SpeziDevices
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
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
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    MeasurementLayer(measurement: .weight(.mockWeighSample))
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    MeasurementLayer(measurement: .weight(.mockWeighSample, bmi: .mockBmiSample, height: .mockHeightSample))
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    MeasurementLayer(measurement: .bloodPressure(.mockBloodPressureSample, heartRate: .mockHeartRateSample))
}
#endif
