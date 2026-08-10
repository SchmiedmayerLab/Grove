//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}


/// Locale information used to localize files, and to resolve them.
///
/// A Localization Key consists of a ``language`` and a ``region``.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(language:region:)``
/// - ``init(locale:)``
/// - ``init(parsingFilename:)``
/// - ``init(_:)``
///
/// ### Properties
/// - ``language``
/// - ``region``
/// - ``description``
///
/// ### Instance Methods
/// - ``score(against:using:)-(Locale,_)``
/// - ``score(against:using:)-(Locale.Language,_)``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LocalizationKey: Sendable {
    /// The `en-US` localization key
    public static let enUS = Self(language: .init(identifier: "en"), region: .unitedStates)

    /// The localization key's language
    public let language: Locale.Language
    /// The localization key's region
    public let region: Locale.Region

    /// Creates a new Localization Key
    public init(language: Locale.Language, region: Locale.Region) {
        self.language = language
        self.region = region
    }

    /// Creates a new Localization Key, from a `Locale`
    ///
    /// This initializer fails if the locale's region is nil. This will happen if you use e.g. `Locale(identifier: "fr")` instead of `Locale(identifier: "fr-FR")`.
    public init?(locale: Locale) {
        guard let region = locale.region else {
            // this should be exceedingly unlikely to happen: https://stackoverflow.com/a/74563008
            return nil
        }
        // we need to reset the region that's embedded in the language (if any), bc we otherwise have that twice.
        self.init(language: locale.language.withRegion(nil), region: region)
    }

    /// Creates a new Localization Key by extracting a localization suffix from a filename
    public init?(parsingFilename filename: String) {
        guard let components = filename.parseLocalizationComponents(),
              let localization = LocalizationKey(components.rawLocalization) else {
            return nil
        }
        self = localization
    }

    /// Match a Localization Key against a Locale.
    ///
    /// Determines how well the LocalizationKey matches the Locale, on a scale from 0 to 1.
    public func score(against locale: Locale, using localeMatchingBehaviour: LocaleMatchingBehaviour = .default) -> Double {
        score(
            against: locale.language.withRegion(locale.language.region ?? locale.region),
            using: localeMatchingBehaviour
        )
    }

    /// Match a Localization Key against a Language.
    ///
    /// Determines how well the `LocalizationKey` matches the `Language`, on a scale from 0 to 1.
    public func score( // swiftlint:disable:this cyclomatic_complexity
        against other: Locale.Language,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default
    ) -> Double {
        let languageMatches = if let selfCode = self.language.languageCode, let otherCode = other.languageCode {
            selfCode.identifier == otherCode.identifier
        } else {
            self.language.minimalIdentifier == other.minimalIdentifier
        }
        guard let otherRegion = other.region else {
            // we only can look at the language
            switch localeMatchingBehaviour {
            case .requirePerfectMatch:
                // we return 0.9 here so that if some other language has a region, and is compared against the same key (using the same matching behaviour),
                // and the other region matches, it compares higher
                return languageMatches ? 0.9 : 0
            case .preferLanguageMatch, .preferRegionMatch:
                return languageMatches ? 0.8 : 0
            case .custom:
                // can't run the check here bc we're missing the region for the language
                // maybe figure smth out here?
                return 0
            }
        }
        // IDEA: maybe also allow matching against parent regions?
        // (eg: if the user is in Canada, but the region in the key is just north america in general, that should still match...)
        let regionMatches = otherRegion.identifier == self.region.identifier
        guard !(languageMatches && regionMatches) else { // perfect match
            return 1
        }
        switch localeMatchingBehaviour {
        case .requirePerfectMatch:
            return 0 // we've already checked for a perfect match above...
        case .preferLanguageMatch:
            return languageMatches ? 0.8 : regionMatches ? 0.75 : 0
        case .preferRegionMatch:
            return regionMatches ? 0.8 : languageMatches ? 0.75 : 0
        case .custom(let imp):
            guard let region = other.region else {
                return 0
            }
            let key = LocalizationKey(language: other, region: region)
            return imp(self, key)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationKey: Hashable {
    public static func == (lhs: LocalizationKey, rhs: LocalizationKey) -> Bool {
        lhs.region == rhs.region && lhs.language.isEquivalent(to: rhs.language)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(region)
        // we implement equality based on `Locale.Language.isEquivalent(to:)`, which internally compares the
        // two languages' maximalIdentifier, so we also need to use that to build up our hash value.
        hasher.combine(language.maximalIdentifier)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationKey: LosslessStringConvertible {
    public var description: String {
        language.minimalIdentifier + "-" + region.identifier
    }

    /// Attempts to create a Localization Key, by parsing the input.
    public init?(_ description: String) {
        self.init(locale: .init(identifier: description))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationKey: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let key = LocalizationKey(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid localization key: \(string)")
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationKey: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        AnyCodingKey(stringValue: description)
    }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(codingKey.stringValue)
    }
}
