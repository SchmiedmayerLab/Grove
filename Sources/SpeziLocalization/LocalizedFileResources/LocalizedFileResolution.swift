//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Algorithms
public import Foundation
private import SpeziFoundation


/// Namespace for Localized File Resolution operations
public enum LocalizedFileResolution {
    private static let logger = Logger(subsystem: "edu.stanford.spezi", category: "SpeziLocalization")
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizedFileResolution {
    private struct ScoredCandidate: Hashable, Comparable, Sendable {
        let fileResource: LocalizedFileResource.Resolved
        let score: Double
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.score < rhs.score
        }
    }
    
    /// Resolves a localized resource from a set of inputs, based on an unlocalizdd filename and a target locale.
    ///
    /// Use this function to match a ``LocalizedFileResource`` against a list of candidate `URL`s representing localized files,
    /// determining which `URL` is the "closest" match w.r.t. the file resource.
    ///
    /// If no matching localized candidate exists, but there is a non-localized candidate whose name matches the `resource`, that candidate is returned, unless the `localeMatchingBehaviour` is set to ``LocaleMatchingBehaviour/requirePerfectMatch``.
    ///
    /// Example:
    /// ```swift
    /// let urls = [
    ///     "/news/Welcome+en-US.md",
    ///     "/news/Welcome+es-US.md",
    ///     "/news/Welcome+en-UK.md",
    ///     "/news/Welcome+de-DE.md"
    /// ].map { URL(filePath: $0) }
    /// // Since no explicit locale is specified, the file resource will get resolved using the current locale,
    /// // and, assuming you're in the US and your device is english, "/news/Welcome+en-US.md" will be returned.
    /// let _ = resolve(LocalizedFileResource("Welcome.md"), from: urls)
    /// // We explicitly specify the "es" locale; this will cause `resolve` to return "/news/Welcomd+es-US.md",
    /// // since that's the closest match.
    /// // If we had a "/news/Welcome+es-ES.md" file, that'd get returned instead.
    /// let _ = resolve(LocalizedFileResource("Welcome.md", locale: .init(identifier: "es-ES")), from: urls)
    /// // In this case, the file resolution will return "/news/Welcome+en-US.md";
    /// // none of the files match the input locale (neither w.r.t. the language, nor w.r.t. the region),
    /// // and the "en-US" locale is the `resolve` function's implicit fallback.
    /// let _ = resolve(LocalizedFileResource("Welcome.md", locale: .init(identifier: "fr-FR")), from: urls)
    /// ```
    ///
    /// - parameter resource: The file resource that should be resolved.
    /// - parameter candidates: List of file `URL`s against which `resource` should be resolved.
    /// - parameter localeMatchingBehaviour: The ``LocaleMatchingBehaviour`` that should be used when resolving the file resource.
    /// - parameter fallbackLocale: An optional fallback locale, used in case no match exists for the `resource`'s locale.
    ///     Ignored if `localeMatchingBehaviour` is ``LocaleMatchingBehaviour/requirePerfectMatch``.
    public static func resolve( // swiftlint:disable:this function_body_length
        _ resource: LocalizedFileResource,
        from candidates: some Collection<URL>,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallback fallbackLocale: LocalizationKey? = .enUS
    ) -> LocalizedFileResource.Resolved? {
        let languages: [Locale.Language] = {
            var langs = Bundle.main.preferredLocalizations(from: [resource.locale.language])
            if !langs.contains(resource.locale.language) {
                langs.insert(resource.locale.language, at: 0)
            }
            if let fallbackLocale, !localeMatchingBehaviour.isRequirePerfectMatch {
                langs.append(fallbackLocale.language.withRegion(fallbackLocale.region))
            }
            return langs
        }()
        var canReturnUnlocalizedMatch = !localeMatchingBehaviour.isRequirePerfectMatch
        for language in languages {
            let candidates: [ScoredCandidate] = candidates
                .lazy
                .compactMap { LocalizedFileResource.Resolved(resource: resource, url: $0) }
                .filter { $0.url.matches(unlocalizedFilename: resource.name) }
                .map { ScoredCandidate(fileResource: $0, score: $0.localization.score(against: language, using: localeMatchingBehaviour)) }
                .sorted(by: >)
            guard let candidate = candidates.first, candidate.score > 0.5 else {
                Self.logger.error(
                    "Unable to find url for \(resource.name) and language \(language.minimalIdentifier)."
                )
                if candidates.isEmpty {
                    Self.logger.error("No candidates")
                } else {
                    canReturnUnlocalizedMatch = false
                    Self.logger.error("Candidates:")
                    for candidate in candidates {
                        Self.logger.error("- \(candidate.score) @ \(candidate.fileResource.fullFilenameIncludingLocalization)")
                    }
                }
                continue
            }
            if let equallyBestRanked = candidates.lazy.chunked(by: { $0.score == $1.score }).first, !equallyBestRanked.isEmpty { // always true
                guard equallyBestRanked.count == 1 else {
                    var errorMsg = "Found multiple candidates for \(resource.name) @ \(language.minimalIdentifier), all of which are equally ranked!"
                    for candidate in candidates {
                        errorMsg.append("\n- \(candidate.score) @ \(candidate.fileResource.fullFilenameIncludingLocalization)")
                    }
                    Self.logger.error("\(errorMsg)")
                    canReturnUnlocalizedMatch = false
                    continue
                }
            }
            return candidate.fileResource
        }
        // if we weren't able to find anything above, see if we can fall back to an unlocalized version of the requested resource.
        if canReturnUnlocalizedMatch,
           case let unlocalizedCandidates = candidates.filter({ $0.matches(unlocalizedFilename: resource.name) }),
           let candidate = unlocalizedCandidates.first,
           unlocalizedCandidates.count == 1 {
            return LocalizedFileResource.Resolved(unlocalized: resource, url: candidate)
        }
        return nil
    }
    
    
    /// Selects all candidates that might match `resource`, ignoring the specified locale.
    public static func selectCandidatesIgnoringLocalization(
        matching resource: LocalizedFileResource,
        from candidates: some Collection<URL>
    ) -> [LocalizedFileResource.Resolved] {
        candidates.lazy
            .compactMap { LocalizedFileResource.Resolved(resource: resource, url: $0) }
            .filter { $0.url.matches(unlocalizedFilename: resource.name) }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizedFileResolution {
    /// Extract's information about a localized file.
    ///
    /// - parameter url: The `URL` of a localized file (e.g., `/Users/spezi/Documents/Welcome+en-US.md`).
    /// - returns: If `URL` contains localization info compatible with SpeziLocalization: the `URL`, with its localization into stripped, and the extracted localization info; otherwise `nil`.
    public static func parse(_ url: URL) -> (unlocalizedUrl: URL, localization: LocalizationKey)? {
        guard let components = url.lastPathComponent.parseLocalizationComponents(),
              let fileExtension = components.fileExtension,
              let localization = LocalizationKey(components.rawLocalization) else {
            return nil
        }
        let strippedUrl = url.deletingLastPathComponent().appending(component: components.baseName).appendingPathExtension(fileExtension)
        return (strippedUrl, localization)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension URL {
    fileprivate func matches(unlocalizedFilename: String) -> Bool {
        self.strippingLocalizationSuffix().pathComponents.ends(with: unlocalizedFilename.split(separator: "/"), by: ==)
    }
    
    /// Returns a copy of the URL, with a potential loalization suffix removed.
    func strippingLocalizationSuffix() -> URL {
        guard let components = self.lastPathComponent.parseLocalizationComponents() else {
            return self
        }
        var newUrl = self.deletingLastPathComponent().appending(component: components.baseName)
        if let fileExtension = components.fileExtension {
            newUrl.appendPathExtension(fileExtension)
        }
        return newUrl
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Locale.Language {
    /// Constructs a new `Language`, by updating the receiver's region.
    public func withRegion(_ region: Locale.Region?) -> Self {
        var components = Locale.Language.Components(identifier: self.maximalIdentifier)
        components.region = region
        return .init(components: components)
    }
}


extension StringProtocol {
    func parseLocalizationComponents() -> (baseName: String, fileExtension: String?, rawLocalization: String)? {
        // swiftlint:disable:previous large_tuple
        guard let separatorIdx = self.lastIndex(of: "+") else {
            return nil
        }
        var filename = self[...]
        let baseName = String(filename[..<separatorIdx])
        filename.removeFirst(baseName.count + 1)
        guard let fileExtIdx = filename.firstIndex(of: ".") else {
            return (baseName, nil, String(filename))
        }
        let rawLocalization = String(filename[..<fileExtIdx])
        filename.removeFirst(rawLocalization.count + 1)
        let fileExtension = String(filename)
        return (baseName, fileExtension, rawLocalization)
    }
}
