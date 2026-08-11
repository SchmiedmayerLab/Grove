//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveOnboarding
import GroveViews
import SwiftUI


struct OnboardingTestsView: View {
    @Binding var onboardingFlowComplete: Bool
    @State var showConditionalView = false

    
    var body: some View {
        ManagedNavigationStack(didComplete: $onboardingFlowComplete) {
            OnboardingStartTestView(
                showConditionalView: $showConditionalView
            )
            OnboardingWelcomeTestView()
            OnboardingSequentialTestView()
            OnboardingTestViewNotIdentifiable(text: "Leland")
                .navigationStepIdentifier("a")
            OnboardingTestViewNotIdentifiable(text: "Stanford")
                .navigationStepIdentifier("b")
            OnboardingCustomToggleTestView(showConditionalView: $showConditionalView)
            if showConditionalView {
                OnboardingConditionalTestView()
            }
        }
    }
}


#if DEBUG
#Preview {
    OnboardingTestsView(onboardingFlowComplete: .constant(false))
}
#endif
