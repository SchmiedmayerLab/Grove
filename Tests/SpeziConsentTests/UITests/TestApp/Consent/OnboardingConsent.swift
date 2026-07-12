//
// This source file is part of the SpeziConsent open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziConsent
import SpeziFoundation
import SpeziOnboarding
import SpeziViews
import SwiftUI


struct OnboardingConsent: View {
    let docId: ConsentDocumentIdentifier
    
    @Environment(TestAppConsentStorage.self) private var consentStorage
    @Environment(ManagedNavigationStack.Path.self) private var path
    
    @State private var consentDocument: ConsentDocument?
    @State private var viewState: ViewState = .idle
    
    var body: some View {
        OnboardingConsentView(
            consentDocument: consentDocument,
            title: (consentDocument?.metadata.title).map { "\($0)" },
            viewState: $viewState
        ) {
            guard let consentDocument else {
                preconditionFailure("No consent document.")
            }
            consentStorage.exportResults[docId] = try? consentDocument.export(using: .init())
            path.nextStep()
        }
        .viewStateAlert(state: $viewState)
        .scrollIndicators(.visible)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConsentShareButton(
                    consentDocument: consentDocument,
                    viewState: $viewState
                )
            }
        }
        .task {
            consentDocument = .for(docId)
        }
    }
}
