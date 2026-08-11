//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveConsent
import GroveViews
import SwiftUI


struct ContentView: View {
    private struct PresentedConsentDocument: Hashable, Identifiable {
        enum Mode {
            case standalone, rendered
        }
        let mode: Mode
        let docId: ConsentDocumentIdentifier
        var id: Self { self }
    }
    
    @Environment(TestAppConsentStorage.self) private var consentStorage
    
    @State private var presentedConsentDoc: PresentedConsentDocument?
    @State private var isPresentingOnboardingFlow = false
    @State private var isPresentingScreenshotView = false
    
    var body: some View {
        Form {
            Section {
                ForEach(ConsentDocumentIdentifier.allCases) { docId in
                    Button(docId.title) {
                        presentedConsentDoc = .init(mode: .standalone, docId: docId)
                    }
                    Button("\(docId.title) (Rendered)") {
                        presentedConsentDoc = .init(mode: .rendered, docId: docId)
                    }
                    .disabled(consentStorage.exportResults[docId] == nil)
                }
            }
            .accessibilityElement()
            .accessibilityIdentifier("Section:Standalone")
            Section {
                Button("Start Onboarding Flow") {
                    isPresentingOnboardingFlow = true
                }
            }
            Section {
                Button("Screenshots") {
                    isPresentingScreenshotView = true
                }
            }
        }
        .navigationTitle("GroveConsent")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedConsentDoc) { item in
            switch item.mode {
            case .standalone:
                NavigationStack {
                    StandaloneConsent(docId: item.docId)
                }
                .interactiveDismissDisabled()
                .adjustingSizeOnVisionOS()
            case .rendered:
                NavigationStack {
                    RenderedConsentDocumentView(docId: item.docId)
                }
                .interactiveDismissDisabled()
                .adjustingSizeOnVisionOS()
            }
        }
        .sheet(isPresented: $isPresentingOnboardingFlow) {
            ManagedNavigationStack {
                OnboardingConsent(docId: .first)
                OnboardingConsent(docId: .second)
                OnboardingConsent(docId: .interactive)
                RenderedConsentDocumentView(docId: .first)
                RenderedConsentDocumentView(docId: .second)
                RenderedConsentDocumentView(docId: .interactive)
            }
            .adjustingSizeOnVisionOS()
        }
        .sheet(isPresented: $isPresentingScreenshotView) {
            ManagedNavigationStack {
                ScreenshotView1()
                ScreenshotView2()
                ScreenshotView3()
            }
            .adjustingSizeOnVisionOS()
        }
    }
}


extension View {
    func adjustingSizeOnVisionOS() -> some View {
        #if os(visionOS)
        self.frame(width: 1250, height: 1250)
        #else
        self
        #endif
    }
}
