//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct CompletionPage: View {
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource?
    private let action: @MainActor () async throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // periphery:ignore - read through its projected value by viewStateAlert(state:)
    @State private var viewState: ViewState = .idle
    @State private var handOffFailed = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Nothing scrolls here, so the button simply ends the stack.
            doneButton
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The same inset the questions were answered at, so the page the participant lands on
        // is the page they have been on all along, one screen further.
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .makeBackgroundMatchFormBackground()
        .viewStateAlert(state: $viewState)
        #if os(iOS)
        // The page carries no title, and a bar that resizes as it arrives drags the content with
        // it — the questions behind it may have been under a large one.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Nothing is left to discard, so this button is the only way out — until it fails, and
        // then refusing to go back would strand the participant on a page that cannot proceed.
        .navigationBarBackButtonHidden(!handOffFailed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("GroveQuestionnaireCompletionPage")
    }

    private var doneButton: some View {
        AsyncButton(state: $viewState) {
            do {
                try await action()
            } catch {
                handOffFailed = true
                throw error
            }
        } label: {
            Text("Done", bundle: .module)
                .bold()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyleGlassProminent()
        .accessibilityIdentifier("PrimaryAction")
        .accessibilityValue(Text("Ready", bundle: .module))
    }

    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        action: @escaping @MainActor () async throws -> Void
    ) {
        self.title = title
        self.message = message
        self.action = action
    }
}
