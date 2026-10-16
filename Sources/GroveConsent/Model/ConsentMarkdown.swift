//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// `AttributedString(markdown:)` is only available in the Apple platforms' Foundation.
#if canImport(Darwin)
import Foundation


/// The textual Markdown supported by both the consent view and its portable PDF copy.
/// No remote content is fetched as a side effect of parsing or exporting consent.
@available(iOS 18, macOS 15, watchOS 11, *)
enum ConsentMarkdown {
    enum ValidationError: Error {
        case externalImage
        case rawHTML
        case unsafeLink
    }

    static func parse(_ text: String) throws -> AttributedString {
        let parsed = try AttributedString(markdown: text, options: .init(failurePolicy: .throwError))
        for run in parsed.runs {
            guard run.imageURL == nil else { throw ValidationError.externalImage }
            let intent = run.inlinePresentationIntent ?? []
            guard !intent.contains(.inlineHTML), !intent.contains(.blockHTML) else { throw ValidationError.rawHTML }
            if let link = run.link {
                guard let scheme = link.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else {
                    throw ValidationError.unsafeLink
                }
            }
        }
        return parsed
    }
}
#endif
