//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import SpeziLocalization
import Testing

struct Article: Hashable, Codable {
    let title: String
    let body: String
}

@Suite
struct LocalizationsDictionaryTests {
    @Test
    func emptyInit() {
        let dict = LocalizationsDictionary<String>()
        #expect(dict.isEmpty)
    }

    @Test
    func dictionaryLiteral() {
        let dict = LocalizationsDictionary<String>([
            .enUS: "Hello World!",
            .deDE: "Hallo Welt!"
        ])
        #expect(dict.count == 2)
        #expect(dict[.enUS] == "Hello World!")
        #expect(dict[.deDE] == "Hallo Welt!")
    }

    @Test
    func subscriptByString() {
        var dict = LocalizationsDictionary<String>([:])
        dict[.enUS] = "Hello World!"
        #expect(dict[.enUS] == "Hello World!")
        dict[.enUS] = nil
        #expect(dict[.enUS] == nil)
        #expect(dict.isEmpty)
    }

    @Test
    func subscriptByLocalizationKey() {
        var dict = LocalizationsDictionary<String>()
        let key = LocalizationKey.enUS
        dict[key] = "Hello World!"
        #expect(dict[key] == "Hello World!")
    }

    @Test
    func perfectMatch() {
        let dict = LocalizationsDictionary<String>([
            .enUS: "Hello World!",
            .deDE: "Hallo Welt!"
        ])
        let result = dict[.enUS]
        #expect(result == "Hello World!")
    }

    @Test
    func partialLanguageMatch() {
        let dict = LocalizationsDictionary<String>([
            .enUS: "Hello World!",
            .deDE: "Hallo Welt!"
        ])
        let result = dict[.enUK, using: .preferLanguageMatch]
        #expect(result == "Hello World!")
    }

    @Test
    func noMatchReturnsFallback() {
        let dict = LocalizationsDictionary<String>([
            .enUS: "Hello World!",
            .deDE: "Hallo Welt!"
        ])
        let result = dict[
            .jaJP,
            using: .requirePerfectMatch,
            fallback: .enUS
        ]
        #expect(result == "Hello World!")
    }

    @Test
    func noMatchNoFallback() {
        let dict = LocalizationsDictionary<String>([
            .deDE: "Hallo Welt!"
        ])
        let result = dict[
            .jaJP,
            using: .requirePerfectMatch,
            fallback: nil
        ]
        #expect(result == nil)
    }

    @Test
    func fallbackKeyNotInDictionary() {
        let dict = LocalizationsDictionary<String>([
            .deDE: "Hallo Welt!"
        ])
        let result = dict[
            .frFR,
            using: .requirePerfectMatch,
            fallback: .enUS
        ]
        #expect(result == nil)
    }


    @Test
    func codableRoundTrip() throws {
        let original = LocalizationsDictionary<String>([
            .enUS: "Hello World!",
            .deDE: "Hallo Welt!",
            .esES: "Hola Mundo!"
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalizationsDictionary<String>.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func decodesFromJSON() throws {
        let json = Data(#"{"en-US":"Hello World!","de-DE":"Hallo Welt!"}"#.utf8)
        let dict = try JSONDecoder().decode(LocalizationsDictionary<String>.self, from: json)
        #expect(dict[.enUS] == "Hello World!")
        #expect(dict[.deDE] == "Hallo Welt!")
        #expect(dict.count == 2)
    }


    @Test
    func collectionConformance() {
        let dict = LocalizationsDictionary<String>([
            .enUS: "Hello World!",
            .deDE: "Hallo Welt!"
        ])
        #expect(dict.count == 2)
        #expect(!dict.isEmpty)

        var values = Set<String>()
        for (_, value) in dict {
            values.insert(value)
        }
        #expect(values == ["Hello World!", "Hallo Welt!"])
    }

    @Test
    func hashableEquality() {
        let dict1 = LocalizationsDictionary<String>([.enUS: "Hello World!", .deDE: "Hallo Welt!"])
        let dict2 = LocalizationsDictionary<String>([.enUS: "Hello World!", .deDE: "Hallo Welt!"])
        let dict3 = LocalizationsDictionary<String>([.enUS: "Hello World"])
        #expect(dict1 == dict2)
        #expect(dict1 != dict3)
        #expect(Set([dict1, dict2]).count == 1)
    }

    @Test
    func structuredValueCreation() {
        let dict = LocalizationsDictionary<Article>([
            .enUS: Article(title: "Welcome", body: "Hello there"),
            .deDE: Article(title: "Willkommen", body: "Hallo")
        ])
        #expect(dict.count == 2)
        #expect(dict[.enUS] == Article(title: "Welcome", body: "Hello there"))
    }

    @Test
    func structuredValueSubscript() {
        var dict = LocalizationsDictionary<Article>()
        let content = Article(title: "Welcome", body: "Hello there")
        dict[.enUS] = content
        #expect(dict[.enUS] == content)
    }

    @Test
    func structuredValueLocalizedValue() {
        let dict = LocalizationsDictionary<Article>([
            .enUS: Article(title: "Welcome", body: "Hello there"),
            .deDE: Article(title: "Willkommen", body: "Hallo")
        ])
        let result = dict[.deDE]
        #expect(result == Article(title: "Willkommen", body: "Hallo"))
    }

    @Test
    func structuredValueCodable() throws {
        let original = LocalizationsDictionary<Article>([
            .enUS: Article(title: "Welcome", body: "Hello there"),
            .deDE: Article(title: "Willkommen", body: "Hallo")
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalizationsDictionary<Article>.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func directSubscriptGetReturnsExactMatch() {
        let dict = LocalizationsDictionary<String>([
            .enUS: "Hello",
            .enUK: "Hello UK"
        ])
        let key: LocalizationKey = .enUK
        #expect(dict[key] == "Hello UK")
    }

    @Test
    func directSubscriptSetAndRemove() {
        var dict = LocalizationsDictionary<String>()
        let key: LocalizationKey = .deDE
        #expect(dict[key] == nil)
        dict[key] = "Hallo"
        #expect(dict[key] == "Hallo")
        #expect(dict.count == 1)
        dict[key] = nil
        #expect(dict[key] == nil)
        #expect(dict.isEmpty)
    }

    @Test
    func directSubscriptOverwritesValue() {
        var dict = LocalizationsDictionary<String>([
            .enUS: "Hello"
        ])
        let key: LocalizationKey = .enUS
        dict[key] = "Hi"
        #expect(dict[key] == "Hi")
        #expect(dict.count == 1)
    }
    
    
    @Test
    func dictionaryLiteralInit() {
        let dict: LocalizationsDictionary<String> = [
            .enUS: "Hello",
            .deDE: "Hallo"
        ]
        #expect(dict[.enUS] == "Hello")
        #expect(dict[.deDE] == "Hallo")
        #expect(dict[.enUK] == "Hello")
    }
}
