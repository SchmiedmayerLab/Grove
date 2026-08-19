//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI


/// The FHIR resource behind a page, as it would go over the wire.
struct FHIRSourceView: View {
    let title: String
    let json: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(json)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("FHIRSource")
    }
}


extension Encodable {
    /// The resource as pretty-printed JSON, or the reason it could not be encoded.
    var prettyPrintedJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        do {
            return String(decoding: try encoder.encode(self), as: UTF8.self)
        } catch {
            return "Could not encode this resource:\n\(error)"
        }
    }
}
