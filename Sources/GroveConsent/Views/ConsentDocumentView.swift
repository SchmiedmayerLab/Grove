//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import GroveFoundation
private import GrovePersonalInfo
private import GroveViews
private import MarkdownUI
private import PencilKit
public import SwiftUI

/// Display a markdown-based ``ConsentDocument`` that can be filled out, signed, and exported.
///
/// ![A consent document with a toggle and a choice on cards.](InteractiveElements)
///
/// Allows the display markdown-based consent documents that can be signed using a family and given name and a hand drawn signature.
///
/// Your app creates a ``ConsentDocument``, which acts as the model representing a markdown-based consent form.
/// This view displays the ``ConsentDocument``, and enables data entry into the document's interactive components, such as e.g. checkboxes, selection pickers, and signature fields.
///
/// - Important: A `ConsentDocumentView` should always be placed in a `ScrollView`.
///     Otherwise, the `ConsentDocumentView`'s contents will easily overflow the available screen space.
///     If you use a ``OnboardingConsentView``, the `ScrollView` is taken care of for you.
///
/// > Note: In the context of user onboarding, you might want to use the ``OnboardingConsentView`` instead.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ConsentDocumentView<Footer: View>: View {
    @Bindable private var consentDocument: ConsentDocument
    private let signatureFieldLabels: ConsentSignatureForm.Labels
    private let signatureDate: Date?
    private let signatureDateFormat: Date.FormatStyle
    private let footer: Footer
    
    public var body: some View {
        MarkdownView(
            document: consentDocument.markdownDocument,
            dividerRule: .never
        ) { blockIdx, _ in
            let section = consentDocument.sections[blockIdx]
            if section.isSignature && blockIdx == consentDocument.sections.endIndex - 1 {
                // A short document keeps its name and signature at the bottom rather than mid-page.
                Spacer(minLength: 24)
            }
            view(for: section)
            if blockIdx == consentDocument.sections.endIndex - 1 {
                footer
            }
        }
    }
    
    /// Creates a `ConsentDocumentView`, which renders a consent document with a markdown view.
    ///
    /// - parameter consentDocument: The consent document the view should display and edit.
    /// - parameter signatureFieldLabels: Allows customizing which text should be used for labels in signature fields within this ``ConsentDocumentView``.
    /// - parameter consentSignatureDate: The date that should be used for the signature.
    /// - parameter consentSignatureDateFormat: The `Date.FormatStyle` that should be used when rendering `consentSignatureDate`.
    /// - parameter footer: Actions that belong to the form, laid out after its last element so a short document keeps them at the bottom together with the signature.
    public init(
        consentDocument: ConsentDocument,
        signatureFieldLabels: ConsentSignatureForm.Labels = .init(),
        consentSignatureDate: Date? = nil,
        consentSignatureDateFormat: Date.FormatStyle = .init(date: .numeric),
        @ViewBuilder footer: () -> Footer
    ) {
        self.consentDocument = consentDocument
        consentDocument.signatureDate = consentSignatureDate?.formatted(consentSignatureDateFormat)
        self.signatureFieldLabels = signatureFieldLabels
        self.signatureDate = consentSignatureDate
        self.signatureDateFormat = consentSignatureDateFormat
        self.footer = footer()
    }

    /// Creates a `ConsentDocumentView` without actions of its own.
    ///
    /// - parameter consentDocument: The consent document the view should display and edit.
    /// - parameter signatureFieldLabels: Allows customizing which text should be used for labels in signature fields within this ``ConsentDocumentView``.
    /// - parameter consentSignatureDate: The date that should be used for the signature.
    /// - parameter consentSignatureDateFormat: The `Date.FormatStyle` that should be used when rendering `consentSignatureDate`.
    public init(
        consentDocument: ConsentDocument,
        signatureFieldLabels: ConsentSignatureForm.Labels = .init(),
        consentSignatureDate: Date? = nil,
        consentSignatureDateFormat: Date.FormatStyle = .init(date: .numeric)
    ) where Footer == EmptyView {
        self.init(
            consentDocument: consentDocument,
            signatureFieldLabels: signatureFieldLabels,
            consentSignatureDate: consentSignatureDate,
            consentSignatureDateFormat: consentSignatureDateFormat
        ) {
            EmptyView()
        }
    }
    
    
    @ViewBuilder
    private func view(for section: ConsentDocument.Section) -> some View {
        switch section {
        case .markdown:
            let _ = preconditionFailure("unreachable") // swiftlint:disable:this redundant_discardable_let
        case .toggle(let config):
            let valueBinding = consentDocument.binding(for: config)
            Toggle(isOn: valueBinding) {
                InteractiveElementLabel(text: config.text)
            }
            .accessibilityIdentifier(for: config)
            .interactiveCard(isBlocking: isBlocking(config), message: Text("CONSENT_TOGGLE_REQUIRED", bundle: .module))
            .id(config.id)
            // Goal: we want a Toggle that can be toggled by tapping anywhere in its frame.
            // Issue: using only `.onTapGesture` doesn't quite work, since that'll only trigger for touches that are in the
            //     left part of the view, where the Toggle's text is, but not for eg above/below the Toggle, if the text is significantly taller
            //     than the Toggle itself.
            // Solution: this combination of using both `.onTapGesture` directly on the view and adding a custom clear background with a
            //     tap gesture of its own covers both scenarios. (Having only the background tap gesture, without the one directly on the view
            //     doesn't work, since that'll only trigger for interactions with the region above/below the Toggle, but not for taps in the text area.)
            // Alternative: We could also have placed the Toggle in a ZStack, and added a clear layer with a tap gesture on top of the Toggle,
            //     but that wouldn't let any touch events through to the toggle, meaning that you can't e.g. drag it via a long touch interaction.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        valueBinding.wrappedValue.toggle()
                    }
            }
            .onTapGesture {
                valueBinding.wrappedValue.toggle()
            }
        case .select(let config):
            CustomPicker(
                config: config,
                selection: consentDocument.binding(for: config)
            )
            .interactiveCard(isBlocking: isBlocking(config), message: Text("CONSENT_SELECTION_REQUIRED", bundle: .module))
            .id(config.id)
        case .signature(let config):
            ConsentSignatureForm(
                labels: signatureFieldLabels,
                storage: consentDocument.binding(for: config),
                isSigning: $consentDocument.isSigning,
                signatureDate: signatureDate,
                signatureDateFormat: signatureDateFormat
            )
            .accessibilityIdentifier(for: config)
            .interactiveCard(isBlocking: isBlocking(config), message: Text("CONSENT_SIGNATURE_REQUIRED", bundle: .module))
            .id(config.id)
        }
    }

    /// Whether the element is marked as one that still keeps the document from being complete.
    private func isBlocking(_ section: some ConsentDocument.InteractiveSectionProtocol) -> Bool {
        consentDocument.highlightsIncompleteSections && !section.valueMatchesExpected(consentDocument.value(for: section))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocumentView {
    private struct CustomPicker: View {
        let config: ConsentDocument.SelectConfig
        @Binding var selection: String
        
        var body: some View {
            HStack {
                InteractiveElementLabel(text: config.text)
                Spacer()
                Picker("" as String, selection: $selection) {
                    Text(ConsentDocument.SelectConfig.emptySelectionDefaultTitle)
                        .tag(ConsentDocument.SelectConfig.emptySelection)
                    ForEach(config.options, id: \.self) { option in
                        Text(option.title)
                            .foregroundStyle(.primary)
                            .tag(option.id)
                    }
                }
                .accessibilityIdentifier(for: config)
                .pickerStyle(.menu)
                // Bordered, so the choice reads as a control to tap rather than as a line of tinted text.
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(tintColor)
            }
        }
        
        /// Dark enough to stand out on its card; red while a required choice is still missing.
        private var tintColor: Color {
            switch config.expectedSelection {
            case .anything(allowEmptySelection: true):
                .primary
            case .option, .anything(allowEmptySelection: false):
                selection == ConsentDocument.SelectConfig.emptySelection ? .red : .primary
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocumentView {
    private struct InteractiveElementLabel: View {
        let text: MarkdownDocument
        
        var body: some View {
            MarkdownView(document: text, dividerRule: .never) { _, element in
                switch element.name {
                case "footnote":
                    let plainText = String(element.content.plainTextContents.trimmingWhitespaceInLines())
                    HStack {
                        if let attrString = try? AttributedString(
                            markdown: plainText,
                            options: .init(interpretedSyntax: .inlineOnly, failurePolicy: .returnPartiallyParsedIfPossible)
                        ) {
                            Text(attrString)
                        } else {
                            Text(plainText)
                        }
                        Spacer()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    fileprivate func accessibilityIdentifier(for section: some ConsentDocument.InteractiveSectionProtocol) -> some View {
        self.accessibilityIdentifier("ConsentForm:\(section.id)")
    }

    /// Everything that asks for an answer sits on the same card, so a reader scrolling past can tell it from the text;
    /// a card that still blocks the form says so underneath, the way a questionnaire's question does.
    fileprivate func interactiveCard(isBlocking: Bool, message: Text) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            self
            if isBlocking {
                BlockingMessage(message)
            }
        }
            .padding(12)
            .background(.fill.quaternary, in: shape)
            .blockingHighlight(isBlocking, in: shape)
            .padding(.vertical, 4)
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    let consentDocument = try! ConsentDocument(markdown: "This is a *markdown* **example**") // swiftlint:disable:this force_try
    NavigationStack {
        ConsentDocumentView(consentDocument: consentDocument)
            .navigationTitle(Text(verbatim: "Consent"))
            .padding()
    }
}
#endif
