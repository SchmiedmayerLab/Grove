//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length file_types_order

import SpeziConsent
import SpeziOnboarding
import SpeziViews
import SwiftUI


private struct ScreenshotView: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    @State private var document: ConsentDocument?
    @State private var viewState: ViewState = .idle
    
    let markdown: String
    
    var body: some View {
        OnboardingConsentView(
            consentDocument: document,
            title: "Consent",
            currentDateInSignature: true,
            viewState: $viewState
        ) {
            path.nextStep()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConsentShareButton(consentDocument: document, viewState: $viewState)
            }
        }
        .viewStateAlert(state: $viewState)
        .task {
            do {
                document = try ConsentDocument(markdown: markdown, initialName: .init(givenName: "Leland", familyName: "Stanford"))
            } catch {
                viewState = .error(AnyLocalizedError(error: error))
            }
        }
    }
}


struct ScreenshotView1: View {
    private static let markdown = """
        Spezi can render *markdown-based* **consent** documents.
        
        ---
        
        Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua.
        At vero eos et accusam et justo duo dolores et ea rebum.
        Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.
        <signature id=sig1 />
        """
    
    var body: some View {
        ScreenshotView(markdown: Self.markdown)
    }
}


struct ScreenshotView2: View {
    private static let markdown = """
        A consent document can also contain interactive elements.
        
        <toggle id=t1>
            Would you like to be informed about future, related studies?
        </toggle>
        
        <select id=s1>
            How often do you participate in research studies like this one?
            <option id=o1>Never</>
            <option id=o2>Sometimes</>
            <option id=o3>Frequently</>
        </select>
        
        <signature id=sig1 />
        """
    
    var body: some View {
        ScreenshotView(markdown: Self.markdown)
    }
}


struct ScreenshotView3: View {
    private static let markdown = """
        You can even require certain selections for the user to be allowed to proceed.
        
        <select id=t1 initial-value=n expected-value=y>
            I understand that as part of this research study, my anonymized health data will be collected and used for scientific research purposes.
            <option id=y>Yes</>
            <option id=n>No</>
        </select>
        
        <signature id=sig1 />
        """
    
    var body: some View {
        ScreenshotView(markdown: Self.markdown)
    }
}
