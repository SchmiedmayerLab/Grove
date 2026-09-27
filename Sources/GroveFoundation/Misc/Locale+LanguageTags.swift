//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension Locale {
    /// The language to render a multilingual resource in, among its base language and its translation languages (BCP 47 tags).
    ///
    /// An exact tag match wins, then the first language sharing the locale's primary language (the base language first),
    /// then the base language.
    package func renderingLanguage(base: String?, translations: [String]) -> String? {
        let offered = (base.map { [$0] } ?? []) + translations
        var exactTags = [identifier(.bcp47)]
        if let code = language.languageCode?.identifier, let region = region?.identifier {
            exactTags.append("\(code)-\(region)")
        }
        for tag in exactTags {
            if let match = offered.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                return match
            }
        }
        if let code = language.languageCode?.identifier,
           let match = offered.first(where: { $0.primaryLanguageSubtag.caseInsensitiveCompare(code) == .orderedSame }) {
            return match
        }
        return base
    }
}


extension String {
    /// The primary language subtag of a BCP 47 language tag, e.g. `es` for `es-US`.
    fileprivate var primaryLanguageSubtag: Substring {
        prefix { $0 != "-" && $0 != "_" }
    }
}
