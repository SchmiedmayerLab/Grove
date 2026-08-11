//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
#if os(macOS) || targetEnvironment(macCatalyst)
import HealthKit
#endif
@_spi(Testing) @testable import GroveLocalization
import Testing

// Suite is Skipped on Linux:
// localization methods are unavailable outside Apple platforms
#if canImport(Darwin)
@Suite
struct LocalizationTests {
    private let allSupportedLanguages: [Locale.Language] = [
        .en, .de, .es, .enGB, .esUS
    ]
    
    @Test
    @available(macOS 15.4, iOS 18.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *)
    func unsupportedLang() {
        let bundle = Bundle.module
        
        #expect(bundle.localizedString(forKey: "LOCALIZATION_LANG", value: nil, table: nil, localizations: [.en]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: "LOCALIZATION_LANG", tables: [.default], localizations: [.en]) == "en")
        #expect(bundle.localizedString(forKey: "LOCALIZATION_LANG", value: nil, table: nil, localizations: [.jp]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: "LOCALIZATION_LANG", tables: [.default], localizations: [.jp]) == "en")
    }
    
    
    @Test
    func preferredLocalizationsSimple() {
        let bundle = Bundle.module
        for lang in [Locale.Language.en, .de, .es] {
            #expect(bundle.preferredLocalizations(from: [lang]) == [lang])
        }
    }
    
    
    @Test
    func preferredLocalizationsSpecializations() {
        let bundle = Bundle.module
        let idents = { ($0 as [Locale.Language]).map(\.minimalIdentifier) }
        #expect(idents(bundle.preferredLocalizations(from: [.enGB])) == idents([.enGB, .en]))
        #expect(idents(bundle.preferredLocalizations(from: [.esUS])) == idents([.esUS, .es]))
        #expect(idents(bundle.preferredLocalizations(from: [.enGB, .en])) == idents([.enGB, .en]))
        #expect(idents(bundle.preferredLocalizations(from: [.en, .enGB])) == idents([.en]))
        #expect(idents(bundle.preferredLocalizations(from: [.fr], limitToPreferences: false)).starts(with: ["fr", "en", "en-GB", "de"]))
        #expect(idents(bundle.preferredLocalizations(from: [.fr, .es], limitToPreferences: false)).starts(with: ["fr", "es", "es-US", "en", "en-GB"]))
        #expect(idents(bundle.preferredLocalizations(from: [.de, .enGB], limitToPreferences: false)).starts(with: ["de", "en-GB", "en"]))
        #expect(idents(bundle.preferredLocalizations(from: [.de], limitToPreferences: false)).starts(with: ["de", "en", "en-GB"]))
    }
    
    
    @Test
    @available(macOS 15.4, iOS 18.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *)
    func bundleLocalizationUtils0() throws {
        let bundle = Bundle.module
        let key = "LOCALIZATION_LANG"
        for lang in allSupportedLanguages {
            let value1 = bundle.localizedString(forKey: key, value: "NOT_FOUND", table: nil, localizations: [lang])
            let value2 = bundle.localizedStringForKeyFallback(key: key, tables: [], localizations: [lang])
            #expect(value1 == value2, "lang: \(lang.minimalIdentifier)")
        }
    }
    
    
    @Test
    @available(macOS 15.4, iOS 18.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *)
    func bundleLocalizationUtils1() throws {
        let bundle = Bundle.module
        let key = "LOCALIZATION_LANG_2"
        
        #expect(bundle.localizedString(forKey: key, value: "nil", table: nil, localizations: [.enGB]) == "nil")
        #expect(bundle.localizedString(forKey: key, tables: [.default], localizations: [.enGB]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.enGB]) == "en")
        
        #expect(bundle.localizedString(forKey: key, value: "nil", table: nil, localizations: [.enGB, .en]) == "nil")
        #expect(bundle.localizedString(forKey: key, tables: [.default], localizations: [.enGB, .en]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.enGB, .en]) == "en")
        
        #expect(bundle.localizedString(forKey: key, value: "nil", table: nil, localizations: [.en, .enGB]) == "en")
        #expect(bundle.localizedString(forKey: key, tables: [.default], localizations: [.en, .enGB]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.en, .enGB]) == "en")
        
        #expect(bundle.localizedString(forKey: key, value: "nil", table: nil, localizations: [.de, .en]) == "de")
        #expect(bundle.localizedString(forKey: key, tables: [.default], localizations: [.de, .en]) == "de")
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.de, .en]) == "de")
        
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.enGB]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.enGB, .en]) == "en")
        #expect(bundle.localizedStringForKeyFallback(key: key, tables: [.default], localizations: [.de, .en]) == "de")
    }
    
    
    @Test
    @available(macOS 14.0, macCatalyst 17.0, *)
    func bundleLocalizationUtils2() throws {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let bundle = Bundle(for: HKHealthStore.self)
        let key1 = "STEPS"
        
        #expect(bundle.localizedString(forKey: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.de]) == "Schritte")
        #expect(bundle.localizedStringForKeyFallback(key: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.de]) == "Schritte")
        
        #expect(bundle.localizedString(forKey: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.en]) == "Steps")
        #expect(bundle.localizedStringForKeyFallback(key: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.en]) == "Steps")
        
        #expect(bundle.localizedString(forKey: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.en, .de]) == "Steps")
        #expect(bundle.localizedStringForKeyFallback(key: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.en, .de]) == "Steps")
        
        #expect(bundle.localizedString(forKey: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.de, .en]) == "Schritte")
        #expect(bundle.localizedStringForKeyFallback(key: key1, tables: [.custom("Localizable-DataTypes")], localizations: [.de, .en]) == "Schritte")
        #endif
    }
    
    
    @Test
    func localizedStringResourceUtil() {
        let resource = LocalizedStringResource(
            "HELLO_WORLD",
            defaultValue: "HELLO_WORLD",
            bundle: .atURL(from: .module)
        )
        #expect(resource.localizedString(for: .init(identifier: "en_US")) == "Hello, World!")
        #expect(resource.localizedString(for: .init(identifier: "de_DE")) == "Hallo, Welt!")
    }
    
    
    @Test
    func localizationKeys() throws {
        #expect(Locale(identifier: "en-UK") == Locale(identifier: "en-GB"))
        #expect(Locale(identifier: "en-UK").identifier == "en-GB")
        #expect(LocalizationKey(locale: .init(identifier: "de_DE"))?.description == "de-DE")
        #expect(LocalizationKey(locale: .init(identifier: "de-DE"))?.description == "de-DE")
        #expect(LocalizationKey(locale: .init(identifier: "en-US"))?.description == "en-US")
        #expect(LocalizationKey(locale: .init(identifier: "en-UK"))?.description == "en-GB")
        #expect(LocalizationKey(locale: .init(identifier: "en-GB"))?.description == "en-GB")
        #expect(LocalizationKey(locale: .init(identifier: "en-DE"))?.description == "en-DE")
        #expect(LocalizationKey(locale: .init(identifier: "es_DE"))?.description == "es-DE")
    }
    
    @Test
    func localizationKeyParsing() {
        #expect(Locale(identifier: "en-UK").language == .enGB)
        #expect(Locale(identifier: "en-UK").region == .unitedKingdom)
        #expect(Locale(identifier: "en-UK").region?.isISORegion == true)
        #expect(LocalizationKey("en-UK") == LocalizationKey(language: .en, region: .unitedKingdom))
        #expect(LocalizationKey("en-GB") == LocalizationKey(language: .en, region: .unitedKingdom))
    }
    
    @Test
    func localizationKeyEquality() throws {
        let keys = [
            LocalizationKey(language: .init(identifier: "en"), region: .unitedKingdom),
            try #require(LocalizationKey("en-UK")),
            try #require(LocalizationKey("en-GB"))
        ]
        for key1 in keys {
            for key2 in keys {
                #expect(key1 == key2)
                #expect(key2 == key1)
                #expect(key1.region == key2.region)
                #expect(key2.region == key1.region)
                #expect(key1.language.isEquivalent(to: key2.language))
                #expect(key2.language.isEquivalent(to: key1.language))
            }
        }
        for _ in 0..<5_000 {
            #expect(Set(keys).count == 1)
        }
    }

    @Test
    func localizationKeyCodableRoundTrip() throws {
        let key = try #require(LocalizationKey("en-US"))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(key)
        let decoded = try decoder.decode(LocalizationKey.self, from: data)
        #expect(decoded == key)
        #expect(decoded.description == "en-US")
    }

    @Test
    func localizationKeyCodableEncodesAsString() throws {
        let key = try #require(LocalizationKey("de-DE"))
        let data = try JSONEncoder().encode(key)
        let jsonString = try #require(String(data: data, encoding: .utf8))
        #expect(jsonString == "\"de-DE\"")
    }

    @Test
    func localizationKeyCodableDecodesFromString() throws {
        let data = Data("\"es-US\"".utf8)
        let key = try JSONDecoder().decode(LocalizationKey.self, from: data)
        #expect(key == LocalizationKey("es-US"))
    }

    @Test
    func localizationKeyCodableInvalidStringThrows() throws {
        let data = Data("\"invalid\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LocalizationKey.self, from: data)
        }
    }
    
    
    @Test
    func localizationKeyScoring() {
        let esUS = LocalizationKey(language: .es, region: .unitedStates)
        #expect(esUS.description == "es-US")
        let es419 = LocalizationKey(language: .es, region: .latinAmerica)
        #expect(es419.description == "es-419")
        let es419US = LocalizationKey(language: .init(identifier: "es-419"), region: .unitedStates)
        #expect(es419US.description == "es-419-US")
        let esES = LocalizationKey(language: .es, region: .spain)
        #expect(esES.description == "es-ES")
        #expect(es419.score(against: Locale.esUS, using: .requirePerfectMatch) == 0)
        #expect(es419.score(against: Locale.Language.esUS, using: .requirePerfectMatch) == 0)
        #expect(esUS.score(against: Locale.Language(identifier: "es-419"), using: .requirePerfectMatch) == 0)
        #expect(esUS.score(against: .es, using: .requirePerfectMatch) == 0.9)
        #expect(esES.score(against: .es, using: .requirePerfectMatch) == 0.9)
    }
}


extension Locale.Language {
    // swiftlint:disable identifier_name
    fileprivate static let en = Self(identifier: "en")
    fileprivate static let de = Self(identifier: "de")
    fileprivate static let fr = Self(identifier: "fr")
    fileprivate static let es = Self(identifier: "es")
    fileprivate static let jp = Self(identifier: "jp")
    fileprivate static let enGB = Self(identifier: "en-GB")
    fileprivate static let esUS = Self(identifier: "es-US")
    // swiftlint:enable identifier_name
}

#endif
