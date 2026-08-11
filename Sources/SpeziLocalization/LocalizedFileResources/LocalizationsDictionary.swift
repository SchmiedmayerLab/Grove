//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A dictionary of localized values keyed by locale.
///
/// Use `LocalizationsDictionary` to store values for multiple locales in a single value,
/// and resolve the best match for a given ``LocalizationKey`` using ``LocaleMatchingBehaviour`` scoring.
///
/// The type parameter `Value` determines what is stored per locale. For simple string translations,
/// use `LocalizationsDictionary<String>`:
///
/// ```swift
/// let translations = LocalizationsDictionary<String>([
///     .enUS: "Hello",
///     .deDE: "Hallo",
///     .enES: "Hola"
/// ])
/// let greeting = translations[.enUS]
/// // greeting == "Hello"
/// ```
///
/// You can also store structured content per locale:
///
/// ```swift
/// struct Article: Hashable, Codable {
///     let title: String
///     let content: String
/// }
/// let articles = LocalizationsDictionary<Article>([
///     .enUS: Article(title: "Welcome", content: "Hello there"),
///     .deDE Article(title: "Willkommen", content: "Hallo")
/// ])
/// let article = articles[.enUS]
/// // article == Article(title: "Welcome", content: "Hello there")
/// ```
///
/// ## Topics
///
/// ### Initializers
/// - ``init()``
/// - ``init(_:)-([LocalizationKey:Value])``
/// - ``init(_:)-(Sequence<(LocalizationKey,Value)>)``
///
/// ### Subscripts
/// - ``subscript(_:using:fallback:)``
/// - ``subscript(_:)
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LocalizationsDictionary<Value> {
    private var storage: [LocalizationKey: Value]

    /// Creates an empty localizations dictionary.
    public init() {
        self.storage = [:]
    }
    
    /// Creates a localizations dictionary from the given entries.
    public init(_ entries: [LocalizationKey: Value]) {
        self.storage = entries
    }

    /// Creates a localizations dictionary from the given entries.
    ///
    /// If the sequence contains multiple elements with the same key, latter occurrences will override earlier ones.
    public init(_ entries: some Sequence<(LocalizationKey, Value)>) {
        self.init()
        for (key, value) in entries {
            storage[key] = value
        }
    }

    /// Resolves the best value for the given localization key.
    ///
    /// Iterates all entries in the dictionary, scores each ``LocalizationKey`` against the target key
    /// using ``LocalizationKey/score(against:using:)-(Locale.Language,_)``, and returns the entry with the highest score
    /// (provided it exceeds `0`). If no match is found and a `fallback` key is specified, the fallback entry is returned.
    ///
    /// - Parameters:
    ///   - key: The localization key to resolve a value for.
    ///   - localeMatchingBehaviour: The matching behaviour to use. Defaults to ``LocaleMatchingBehaviour/default``.
    ///   - fallback: An optional fallback ``LocalizationKey`` to use if no match is found. Defaults to ``LocalizationKey/enUS``.
    /// - Returns: The best matching value, or `nil` if no match and no fallback exists.
    public subscript(
        _ key: LocalizationKey,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallback fallback: LocalizationKey? = .enUS
    ) -> Value? {
        var bestScore: Double = 0
        var bestValue: Value?
        let targetLanguage = key.language.withRegion(key.region)
        for (existingKey, value) in storage {
            let score = existingKey.score(against: targetLanguage, using: localeMatchingBehaviour)
            if score > bestScore {
                bestScore = score
                bestValue = value
            }
        }
        if let bestValue {
            return bestValue
        }
        if let fallback {
            return storage[fallback]
        }
        return nil
    }

    /// Access or set a value by its ``LocalizationKey``.
    @_disfavoredOverload
    public subscript(_ key: LocalizationKey) -> Value? {
        get { storage[key] }
        set { storage[key] = newValue }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: Equatable where Value: Equatable {}
@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: Hashable where Value: Hashable {}
@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: Sendable where Value: Sendable {}

@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: Encodable where Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.storage = try container.decode([LocalizationKey: Value].self)
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: Collection {
    public typealias Index = Dictionary<LocalizationKey, Value>.Index
    public typealias Element = Dictionary<LocalizationKey, Value>.Element

    public var startIndex: Index {
        storage.startIndex
    }

    public var endIndex: Index {
        storage.endIndex
    }

    public func index(after index: Index) -> Index {
        storage.index(after: index)
    }

    public subscript(position: Index) -> Element {
        storage[position]
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizationsDictionary: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (LocalizationKey, Value)...) {
        self.init(elements)
    }
}
