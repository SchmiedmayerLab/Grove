//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveConsent
import SwiftUI


struct ConsentFooterTestView: View {
    @State private var markdownDocument = try? ConsentDocument(markdown: "A document with only Markdown.")
    @State private var interactiveDocument = try? ConsentDocument(markdown: """
        <toggle id=agree initial-value=true>I agree</toggle>

        Thank you for reading.
        """)
    @State private var activations = 0

    var body: some View {
        ScrollView {
            VStack {
                if let markdownDocument {
                    ConsentDocumentView(consentDocument: markdownDocument) {
                        Button("Markdown Footer") {
                            activations += 1
                        }
                    }
                }
                if let interactiveDocument {
                    ConsentDocumentView(consentDocument: interactiveDocument) {
                        Button("Trailing Markdown Footer") {
                            activations += 1
                        }
                    }
                }
                Text("Footer activations: \(activations)")
            }
            .padding()
        }
    }
}
