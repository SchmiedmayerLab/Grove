//
// This source file is part of the Stanford Spezi open-source project
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
struct BloodPressureMeasurementLabel: View {
    private let bloodPressureSample: HKCorrelation
    private let heartRateSample: HKQuantitySample?

    @ScaledMetric private var measurementTextSize: CGFloat = 50

    private var systolic: HKQuantitySample? {
        bloodPressureSample
            .objects(for: HKQuantityType(.bloodPressureSystolic))
            .first as? HKQuantitySample
    }

    private var diastolic: HKQuantitySample? {
        bloodPressureSample
            .objects(for: HKQuantityType(.bloodPressureDiastolic))
            .first as? HKQuantitySample
    }

    var body: some View {
        if let systolic,
           let diastolic {
            VStack(spacing: 5) {
                Text(
                    "\(Int(systolic.quantity.doubleValue(for: .millimeterOfMercury())))/\(Int(diastolic.quantity.doubleValue(for: .millimeterOfMercury()))) mmHg",
                    bundle: .module
                )
                    .font(.system(size: measurementTextSize, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                if let heartRateSample {
                    Text("\(Int(heartRateSample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))) BPM", bundle: .module)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Invalid Sample", bundle: .module)
                .italic()
        }
    }


    init(_ bloodPressureSample: HKCorrelation, heartRate heartRateSample: HKQuantitySample? = nil) {
        self.bloodPressureSample = bloodPressureSample
        self.heartRateSample = heartRateSample
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    BloodPressureMeasurementLabel(.mockBloodPressureSample, heartRate: .mockHeartRateSample)
}
#endif
