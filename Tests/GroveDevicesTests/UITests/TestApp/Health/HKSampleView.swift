//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
@_spi(TestingSupport)
import GroveDevices
import SwiftUI


struct HKSampleView: View {
    private let sample: HKSample

    var body: some View {
        switch sample.sampleType {
        case HKQuantityType(.heartRate), HKQuantityType(.bodyMass), HKQuantityType(.bodyMassIndex), HKQuantityType(.height):
            HKQuantitySampleView(sample as! HKQuantitySample) // swiftlint:disable:this force_cast
        case HKCorrelationType(.bloodPressure):
            HKCorrelationView(sample as! HKCorrelation) // swiftlint:disable:this force_cast
        default:
            Text("Unknown sample type: \(sample.sampleType)")
        }
    }


    init(_ sample: HKSample) {
        self.sample = sample
    }
}


#Preview {
    List {
        HKSampleView(HKQuantitySample.mockWeighSample)
    }
}

#Preview {
    List {
        HKSampleView(HKQuantitySample.mockBmiSample)
    }
}

#Preview {
    List {
        HKSampleView(HKQuantitySample.mockHeightSample)
    }
}

#Preview {
    List {
        HKSampleView(HKQuantitySample.mockHeartRateSample)
    }
}

#Preview {
    List {
        HKSampleView(HKCorrelation.mockBloodPressureSample)
    }
}
