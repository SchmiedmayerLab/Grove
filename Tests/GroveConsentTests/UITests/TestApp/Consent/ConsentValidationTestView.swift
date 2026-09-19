//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveConsent
import GroveViews
import SwiftUI


struct ConsentValidationTestView: View {
    @State private var document = try? ConsentDocument(markdown: """
        <toggle id=agree expected-value=true>I agree</toggle>
        <toggle id=excluded initial-value=true expected-value=false>I am enrolled in an incompatible study</toggle>
        """)
    @State private var isPresented = false
    @State private var submissions = 0
    @State private var viewState: ViewState = .idle

    var body: some View {
        VStack {
            Button("Open Consent") {
                isPresented = true
            }
            Text("Submissions: \(submissions)")
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                OnboardingConsentView(consentDocument: document, viewState: $viewState) {
                    submissions += 1
                    isPresented = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Dismiss Consent") {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}
