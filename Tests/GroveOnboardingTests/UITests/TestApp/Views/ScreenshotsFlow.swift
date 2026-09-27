//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order line_length

import GroveFoundation
import GroveOnboarding
import GroveViews
import SwiftUI


struct ScreenshotsFlow: View {
    var body: some View {
        ManagedNavigationStack {
            Welcome()
            InterestingModules()
            HealthKitPermissions()
            StudyDetails()
        }
    }
}


private struct Welcome: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    
    var body: some View {
        PageView {
            PageHeader(
                title: "Heart Health Study",
                subtitle: "How everyday activity shapes a healthy heart."
            )
        } content: {
            OnboardingInformationView {
                OnboardingInformationView.Area(
                    iconSymbol: "applewatch",
                    title: "Wear Your Watch",
                    description: "Heart rate and activity are recorded the way they already are; nothing extra to do."
                )
                OnboardingInformationView.Area(
                    iconSymbol: "list.clipboard",
                    title: "Weekly Check-Ins",
                    description: "A short questionnaire once a week asks how you have been feeling and what your days were like."
                )
                OnboardingInformationView.Area(
                    iconSymbol: "lock.shield",
                    title: "Your Data Stays Yours",
                    description: "Everything stays on your device until you choose to share it with the study team."
                )
                OnboardingInformationView.Area(
                    iconSymbol: "chart.line.uptrend.xyaxis",
                    title: "See What Changes",
                    description: "Your own trends are shown back to you as the weeks go by, alongside what the study learns."
                )
            }
        } footer: {
            PageActions(
                primaryTitle: "Learn More",
                primaryAction: { path.nextStep() },
                secondaryTitle: "Not Now",
                secondaryAction: { path.nextStep() }
            )
        }
    }
}


private struct InterestingModules: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    
    var body: some View {
        SequentialOnboardingView(
            title: "What to Expect",
            subtitle: "Four steps, and the study begins.",
            steps: [
                .init(title: "Consent", description: "Read what taking part means and sign on the next page."),
                .init(title: "Health Access", description: "Allow the app to read heart rate and activity from Apple Health."),
                .init(title: "First Check-In", description: "Answer the first weekly questionnaire; it takes about two minutes."),
                .init(title: "Reminders", description: "Choose the evening you would like to be reminded each week.")
            ],
            actionText: "Continue"
        ) {
            path.nextStep()
        }
    }
}


private struct HealthKitPermissions: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    
    var body: some View {
        PageView {
            PageHeader(
                title: "Health Access",
                subtitle: "Your Health data stays on your device unless you decide otherwise.",
                image: Image(systemName: "heart.text.square") // swiftlint:disable:this accessibility_label_for_image
            )
        } content: {
            VStack(alignment: .leading) {
                Text(
                    """
                    Grant read-only permission to access your Health data, in order to view Health summaries and stats in the app, and to perform background processing of your Health data.
                    
                    You can revoke this at any time.
                    """
                )
            }
        } footer: {
            PageActions(
                primaryTitle: "Grant Access",
                primaryAction: {
                    path.nextStep()
                },
                secondaryTitle: "Later",
                secondaryAction: {
                    path.nextStep()
                }
            )
        }
    }
}


private struct StudyDetails: View {
    private static let sections = [
        "Taking part is voluntary. You can stop at any time, without giving a reason and without any effect on your care.",
        "The study reads heart rate and activity data from Apple Health on this device, and the answers you give in the weekly check-ins.",
        "Nothing leaves your device until you choose to share it. Shared data is encrypted in transit and at rest and stored on servers of the study team.",
        "The study team sees your data under a participant number, not your name. Your name is kept separately, for the consent record only.",
        "You can ask for your data to be deleted at any time; data already included in published results cannot be withdrawn.",
        "The study runs for eight weeks. Each week's check-in is available from Friday evening and takes about two minutes.",
        "Results are shared with you at the end of the study, together with a summary of what the study learned across all participants.",
        "Questions about the study go to the study team through the app, and questions about your rights as a participant to the review board named in the consent."
    ]

    @Environment(ManagedNavigationStack.Path.self) private var path

    var body: some View {
        PageView {
            PageHeader(
                title: "Study Details",
                subtitle: "What taking part means, in full."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, section in
                    Text("\(index + 1). \(section)")
                }
            }
        } footer: {
            PageActions("I Understand") {
                path.nextStep()
            }
        }
    }
}
