//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveConsent
import GroveFoundation
import QuickLook
import SwiftUI


/// Local visual fixtures; exports deliberately remain unsigned and never represent accepted consent.
struct ConsentExampleView: View {
    let resource: String
    @State private var document: ConsentDocument?
    @State private var pdfURL: URL?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Unsigned example — not an accepted consent")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let document {
                    ConsentDocumentView(consentDocument: document)
                }
                if failed {
                    Text("The example could not be loaded or exported.")
                }
            }
            .padding()
        }
        .navigationTitle(document?.metadata.title ?? "Consent Example")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            Button("Show PDF") { export() }
                .disabled(document == nil)
        }
        .quickLookPreview($pdfURL)
        .task {
            do {
                guard let url = Bundle.main.url(forResource: resource, withExtension: "md") else {
                    failed = true
                    return
                }
                document = try ConsentDocument(contentsOf: url)
            } catch {
                failed = true
            }
        }
    }

    private func export() {
        guard let document else {
            return
        }
        do {
            let result = try document.export(using: .init(includingTimestamp: false))
            let directory = URL.documentsDirectory.appending(path: "ConsentExamples", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: resource + ".pdf")
            guard let data = result.pdf.dataRepresentation() else {
                failed = true
                return
            }
            try data.write(to: url, options: .atomic)
            pdfURL = url
        } catch {
            failed = true
        }
    }
}
