//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct DismissKeyboardTest: View {
    var body: some View {
        Form {
            SubView("Continue", label: .continue)
            SubView("Done", label: .done)
            SubView("Go", label: .go)
            SubView("Join", label: .join)
            SubView("Next", label: .next)
            SubView("Return", label: .return)
            SubView("Route", label: .route)
            SubView("Search", label: .search)
            SubView("Send", label: .send)
            NumberEntry()
                .accessibilityLabel("Number Entry")
        }
    }
}


extension DismissKeyboardTest {
    private struct SubView: View {
        @State var text = ""
        var submitLabel: SubmitLabel
        var label: String

        var body: some View {
            TextField(text: $text, prompt: Text(label)) {
                Text(label)
            }
            .submitLabel(submitLabel)
        }

        init(_ label: String, label submitLabel: SubmitLabel) {
            self.submitLabel = submitLabel
            self.label = label
        }
    }
    
    
    private struct NumberEntry: View {
        // Note: using a NumberFormatter() instead of the new `FloatingPointFormatStyle<Double>.number` API,
        // because of https://github.com/swiftlang/swift-foundation/issues/135
        @State private var formatter = NumberFormatter()
        
        @State private var value: Double?
        
        var body: some View {
            TextField("Number Entry", value: $value, formatter: formatter, prompt: Text(verbatim: "0"))
                .keyboardType(.numberPad)
        }
    }
}


#if DEBUG
#Preview {
    DismissKeyboardTest()
}
#endif
