//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// Text shown to the participant: the base string, written in the questionnaire's ``Metadata/language``,
    /// and its translations into other languages.
    ///
    /// A string literal is a text without translations.
    ///
    /// ```swift
    /// let title: Questionnaire.LocalizedText = "How are you today?"
    /// let translated = Questionnaire.LocalizedText("How are you today?", translations: ["es": "¿Cómo está hoy?"])
    /// ```
    public struct LocalizedText: Hashable, Sendable {
        /// The text in the questionnaire's base language.
        public var base: String
        /// Translations of ``base``, keyed by BCP 47 language tag.
        public var translations: [String: String]

        /// Creates a text from its base string and its translations, keyed by BCP 47 language tag.
        public init(_ base: String, translations: [String: String] = [:]) {
            self.base = base
            self.translations = translations
        }

        /// The text as rendered in `language`: its translation into exactly that tag, or else the base string.
        ///
        /// Pass the language ``Questionnaire/renderingLanguage(for:)`` selects, so every text of a questionnaire
        /// renders in the same language; `nil` renders the base string.
        public func resolved(in language: String?) -> String {
            guard let language else {
                return base
            }
            return translations[language]
                ?? translations.first { $0.key.caseInsensitiveCompare(language) == .orderedSame }?.value
                ?? base
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.LocalizedText: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.LocalizedText {
    /// The texts joined per language, each language falling back to a text's base string where it has no translation.
    package static func joined(_ texts: [Self], separator: String) -> Self {
        let languages = Set(texts.flatMap(\.translations.keys))
        return Self(
            texts.map(\.base).joined(separator: separator),
            translations: Dictionary(uniqueKeysWithValues: languages.map { language in
                (language, texts.map { $0.resolved(in: language) }.joined(separator: separator))
            })
        )
    }
}
