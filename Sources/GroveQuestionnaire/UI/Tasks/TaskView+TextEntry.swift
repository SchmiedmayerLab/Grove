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
        let config: Questionnaire.Task.Kind.FreeTextConfig
        @Binding var response: String
        
        var body: some View {
            TextEditor(text: $response)
                .frame(minHeight: 100, maxHeight: 372) // starts to scroll once max height is reached
                #if os(iOS)
                .textInputAutocapitalization(config.disableAutocorrection ? .never : nil)
                #endif
                .autocorrectionDisabled(config.disableAutocorrection)
                .enableDismissalViaKeyboardAccessory()
        }
    }
}
