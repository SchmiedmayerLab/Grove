//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import Grove
@_spi(TestingSupport)
import GroveDevices
import GroveDevicesUI
import GroveViews
import SwiftUI


struct HKCorrelationView: View {
    private let correlation: HKCorrelation

    var body: some View {
        if let systolic = correlation.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample {
            HKQuantitySampleView(systolic)
        }
        if let diastolic = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample {
            HKQuantitySampleView(diastolic)
        }
    }

    init(_ correlation: HKCorrelation) {
        self.correlation = correlation
    }
}


#Preview {
    List {
        HKCorrelationView(.mockBloodPressureSample)
    }
}
