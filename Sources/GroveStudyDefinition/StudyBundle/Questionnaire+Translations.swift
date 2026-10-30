//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


/// A value that differs between two locale sources of a questionnaire but is data, not presentation text, so it cannot
/// become a translation.
@available(iOS 18, macOS 15, watchOS 11, *)
struct TranslationConflict: Hashable {
    typealias Path = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Path
    typealias Value = StudyBundle.BundleValidationIssue.QuestionnaireIssue.Value

    let path: Path
    let baseValue: Value
    let localizedValue: Value
}


@available(iOS 18, macOS 15, watchOS 11, *)
private struct TranslationMerge {
    typealias JSONObject = [String: Any]
    typealias Path = TranslationConflict.Path

    /// Where an object sits, which decides whether its `valueString` is displayed text or data.
    enum Context {
        case root
        case element(key: String)
        case `extension`(url: String)

        /// An answer option's, initial value's or pattern's string is a value a response stores or is checked against.
        var holdsDataString: Bool {
            switch self {
            case .element(let key):
                ["answerOption", "initial"].contains(key)
            case .extension(let url):
                url == "http://hl7.org/fhir/StructureDefinition/regex"
            case .root:
                false
            }
        }
    }

    private static let translationURL = "http://hl7.org/fhir/StructureDefinition/translation"
    /// The elements whose strings are presentation text, and so carry translations.
    private static let presentationKeys: Set<String> = [
        "title", "description", "purpose", "copyright", "text", "prefix", "display", "unit", "valueString", "valueMarkdown"
    ]
    /// What describes each locale source rather than the questionnaire: its language, tags and narrative.
    private static let perSourceKeys: Set<String> = ["language", "meta", "text"]

    let language: String
    private(set) var conflicts: [TranslationConflict] = []

    init(language: String) {
        self.language = language
    }

    private static func carriesOnlyTranslations(_ primitive: Any) -> Bool {
        (primitive as? JSONObject)?.allSatisfy { key, value in
            key == "extension" && (value as? [JSONObject])?.allSatisfy { $0["url"] as? String == translationURL } == true
        } == true
    }

    /// Leaves are strings, numbers and booleans, which JSON writes identically exactly when they are equal.
    private static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs is String) == (rhs is String) && String(describing: lhs) == String(describing: rhs)
    }

    private static func value(_ value: Any?) -> TranslationConflict.Value {
        switch value {
        case let string as String:
            .init(string)
        case let value as JSONObject:
            .init((try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys)).map { String(decoding: $0, as: UTF8.self) })
        case .some(let value):
            .init(String(describing: value))
        case nil:
            nil
        }
    }

    mutating func conflict(at path: Path, base: Any?, localized: Any?) {
        conflicts.append(.init(path: path, baseValue: Self.value(base), localizedValue: Self.value(localized)))
    }

    mutating func walk(_ base: inout Any, _ other: Any, at path: Path, context: Context) {
        if var object = base as? JSONObject, let otherObject = other as? JSONObject {
            walk(&object, otherObject, at: path, context: context)
            base = object
        } else if var array = base as? [Any], let otherArray = other as? [Any] {
            guard array.count == otherArray.count else {
                conflict(at: path.length, base: array.count, localized: otherArray.count)
                return
            }
            for index in array.indices {
                walk(&array[index], otherArray[index], at: path[index], context: context)
            }
            base = array
        } else if !Self.isEqual(base, other) {
            conflict(at: path, base: base, localized: other)
        }
    }

    private mutating func walk(_ object: inout JSONObject, _ other: JSONObject, at path: Path, context: Context) {
        for (key, otherValue) in other.sorted(by: { $0.key < $1.key }) {
            if case .root = context, Self.perSourceKeys.contains(key) {
                continue
            }
            let isPrimitiveExtension = key.hasPrefix("_")
            guard var value = object[key] else {
                if !(isPrimitiveExtension && Self.carriesOnlyTranslations(otherValue)) {
                    conflict(at: path.appending(key), base: nil, localized: otherValue)
                }
                continue
            }
            if key == "extension" || key == "modifierExtension" {
                walkExtensions(&value, otherValue, at: path.appending(key))
            } else if let string = value as? String, let otherString = otherValue as? String, string != otherString {
                if Self.presentationKeys.contains(key) && !(key == "valueString" && context.holdsDataString) {
                    object["_\(key)"] = translating(object["_\(key)"], to: otherString)
                } else {
                    conflict(at: path.appending(key), base: string, localized: otherString)
                }
            } else {
                walk(&value, otherValue, at: path.appending(key), context: isPrimitiveExtension ? context : .element(key: key))
            }
            object[key] = value
        }
    }

    /// Pairs each extension with the one at the same position among the other source's extensions of its url.
    private mutating func walkExtensions(_ base: inout Any, _ other: Any, at path: Path) {
        guard var extensions = base as? [JSONObject], let otherExtensions = other as? [JSONObject] else {
            walk(&base, other, at: path, context: .root)
            return
        }
        let url = { (ext: JSONObject) in ext["url"] as? String ?? "" }
        let translatable = { (ext: JSONObject) in url(ext) != Self.translationURL }
        for otherURL in Set(otherExtensions.filter(translatable).map(url)) {
            let baseCount = extensions.count { url($0) == otherURL }
            let otherCount = otherExtensions.count { url($0) == otherURL }
            if baseCount != otherCount {
                conflict(at: path[otherURL].length, base: baseCount, localized: otherCount)
            }
        }
        var ordinals: [String: Int] = [:]
        for index in extensions.indices where translatable(extensions[index]) {
            let extensionURL = url(extensions[index])
            let ordinal = ordinals[extensionURL, default: 0]
            ordinals[extensionURL] = ordinal + 1
            guard let counterpart = otherExtensions.filter({ url($0) == extensionURL }).dropFirst(ordinal).first else {
                continue
            }
            var ext = extensions[index]
            walk(&ext, counterpart, at: path[extensionURL], context: .extension(url: extensionURL))
            extensions[index] = ext
        }
        base = extensions
    }

    /// The primitive's extensions (`_element`), carrying `content` as its one translation into ``language``.
    private func translating(_ primitive: Any?, to content: String) -> JSONObject {
        var primitive = primitive as? JSONObject ?? [:]
        let extensions = primitive["extension"] as? [JSONObject] ?? []
        let isTranslation = { (ext: JSONObject) in ext["url"] as? String == Self.translationURL }
        let lang = { (ext: JSONObject) in
            (ext["extension"] as? [JSONObject])?.first { $0["url"] as? String == "lang" }?["valueCode"] as? String ?? ""
        }
        let translation: JSONObject = [
            "url": Self.translationURL,
            "extension": [["url": "lang", "valueCode": language], ["url": "content", "valueString": content]]
        ]
        let translations = extensions.filter { isTranslation($0) && lang($0).caseInsensitiveCompare(language) != .orderedSame } + [translation]
        primitive["extension"] = extensions.filter { !isTranslation($0) } + translations.sorted { lang($0) < lang($1) }
        return primitive
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.Questionnaire {
    /// Adds `other`, this questionnaire written in `language`, as translations of this one's text.
    ///
    /// The two are walked in parallel, pairing array elements by position and extensions by url and position.
    /// A string that differs becomes a `translation` extension on the base string when it is presentation text,
    /// and a conflict when it is data, as is every other value that differs and everything only `other` carries.
    mutating func addTranslations(from other: Self, in language: String) throws -> [TranslationConflict] {
        var merge = TranslationMerge(language: language)
        var base: Any = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        if language.caseInsensitiveCompare(self.language?.value?.string ?? "") == .orderedSame {
            merge.conflict(at: .root.language, base: self.language?.value?.string, localized: language)
        } else {
            merge.walk(&base, try JSONSerialization.jsonObject(with: JSONEncoder().encode(other)), at: .root, context: .root)
        }
        self = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: base))
        return merge.conflicts
    }
}
