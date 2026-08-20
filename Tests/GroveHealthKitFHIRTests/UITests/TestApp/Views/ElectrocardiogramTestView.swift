//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct ElectrocardiogramTestView: View {
    var body: some View {
        ContentUnavailableView(
            "Handled by Grove Sensor FHIR",
            systemImage: "waveform.path.ecg",
            description: Text("ECG voltage series use the Sensor ECG/raw graph rather than the point-measurement HealthKit facade.")
        )
        .navigationTitle("Electrocardiogram")
    }
}
