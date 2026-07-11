//
// This source file is part of the Stanford SpeziDevices open source project
//
// SPDX-FileCopyrightText: 2024 Stanford University
//
// SPDX-License-Identifier: MIT
//

import HealthKit
@_spi(TestingSupport)
import SpeziDevices
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct WeightMeasurementLabel: View {
    private let sample: HKQuantitySample
    private let bmiSample: HKQuantitySample?
    private let heightSample: HKQuantitySample?

    @ScaledMetric private var measurementTextSize: CGFloat = 60

    private var additionalMeasurements: String? {
        var string: String?
        if let heightSample {
            string = "\(Int(heightSample.quantity.doubleValue(for: .meterUnit(with: .centi)))) cm"
        }

        if let bmiSample {
            string = (string.map { $0 + ",  " } ?? "")
                + "\(Int(bmiSample.quantity.doubleValue(for: .count()))) BMI"
        }

        return string
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(sample.quantity.description)
                .font(.system(size: measurementTextSize, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if let additionalMeasurements {
                Text(additionalMeasurements)
                    .accessibilityElement(children: .combine)
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    init(_ sample: HKQuantitySample, bmi bmiSample: HKQuantitySample? = nil, height heightSample: HKQuantitySample? = nil) {
        self.sample = sample
        self.bmiSample = bmiSample
        self.heightSample = heightSample
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    WeightMeasurementLabel(.mockWeighSample)
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    WeightMeasurementLabel(.mockWeighSample, bmi: .mockBmiSample, height: .mockHeightSample)
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    WeightMeasurementLabel(.mockWeighSample, bmi: .mockBmiSample)
}

@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    WeightMeasurementLabel(.mockWeighSample, height: .mockHeightSample)
}
#endif
