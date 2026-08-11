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
import SwiftUI


struct MeasurementsTestView: View {
    @Environment(HealthMeasurements.self)
    private var healthMeasurements

    @State private var samples: [HKSample] = []
    @State private var hideUnavailableView = false

    var body: some View {
        @Bindable var healthMeasurements = healthMeasurements
        NavigationStack { // swiftlint:disable:this closure_body_length
            Group {
                if samples.isEmpty {
                    if !hideUnavailableView {
                        ContentUnavailableView(
                            "No Samples",
                            systemImage: "heart.text.square",
                            description: Text("Please add new measurements.")
                        )
                    } else {
                        Text(verbatim: "")
                    }
                } else {
                    List {
                        ForEach(samples, id: \.uuid) { sample in
                            HKSampleView(sample)
                        }
                    }
                }
            }
                .navigationTitle("Measurements")
                .sheet(isPresented: $healthMeasurements.shouldPresentMeasurements) {
                    MeasurementsRecordedSheet { samples in
                        self.samples.append(contentsOf: samples)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Measurement", systemImage: "plus") {
                            healthMeasurements.shouldPresentMeasurements = true
                        }
                    }
                    ToolbarItemGroup(placement: .secondaryAction) {
                        Button("Simulate Weight", systemImage: "scalemass.fill") {
                            healthMeasurements.loadMockWeightMeasurement()
                        }
                        Button("Simulate Blood Pressure", systemImage: "heart.fill") {
                            healthMeasurements.loadMockBloodPressureMeasurement()
                        }
                        Button("\(hideUnavailableView ? "Show" : "Hide") Unavailable View", systemImage: "macwindow.on.rectangle") {
                            hideUnavailableView.toggle()
                        }
                    }
                }
        }
    }

    init() {}
}


#Preview {
    MeasurementsTestView()
        .previewWith {
            HealthMeasurements()
        }
}
