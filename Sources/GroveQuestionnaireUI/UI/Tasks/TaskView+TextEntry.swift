//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension TaskView {
    struct FreeTextEntry: View {
        let label: String
        let config: Questionnaire.Task.Kind.FreeTextConfig
        @Binding var response: String

        var body: some View {
            SwiftUI.Group {
                if config.isMultiline {
                    // A long answer is the same field as a short one, given room to grow: same
                    // card, same inset, same placeholder. Only the height differs.
                    TextEditor(text: $response)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 88, maxHeight: 372) // starts to scroll once max height is reached
                        .overlay(alignment: .topLeading) {
                            if response.isEmpty {
                                Text("Your answer", bundle: .module)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                } else {
                    TextField("", text: $response, prompt: Text("Your answer", bundle: .module))
                        .frame(minHeight: 44)
                }
            }
            #if os(iOS)
            .textInputAutocapitalization(config.disableAutocorrection ? .never : nil)
            .keyboardType(keyboardType)
            #endif
            .autocorrectionDisabled(config.disableAutocorrection)
            .accessibilityLabel(label)
            .enableDismissalViaKeyboardAccessory()
            .padding(.vertical, 8)
        }

        #if os(iOS)
        /// The keyboard suited to the expected entry (SDC `keyboard`).
        private var keyboardType: UIKeyboardType {
            switch config.keyboard {
            case .phone: .phonePad
            case .email: .emailAddress
            case .number: .decimalPad
            case .url: .URL
            case nil: .default
            }
        }
        #endif
    }
}
