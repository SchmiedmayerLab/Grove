//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct CreateWorkoutView: View {
    var body: some View {
        ContentUnavailableView(
            "No v0.2 Workout Profile",
            systemImage: "figure.run",
            description: Text("Workout is listed as no-published-contract in the authoritative HealthKit coverage matrix.")
        )
        .navigationTitle("Workout")
    }
}
