//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveHealthKit
import SwiftUI


struct ContentView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(TestView.allCases) { testView in
                        NavigationLink(testView.rawValue) {
                            testView.view
                        }
                    }
                }
                Section("Other") {
                    NavigationLink("Read Data (heartRate)") {
                        ReadDataView(.heartRate)
                    }
                    NavigationLink("Read Data (basalBodyTemperature)") {
                        ReadDataView(.basalBodyTemperature)
                    }
                }
            }
            .navigationBarTitle("GroveHealthKitFHIR Tests")
        }
    }
}
