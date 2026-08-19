//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLocalization
import Testing

#if canImport(Darwin) // "Skipping on non-Darwin platforms: no systemLanguages available"
@Suite
struct LocalizationBundleTests { // swiftlint:disable:this type_body_length
    @Test
    func parseFilename() throws {
        let resolved = try #require(LocalizedFileResource.Resolved(
            resource: "Consent.md",
            url: URL(filePath: "Consent+en-US.md")
        ))
        #expect(resolved.unlocalizedFilename == "Consent.md")
        #expect(resolved.fullFilenameIncludingLocalization == "Consent+en-US.md")
        #expect(resolved.localization == .enUS)
    }
    
    @Test
    func urlExtensions() {
        #expect(URL(filePath: "/abc/def+en-US.txt").strippingLocalizationSuffix() == URL(filePath: "/abc/def.txt"))
        #expect(URL(filePath: "/def+en-US.txt").strippingLocalizationSuffix() == URL(filePath: "/def.txt"))
        #expect(URL(filePath: "def+en-US.txt").strippingLocalizationSuffix().absoluteURL == URL(filePath: "def.txt").absoluteURL)
        #expect(URL(filePath: "/def+en-US").strippingLocalizationSuffix() == URL(filePath: "/def"))
        #expect(URL(filePath: "def+en-US").strippingLocalizationSuffix().absoluteURL == URL(filePath: "def").absoluteURL)
    }
    
    @Test
    func resolveFromList() throws { // swiftlint:disable:this function_body_length
        let inputUrls = [
            "/news/Welcome.md",
            "/news/Welcome+en-US.md",
            "/news/Welcome+es-US.md",
            "/news/Welcome+es-ES.md",
            "/news/Welcome+en-UK.md",
            "/news/Welcome+de-DE.md",
            "/news/Update.md",
            "/news/Update+en-US.md",
            "/news/Update+es-US.md",
            "/news/Update+de-US.md"
        ].map { URL(filePath: $0) }
        
        func imp(
            _ resource: LocalizedFileResource,
            using localeMatchingBehavior: LocaleMatchingBehaviour,
            fallback: LocalizationKey? = nil,
            expectedPath: String,
            expectedLocalization: LocalizationKey,
            sourceLocation: SourceLocation = #_sourceLocation
        ) throws {
            let resolved = try #require(
                LocalizedFileResolution.resolve(resource, from: inputUrls, using: localeMatchingBehavior, fallback: fallback),
                sourceLocation: sourceLocation
            )
            #expect(resolved.url.path == expectedPath, sourceLocation: sourceLocation)
            #expect(resolved.localization == expectedLocalization, sourceLocation: sourceLocation)
        }
        
        try imp(
            LocalizedFileResource("Welcome.md", locale: .enUS),
            using: .requirePerfectMatch,
            expectedPath: "/news/Welcome+en-US.md",
            expectedLocalization: .enUS
        )
        
        try imp(
            LocalizedFileResource("news/Welcome.md", locale: .enUS),
            using: .requirePerfectMatch,
            expectedPath: "/news/Welcome+en-US.md",
            expectedLocalization: .enUS
        )
        try imp(
            LocalizedFileResource("/news/Welcome.md", locale: .enUS),
            using: .requirePerfectMatch,
            expectedPath: "/news/Welcome+en-US.md",
            expectedLocalization: .enUS
        )
        
        for behavior in [LocaleMatchingBehaviour.requirePerfectMatch, .preferLanguageMatch, .preferRegionMatch] {
            try imp(
                LocalizedFileResource("Welcome.md", locale: .deDE),
                using: behavior,
                expectedPath: "/news/Welcome+de-DE.md",
                expectedLocalization: .deDE
            )
        }
        try imp(
            LocalizedFileResource("Welcome.md", locale: .deUS),
            using: .preferLanguageMatch,
            expectedPath: "/news/Welcome+de-DE.md",
            expectedLocalization: .deDE
        )
        do {
            let resolved0 = LocalizedFileResolution.resolve(
                LocalizedFileResource("Welcome.md", locale: .deUS),
                from: inputUrls,
                using: .preferRegionMatch,
                fallback: nil
            )
            #expect(resolved0 == nil)
            // regardless of the fallback, we always expect a nil result when resolving a non-existant locale using `requirePerfectMatch`.
            for fallback: LocalizationKey? in [nil, .enUS, .esUS, .esES, .enUK, .deDE, .deUS] {
                let resolved = LocalizedFileResolution.resolve(
                    LocalizedFileResource("Welcome.md", locale: .deUS),
                    from: inputUrls,
                    using: .requirePerfectMatch,
                    fallback: fallback
                )
                #expect(resolved == nil)
            }
        }
        
        try imp(
            LocalizedFileResource("Update.md", locale: .enUS),
            using: .requirePerfectMatch,
            expectedPath: "/news/Update+en-US.md",
            expectedLocalization: .enUS
        )
        try imp(
            LocalizedFileResource("Update.md", locale: .deUS),
            using: .requirePerfectMatch,
            expectedPath: "/news/Update+de-US.md",
            expectedLocalization: .deUS
        )
        
        for behaviour in [LocaleMatchingBehaviour.requirePerfectMatch, .preferRegionMatch, .preferLanguageMatch] {
            try imp(
                LocalizedFileResource("Update.md", locale: .enUS),
                using: behaviour,
                expectedPath: "/news/Update+en-US.md",
                expectedLocalization: .enUS
            )
        }
        
        try imp(
            LocalizedFileResource("Welcome.md", locale: .esES),
            using: .default,
            expectedPath: "/news/Welcome+es-ES.md",
            expectedLocalization: .esES
        )
        try imp(
            LocalizedFileResource("Update.md", locale: .esES),
            using: .default,
            expectedPath: "/news/Update+es-US.md",
            expectedLocalization: .esUS
        )
        try imp(
            LocalizedFileResource("Welcome.md", locale: .frFR),
            using: .default,
            fallback: .enUS,
            expectedPath: "/news/Welcome+en-US.md",
            expectedLocalization: .enUS
        )
    }
    
    
    @Test
    func resolve2() throws {
        let urls: [URL] = try [
            "gs://myheart-counts-development.firebasestorage.app/public/news/Update+en-US.md",
            "gs://myheart-counts-development.firebasestorage.app/public/news/Update+en-UK.md",
            "gs://myheart-counts-development.firebasestorage.app/public/news/Update+es-US.md",
            "gs://myheart-counts-development.firebasestorage.app/public/news/Welcome+en-US.md",
            "gs://myheart-counts-development.firebasestorage.app/public/news/Welcome+en-UK.md",
            "gs://myheart-counts-development.firebasestorage.app/public/news/Welcome+es-US.md"
        ].map { try URL($0, strategy: .url) }
        
        func imp(
            _ resource: LocalizedFileResource,
            using localeMatchingBehavior: LocaleMatchingBehaviour,
            fallback: LocalizationKey? = nil,
            expectedPath: String,
            expectedLocalization: LocalizationKey,
            sourceLocation: SourceLocation = #_sourceLocation
        ) throws {
            let resolved = try #require(
                LocalizedFileResolution.resolve(resource, from: urls, using: localeMatchingBehavior, fallback: fallback),
                sourceLocation: sourceLocation
            )
            #expect(resolved.url.path == expectedPath, sourceLocation: sourceLocation)
            #expect(resolved.localization == expectedLocalization, sourceLocation: sourceLocation)
        }
        try imp(
            LocalizedFileResource("Update.md", locale: .enUK),
            using: .preferLanguageMatch,
            expectedPath: "/public/news/Update+en-UK.md",
            expectedLocalization: .enUK
        )
        try imp(
            LocalizedFileResource("Update.md", locale: .esUK),
            using: .preferLanguageMatch,
            expectedPath: "/public/news/Update+es-US.md",
            expectedLocalization: .esUS
        )
    }
    
    
    @Test
    func resolve3() throws {
        let url = URL(filePath: "/news/Welcome.md")
        let resolved = try #require(LocalizedFileResolution.resolve("Welcome.md", from: [url]))
        #expect(resolved.url == url)
        #expect(resolved.localization == .init(language: Locale.current.language, region: .unknown))
    }
    
    
    @Test
    func resolve4() throws {
        let urls = [
            "/news/Welcome.md",
            "/news/Welcome+en-US.md",
            "/news/Welcome+es-US.md",
            "/news/Welcome+es-ES.md",
            "/news/Welcome+en-UK.md",
            "/news/Welcome+de-DE.md",
            "/news/Update.md",
            "/news/Update+en-US.md",
            "/news/Update+es-US.md",
            "/news/Update+de-US.md"
        ].map { URL(filePath: $0) }
        #expect(LocalizedFileResolution.selectCandidatesIgnoringLocalization(
            matching: LocalizedFileResource("Welcome.md"),
            from: urls
        ) == [
            try #require(LocalizedFileResource.Resolved(resource: "Welcome.md", url: URL(filePath: "/news/Welcome+en-US.md"))),
            try #require(LocalizedFileResource.Resolved(resource: "Welcome.md", url: URL(filePath: "/news/Welcome+es-US.md"))),
            try #require(LocalizedFileResource.Resolved(resource: "Welcome.md", url: URL(filePath: "/news/Welcome+es-ES.md"))),
            try #require(LocalizedFileResource.Resolved(resource: "Welcome.md", url: URL(filePath: "/news/Welcome+en-UK.md"))),
            try #require(LocalizedFileResource.Resolved(resource: "Welcome.md", url: URL(filePath: "/news/Welcome+de-DE.md")))
        ])
        
        #expect(LocalizedFileResolution.selectCandidatesIgnoringLocalization(
            matching: LocalizedFileResource("Update.md"),
            from: urls
        ) == [
            try #require(LocalizedFileResource.Resolved(resource: "Update.md", url: URL(filePath: "/news/Update+en-US.md"))),
            try #require(LocalizedFileResource.Resolved(resource: "Update.md", url: URL(filePath: "/news/Update+es-US.md"))),
            try #require(LocalizedFileResource.Resolved(resource: "Update.md", url: URL(filePath: "/news/Update+de-US.md")))
        ])
    }
    
    
    @Test
    func localeStuff() {
        #expect(LocalizationKey(locale: .enUS) == LocalizationKey(language: .init(identifier: "en"), region: .unitedStates))
        #expect(LocalizationKey(locale: .enUK) == LocalizationKey(language: .init(identifier: "en"), region: .unitedKingdom))
    }
    
    
    @Test
    func parseLocalizationInfo() throws {
        func imp(
            url: String,
            expected: (unlocalizedUrl: String, localization: LocalizationKey)?,
            sourceLocation: SourceLocation = #_sourceLocation
        ) throws {
            let url = try URL(url, strategy: .url)
            let result = LocalizedFileResolution.parse(url)
            switch expected {
            case nil:
                #expect(result == nil, sourceLocation: sourceLocation)
            case let .some(expected):
                let result = try #require(result, "Expected nil, but got \(String(describing: result))", sourceLocation: sourceLocation)
                let expectedUrl = try URL(expected.unlocalizedUrl, strategy: .url)
                #expect(result.unlocalizedUrl == expectedUrl, sourceLocation: sourceLocation)
                #expect(result.localization == expected.localization, sourceLocation: sourceLocation)
            }
        }
        
        try imp(url: "file:///news/Welcome.md", expected: nil)
        try imp(
            url: "file:///news/Welcome+en-US.md",
            expected: ("file:///news/Welcome.md", try #require(.init(locale: .enUS)))
        )
        try imp(
            url: "file:///news/Welcome+es-US.md",
            expected: ("file:///news/Welcome.md", try #require(.init(locale: .esUS)))
        )
        try imp(
            url: "file:///news/Welcome+en-UK.md",
            expected: ("file:///news/Welcome.md", try #require(.init(locale: .enUK)))
        )
        try imp(
            url: "file:///news/Welcome+en-DE.md",
            expected: ("file:///news/Welcome.md", try #require(.init(locale: .enDE)))
        )
    }
}
#endif

extension Locale {
    static let enUS = Self(identifier: "en_US")
    static let enUK = Self(identifier: "en_UK")
    static let esUS = Self(identifier: "es_US")
    static let esUK = Self(identifier: "es_UK")
    static let deDE = Self(identifier: "de_DE")
    static let deUS = Self(identifier: "de_US")
    static let esES = Self(identifier: "es_ES")
    static let frFR = Self(identifier: "fr_FR")
    static let enDE = Self(identifier: "en_DE")
}

extension LocalizationKey {
    static let deDE = Self(language: .init(identifier: "de"), region: .germany)
    static let deUS = Self(language: .init(identifier: "de"), region: .unitedStates)
    static let enUK = Self(language: .init(identifier: "en"), region: .unitedKingdom)
    static let esUS = Self(language: .init(identifier: "es"), region: .unitedStates)
    static let esES = Self(language: .init(identifier: "es"), region: .spain)
    static let frFR = Self(language: .init(identifier: "fr"), region: .france)
    static let jaJP = Self(language: .init(identifier: "ja"), region: .japan)
}
