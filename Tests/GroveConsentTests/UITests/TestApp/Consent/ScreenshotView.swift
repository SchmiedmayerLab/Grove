//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length file_types_order

import GroveConsent
import GroveOnboarding
import GroveViews
import SwiftUI


private struct ScreenshotView: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    @State private var document: ConsentDocument?
    @State private var viewState: ViewState = .idle
    
    let markdown: String
    
    var body: some View {
        OnboardingConsentView(
            consentDocument: document,
            title: "Study Consent",
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
        You are invited to take part in a research study on how everyday activity relates to heart health.
        Taking part means wearing your Apple Watch as you normally would and answering a short check-in once a week for eight weeks.

        The study reads heart rate and activity data from Apple Health on this device, together with the answers you give in the weekly check-ins.
        Nothing leaves your device until you choose to share it. Shared data is encrypted in transit and stored on servers of the study team.

        The study team sees your data under a participant number, not your name. Your name is kept separately, for the consent record only.
        You can ask for your data to be deleted at any time. Data already included in published results cannot be withdrawn.

        You can withdraw at any time without giving a reason, and withdrawing has no effect on your care.
        Results are shared with you at the end of the study, together with a summary of what the study learned across all participants.

        Please sign below to confirm that you have read this and agree to take part.
        <signature id=sig1 />
        """

    var body: some View {
        ScreenshotView(markdown: Self.markdown)
    }
}


struct ScreenshotView2: View {
    private static let markdown = """
        Before we begin, a few choices about your participation.

        <toggle id=t1>
            Let me know about related studies I could join later.
        </toggle>

        <select id=s1>
            How often have you taken part in research studies like this one?
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
        To take part, please confirm the following.

        <select id=t1 initial-value=n expected-value=y>
            I understand that my anonymized health data will be collected and used for scientific research.
            <option id=y>Yes</>
            <option id=n>No</>
        </select>

        <signature id=sig1 />
        """

    var body: some View {
        ScreenshotView(markdown: Self.markdown)
    }
}
