//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// The languages the questionnaire's text is offered in: the base ``Metadata/language`` first, then every
    /// translation language, sorted.
    public var languages: [String] {
        (metadata.language.map { [$0] } ?? []) + translationLanguages
    }

    /// A translation language no text may use: the base language, or one a text already translates into,
    /// compared case-insensitively.
    package var conflictingTranslationLanguage: String? {
        let base = metadata.language?.lowercased()
        for text in localizedTexts {
            var seen: Set<String> = base.map { [$0] } ?? []
            for language in text.translations.keys where !seen.insert(language.lowercased()).inserted {
                return language
            }
        }
        return nil
    }

    /// Every translation language, sorted, leaving out the base language.
    private var translationLanguages: [String] {
        var seen: Set<String> = metadata.language.map { [$0.lowercased()] } ?? []
        var languages: [String] = []
        for text in localizedTexts {
            for language in text.translations.keys where seen.insert(language.lowercased()).inserted {
                languages.append(language)
            }
        }
        return languages.sorted()
    }

    private var localizedTexts: [LocalizedText] {
        [metadata.title, metadata.explainer] + (metadata.purpose.map { [$0] } ?? [])
            + sections.flatMap { section in
                [section.title] + (section.shortTitle.map { [$0] } ?? []) + section.tasks.flatMap(\.localizedTexts)
            }
    }

    /// The offered language to render the questionnaire in for `locale`.
    ///
    /// An exact tag match wins (`es-US`), then a language sharing the locale's primary language (`es`),
    /// then the base language. Resolve every text in the result with ``LocalizedText/resolved(in:)``;
    /// `nil` means the base language is unknown and nothing else matched, so the base strings render.
    public func renderingLanguage(for locale: Locale) -> String? {
        locale.renderingLanguage(base: metadata.language, translations: translationLanguages)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task {
    fileprivate var localizedTexts: [Questionnaire.LocalizedText] {
        var texts = [title, subtitle, footer]
        texts += [markdownText, prefix, shortTitle, media?.altText].compactMap(\.self)
        texts += constraints.map(\.humanDescription)
        texts += groupPath.flatMap { [$0.title] + ($0.shortTitle.map { [$0] } ?? []) }
        switch kind.variant {
        case .instructional(let text):
            texts.append(text)
        case .choice(let config):
            texts += config.options.flatMap { [$0.title, $0.subtitle] }
            texts += config.freeTextOtherOptionLabel.map { [$0] } ?? []
            texts += config.followUpTasks.flatMap(\.localizedTexts)
        case .numeric(let config):
            texts.append(config.unit)
            texts += config.unitOptions.map(\.display)
        case .custom(_, let config):
            texts += config.followUpTasks.flatMap(\.localizedTexts)
        case .boolean, .freeText, .dateTime, .fileAttachment:
            break
        }
        return texts
    }
}
