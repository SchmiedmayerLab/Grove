//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveViews
public import SwiftUI


/// Onboarding view to display markdown-based consent documents that can be signed and exported.
///
/// ![A consent page with the document, the name fields and a drawn signature.](SignedConsent)
///
/// The ``OnboardingConsentView`` embeds a ``ConsentDocumentView`` into a `PageView`, so it takes its place in an onboarding flow like any other step.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct OnboardingConsentView: View {
    /// Provides default localization values for necessary fields in the ``OnboardingConsentView``.
    public enum LocalizationDefaults {
        /// Default localized value for the title of the consent form.
        public static var consentFormTitle: LocalizedStringResource {
            LocalizedStringResource("CONSENT_VIEW_TITLE", bundle: .module)
        }
    }
    
    private let title: LocalizedStringResource?
    private let action: @MainActor () async throws -> Void
    private let currentDateInSignature: Bool
    private var consentDocument: ConsentDocument?
    @Binding private var viewState: ViewState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the taps that found the form incomplete, so each of them can be felt.
    @State private var incompleteAttempts = 0
    
    public var body: some View {
        // The reader wraps the page, so the button floating over it can still scroll the document.
        ScrollViewReader { proxy in
            PageView {
                if let title {
                    PageHeader(title: title)
                }
            } content: {
                if let consentDocument {
                    ConsentDocumentView(
                        consentDocument: consentDocument,
                        consentSignatureDate: currentDateInSignature ? .now : nil
                    )
                    #if !(os(macOS) || os(visionOS))
                    .scrollDismissesKeyboard(.interactively)
                    #endif
                    .disabled(viewState == .processing)
                } else {
                    ProgressView(LocalizedStringResource("Loading…", bundle: .module))
                }
            } footer: {
                actionButton(scrollingWith: proxy)
            }
        }
        .scrollDisabled(consentDocument?.isSigning == true)
        .navigationBarBackButtonHidden(backButtonHidden)
    }

    private var isComplete: Bool {
        consentDocument?.completionState == .complete
    }

    private var backButtonHidden: Bool {
        guard let consentDocument else {
            return false
        }
        return consentDocument.isExporting
    }


    /// Creates an `OnboardingConsentView` for a file-based consent document.
    ///
    /// - parameter consentDocument: The Consent Document.
    ///     Pass `nil` if your app is currently still loading the document, but already wishes to display a "loading in progress" version of the ``OnboardingConsentView``.
    /// - parameter title: The title of the view displayed at the top. Can be `nil`, meaning no title is displayed.
    /// - parameter currentDateInSignature: Whether the current date should be included in the consent form's signature fields.
    /// - parameter viewState: A binding that provides the `ViewState` the view should use.
    /// - parameter action: The action to perform when the user has completed the consent form and taps the button below it.
    public init(
        consentDocument: ConsentDocument?,
        title: LocalizedStringResource? = LocalizationDefaults.consentFormTitle,
        currentDateInSignature: Bool = true,
        viewState: Binding<ViewState>,
        action: @escaping @MainActor () async throws -> Void
    ) {
        self.consentDocument = consentDocument
        self.title = title
        self.currentDateInSignature = currentDateInSignature
        self._viewState = viewState
        self.action = action
    }

    private func actionButton(scrollingWith proxy: ScrollViewProxy) -> some View {
        AsyncButton(state: $viewState) {
            try await confirm(scrollingWith: proxy)
        } label: {
            Text("CONSENT_ACTION", bundle: .module)
                .bold()
                .frame(maxWidth: .infinity)
                .processingOverlay(isProcessing: backButtonHidden)
        }
        .actionButtonStyle(.primary)
        .controlSize(.large)
        .disabled(consentDocument == nil || consentDocument?.isExporting == true)
        .accessibilityValue(isComplete ? Text("CONSENT_STATE_READY", bundle: .module) : Text("CONSENT_STATE_INCOMPLETE", bundle: .module))
        .accessibilityHint(Text("CONSENT_ACTION_HINT", bundle: .module))
        .sensoryFeedback(.warning, trigger: incompleteAttempts)
    }

    /// Continues with a complete form; an incomplete one is marked where it is missing an answer and scrolled there.
    private func confirm(scrollingWith proxy: ScrollViewProxy) async throws {
        guard let consentDocument else {
            return
        }
        guard case .incomplete(let firstIncompleteId) = consentDocument.completionState else {
            try await action()
            return
        }
        incompleteAttempts += 1
        AccessibilityNotification.Announcement(String(localized: "CONSENT_INCOMPLETE_ANNOUNCEMENT", bundle: .module)).post()
        withAnimation(reduceMotion ? nil : .revisit) {
            consentDocument.highlightsIncompleteSections = true
            proxy.scrollTo(firstIncompleteId, anchor: .center)
        }
    }
}

#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    @Previewable @State var viewState: ViewState = .idle
    let document = try? ConsentDocument(markdown: "This is a *markdown* **example**")
    NavigationStack {
        OnboardingConsentView(consentDocument: document, viewState: $viewState) {
            print("Next")
        }
    }
}
#endif
