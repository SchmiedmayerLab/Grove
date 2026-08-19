//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


struct SkeletonLoadingExample: View {
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary)
                .frame(height: 100)
                .skeletonLoading(replicationCount: 5, repeatInterval: 1.5, spacing: 16)
            Spacer()
        }
            .padding()
    }
}


#if DEBUG
#Preview {
    SkeletonLoadingExample()
}
#endif
