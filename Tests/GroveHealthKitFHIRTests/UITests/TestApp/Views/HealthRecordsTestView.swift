//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct HealthRecordsTestView: View {
    var body: some View {
        ContentUnavailableView(
            "Clinical Records Are Not Re-mapped",
            systemImage: "doc.text.magnifyingglass",
            description: Text("GroveHealthKitFHIR converts admitted mobile measurements. It does not reinterpret embedded Health Records or DSTU2 resources.")
        )
        .navigationTitle("Health Records")
    }
}
