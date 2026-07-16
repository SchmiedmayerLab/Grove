//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import SpeziOnboarding
public import SpeziViews
public import SwiftUI


/// Onboarding view to display markdown-based consent documents that can be signed and exported.
///
/// The ``OnboardingConsentView`` embeds a ``ConsentDocumentView`` into an `OnboardingView` that is compatible with SpeziOnboarding's Onboarding Stack API.
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
    
    public var body: some View {
        OnboardingView {
            if let title {
                OnboardingTitleView(title: title)
            }
        } content: {
            Group {
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
            }
            .padding(.bottom)
        } footer: {
            AsyncButton(state: $viewState) {
                try await action()
            } label: {
                Text("CONSENT_ACTION", bundle: .module)
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .processingOverlay(isProcessing: backButtonHidden)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!actionButtonsEnabled)
            .animation(.easeInOut(duration: 0.2), value: actionButtonsEnabled)
            .interactiveGlassEffect()
            .id("ActionButton")
        }
        .scrollDisabled(consentDocument?.isSigning == true)
        .navigationBarBackButtonHidden(backButtonHidden)
    }

    private var backButtonHidden: Bool {
        guard let consentDocument else {
            return false
        }
        return consentDocument.isExporting
    }

    private var actionButtonsEnabled: Bool {
        if let consentDocument {
            !consentDocument.isExporting && consentDocument.completionState == .complete
        } else {
            false
        }
    }
    
    
    /// Creates an `OnboardingConsentView` for a file-based consent document.
    ///
    /// - parameter consentDocument: The Consent Document.
    ///     Pass `nil` if your app is currently still loading the document, but already wishes to display a "loading in progress" version of the ``OnboardingConsentView``.
    /// - parameter title: The title of the view displayed at the top. Can be `nil`, meaning no title is displayed.
    /// - parameter currentDateInSignature: Whether the current date should be included in the consent form's signature fields.
    /// - parameter viewState: A binding that provides the `ViewState` the view should use.
    /// - parameter action: The action to perform when the user has completed the consent form and taps the Onboarding View's "Continue" button.
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
}


extension View {
    @ViewBuilder
    fileprivate func interactiveGlassEffect() -> some View {
        #if !os(visionOS)
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, *) {
            self.glassEffect(.regular.interactive())
        } else {
            self
        }
        #else
        self
        #endif
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
