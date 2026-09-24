//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import FHIRModelsExtensions
public import Foundation
import GroveFoundation
import GroveLocalization
public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// One per-locale file of a questionnaire.
    struct LocalizedQuestionnaire {
        let questionnaire: Questionnaire
        let localization: LocalizationKey
        let url: URL

        /// The language the file is written in: its own `language`, else its filename's localization.
        var language: String {
            questionnaire.language?.value?.string ?? localization.description
        }
    }

    /// The file the others are compared against and merged into: `en-US`, else English, else the first.
    static func base(of files: [LocalizedQuestionnaire]) -> LocalizedQuestionnaire? {
        files.first { $0.questionnaire.language == "en-US" || $0.localization == .enUS }
            ?? files.first { $0.questionnaire.language == "en" || $0.localization.language.isEquivalent(to: .init(identifier: "en")) }
            ?? files.first
    }

    /// The base file, carrying every other file's text as translations.
    ///
    /// The files must differ in presentation text alone, which the bundle's validation guarantees; data that differs keeps
    /// its base value.
    private static func merged(_ files: [LocalizedQuestionnaire]) throws -> LocalizedQuestionnaire? {
        guard let base = base(of: files) else {
            return nil
        }
        var questionnaire = base.questionnaire
        questionnaire.language = FHIRPrimitive(FHIRString(base.language))
        for file in files where file.url != base.url {
            let conflicts = try questionnaire.addTranslations(from: file.questionnaire, in: file.language)
            if !conflicts.isEmpty {
                logger.error("\(file.url.lastPathComponent) differs from its base in data at \(conflicts.map(\.path.description))")
            }
        }
        return LocalizedQuestionnaire(questionnaire: questionnaire, localization: base.localization, url: base.url)
    }

    /// Loads a questionnaire resource from a ``FileReference``.
    ///
    /// A questionnaire is one multilingual resource: its per-locale files are merged into the base file,
    /// the `en-US` one where it exists, with every other file's text added as `translation` extensions.
    /// A renderer then picks the language to show.
    public func questionnaire(for fileRef: FileReference) -> Questionnaire? {
        do {
            return try Self.merged(try localizedQuestionnaires(for: fileRef))?.questionnaire
        } catch {
            Self.logger.error("Unable to load questionnaire '\(fileRef)': \(error)")
            return nil
        }
    }

    /// Loads the questionnaire resource with the specified filename.
    public func questionnaire(named questionnaireName: String) -> Questionnaire? {
        questionnaire(for: .init(category: .questionnaire, filename: questionnaireName, fileExtension: "json"))
    }

    /// The questionnaires study components reference, and every other questionnaire the bundle includes.
    func questionnaireFileRefs() -> [FileReference] {
        var fileRefs: Set<FileReference> = studyDefinition.components.compactMapIntoSet {
            switch $0 {
            case .questionnaire(let component):
                component.fileRef
            default:
                nil
            }
        }
        let questionnairesUrl = Self
            .folderUrl(for: .questionnaire, relativeTo: bundleUrl)
            .resolvingSymlinksInPath()
            .absoluteURL
        let urls = FileManager.default.enumerator(at: questionnairesUrl, includingPropertiesForKeys: nil)?
            .compactMap { (($0 as? NSURL)?.path).map { URL(filePath: $0) } } ?? []
        for url in urls {
            guard let unlocalizedUrl = LocalizedFileResolution.parse(url.absoluteURL)?.unlocalizedUrl.standardized,
                  unlocalizedUrl.pathExtension == "json" else {
                continue
            }
            // -resolvingSymlinksInPath needs a URL to an existing file system object, so the containing folder is
            // normalized and the filename re-added.
            let pathComponents = unlocalizedUrl
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .appending(component: unlocalizedUrl.deletingPathExtension().lastPathComponent)
                .pathComponents
            fileRefs.insert(.init(
                category: .questionnaire,
                filename: pathComponents.dropFirst(questionnairesUrl.pathComponents.count).joined(separator: "/"),
                fileExtension: "json"
            ))
        }
        return fileRefs.sorted(using: [KeyPathComparator(\.category.rawValue), KeyPathComparator(\.filename)])
    }

    /// Every per-locale file of the questionnaire, in no particular order.
    func localizedQuestionnaires(for fileRef: FileReference) throws -> [LocalizedQuestionnaire] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.folderUrl(for: fileRef.category, relativeTo: bundleUrl),
            includingPropertiesForKeys: nil
        )) ?? []
        return try LocalizedFileResolution
            .selectCandidatesIgnoringLocalization(matching: LocalizedFileResource(fileRef), from: urls)
            .map { candidate in
                LocalizedQuestionnaire(
                    questionnaire: try JSONDecoder().decode(Questionnaire.self, from: Data(contentsOf: candidate.url)),
                    localization: candidate.localization,
                    url: candidate.url
                )
            }
    }

    /// Rewrites every questionnaire as one multilingual file in its base file's place, removing the other per-locale files.
    func mergeQuestionnaires() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for fileRef in questionnaireFileRefs() {
            let files = try localizedQuestionnaires(for: fileRef)
            guard files.count > 1, let merged = try Self.merged(files) else {
                continue
            }
            try encoder.encode(merged.questionnaire).write(to: merged.url)
            for file in files where file.url != merged.url {
                try FileManager.default.removeItem(at: file.url)
            }
        }
    }
}


extension ModelsR4.Questionnaire {
    /// A string of the questionnaire in the language it renders in for `locale`: an exact tag match, then the
    /// locale's primary language, then the base language.
    @available(iOS 18, macOS 15, watchOS 11, *)
    func rendered(_ keyPath: KeyPath<Self, FHIRPrimitive<FHIRString>?>, for locale: Locale) -> String? {
        guard let string = self[keyPath: keyPath] else {
            return nil
        }
        let translations = string.translations
        let language = locale.renderingLanguage(base: language?.value?.string, translations: translations.keys.sorted())
        return language.flatMap { translations[$0] } ?? string.value?.string
    }
}
