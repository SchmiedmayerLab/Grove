//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziConsent
import SpeziFoundation
import SpeziOnboarding
import SpeziViews
import SwiftUI


struct StandaloneConsent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TestAppConsentStorage.self) private var consentStorage
    
    let docId: ConsentDocumentIdentifier
    @State private var consentDocument: ConsentDocument?
    @State private var viewState: ViewState = .idle
    
    var body: some View {
        VStack {
            if let consentDocument {
                GeometryReader { geometry in
                    ScrollView {
                        ConsentDocumentView(consentDocument: consentDocument)
                            .padding(.horizontal)
                            .frame(minHeight: geometry.size.height)
                    }
                }
            } else {
                ProgressView("Fetching Consent…")
            }
        }
        .viewStateAlert(state: $viewState)
        .scrollIndicators(.visible)
        .navigationTitle(consentDocument?.metadata.title ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AsyncButton(state: $viewState) {
                    guard let consentDocument else {
                        return
                    }
                    consentStorage.exportResults[docId] = try consentDocument.export(using: .init())
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .accessibilityLabel("Done")
                }
                .buttonStyleGlassProminent()
                .disabled(consentDocument?.completionState != .complete)
            }
            ToolbarItem(placement: .topBarTrailing) {
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
