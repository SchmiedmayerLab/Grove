//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension PairRules {
    private static let translationURL = "http://hl7.org/fhir/StructureDefinition/translation"

    /// Both resources name a language, and the response names one the Questionnaire offers: its base language or any
    /// language it translates into, compared case-insensitively.
    static func validateLanguage(
        questionnaire: FHIRJSONObject,
        response: FHIRJSONObject,
        issues: inout [ValidationIssue]
    ) {
        let base = (questionnaire["language"] as? String)?.lowercased()
        if base == nil {
            issues.append(.init(
                code: .questionnaireLanguageRequired,
                path: "Questionnaire.language",
                message: "Questionnaire.language must name the language of the base text."
            ))
        }
        var offered = Set(base.map { [$0] } ?? [])
        validateTranslations(in: questionnaire, path: "Questionnaire", base: base, offered: &offered, issues: &issues)
        guard let language = response["language"] as? String else {
            issues.append(.init(
                code: .responseLanguageRequired,
                path: "QuestionnaireResponse.language",
                message: "QuestionnaireResponse.language must name the language the participant saw."
            ))
            return
        }
        if !offered.contains(language.lowercased()) {
            issues.append(.init(
                code: .responseLanguage,
                path: "QuestionnaireResponse.language",
                message: "QuestionnaireResponse.language must be one the Questionnaire offers \(offered.sorted()); found '\(language)'."
            ))
        }
    }

    /// Collects every translation language, rejecting a translation into the base language and a second one into a
    /// language a text already translates into.
    private static func validateTranslations(
        in value: Any,
        path: String,
        base: String?,
        offered: inout Set<String>,
        issues: inout [ValidationIssue]
    ) {
        if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                validateTranslations(in: element, path: "\(path)[\(index)]", base: base, offered: &offered, issues: &issues)
            }
            return
        }
        guard let object = value as? FHIRJSONObject else {
            return
        }
        var languages: Set<String> = []
        for translation in object["extension"] as? [FHIRJSONObject] ?? [] where translation["url"] as? String == translationURL {
            guard let language = (translation["extension"] as? [FHIRJSONObject])?
                .first(where: { $0["url"] as? String == "lang" })?["valueCode"] as? String else {
                continue
            }
            let tag = language.lowercased()
            offered.insert(tag)
            if tag == base || !languages.insert(tag).inserted {
                issues.append(.init(
                    code: .questionnaireTranslation,
                    path: "\(path).extension",
                    message: "A text translates into '\(language)', its base language or one it already translates into."
                ))
            }
        }
        for (key, child) in object {
            validateTranslations(in: child, path: "\(path).\(key)", base: base, offered: &offered, issues: &issues)
        }
    }
}
