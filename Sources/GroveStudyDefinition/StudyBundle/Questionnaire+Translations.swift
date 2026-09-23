//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import FHIRModelsExtensions
import ModelsR4


/// The extensions whose values are rendered text, and so carry translations.
private let translatableItemExtensions: Set<String> = [
    "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText",
    "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-openLabel",
    "http://hl7.org/fhir/StructureDefinition/entryFormat",
    "http://hl7.org/fhir/StructureDefinition/questionnaire-unit",
    "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption",
    "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-itemMedia",
    "http://hl7.org/fhir/StructureDefinition/targetConstraint",
    "http://hl7.org/fhir/StructureDefinition/rendering-markdown",
    // Sub-extension of targetConstraint.
    "human"
]
private let translatableOptionExtensions: Set<String> = [
    "http://hl7.org/fhir/StructureDefinition/questionnaire-optionPrefix"
]


extension ModelsR4.Questionnaire {
    /// Adds the text of `other`, this questionnaire written in `language`, as translations of this one's text.
    ///
    /// Elements are paired by position and linkId, so both must share one structure.
    mutating func addTranslations(from other: Self, in language: String) {
        title = title.translated(by: other.title, in: language)
        description_fhir = description_fhir.translated(by: other.description_fhir, in: language)
        purpose = purpose.translated(by: other.purpose, in: language)
        item = item?.map { item in
            other.item?.first { $0.linkId == item.linkId }.map { item.translated(by: $0, in: language) } ?? item
        }
        contained = contained?.map { resource in
            guard case .valueSet(let valueSet) = resource,
                  case .valueSet(let otherValueSet)? = other.contained?.first(where: { $0.valueSetId == valueSet.id }) else {
                return resource
            }
            return .valueSet(valueSet.translated(by: otherValueSet, in: language))
        }
    }
}


extension ModelsR4.QuestionnaireItem {
    fileprivate func translated(by other: Self, in language: String) -> Self {
        var item = self
        item.text = text.translated(by: other.text, in: language)
        item.prefix = prefix.translated(by: other.prefix, in: language)
        item.extension = `extension`.translated(by: other.extension, in: language, urls: translatableItemExtensions)
        item.answerOption = answerOption.map { options in
            options.enumerated().map { index, option in
                other.answerOption?.indices.contains(index) == true
                    ? option.translated(by: other.answerOption?[index], in: language)
                    : option
            }
        }
        item.item = self.item?.map { child in
            other.item?.first { $0.linkId == child.linkId }.map { child.translated(by: $0, in: language) } ?? child
        }
        return item
    }
}


extension ModelsR4.QuestionnaireItemAnswerOption {
    fileprivate func translated(by other: Self?, in language: String) -> Self {
        var option = self
        switch (value, other?.value) {
        case let (.coding(coding), .coding(otherCoding)?):
            option.value = .coding(coding.translated(by: otherCoding, in: language))
        case let (.string(string), .string(otherString)?):
            // The base value stays the stored answer; the translation only changes what is displayed.
            option.value = .string(string.translated(by: otherString, in: language))
        default:
            break
        }
        option.extension = `extension`.translated(by: other?.extension, in: language, urls: translatableOptionExtensions)
        return option
    }
}


extension ModelsR4.ValueSet {
    fileprivate func translated(by other: Self, in language: String) -> Self {
        var valueSet = self
        valueSet.compose?.include = compose?.include.enumerated().map { index, include in
            var include = include
            let otherConcepts = other.compose?.include.indices.contains(index) == true ? other.compose?.include[index].concept : nil
            include.concept = include.concept?.map { concept in
                var concept = concept
                concept.display = concept.display.translated(
                    by: otherConcepts?.first { $0.code == concept.code }?.display,
                    in: language
                )
                return concept
            }
            return include
        } ?? []
        valueSet.expansion?.contains = expansion?.contains?.translated(by: other.expansion?.contains, in: language)
        return valueSet
    }
}


extension [ValueSetExpansionContains] {
    fileprivate func translated(by other: Self?, in language: String) -> Self {
        map { entry in
            guard let counterpart = other?.first(where: { $0.system == entry.system && $0.code == entry.code }) else {
                return entry
            }
            var entry = entry
            entry.display = entry.display.translated(by: counterpart.display, in: language)
            entry.contains = entry.contains?.translated(by: counterpart.contains, in: language)
            return entry
        }
    }
}


extension Optional where Wrapped == [ModelsR4.Extension] {
    /// Translates the rendered values among `urls`, pairing each extension with the one at the same position among
    /// `other`'s extensions of its url.
    fileprivate func translated(by other: Self, in language: String, urls: Set<String>) -> Self {
        map { extensions in
            var ordinals: [String: Int] = [:]
            return extensions.map { ext in
                let url = ext.url.value?.url.absoluteString ?? ""
                let ordinal = ordinals[url, default: 0]
                ordinals[url] = ordinal + 1
                guard urls.contains(url),
                      let counterpart = (other ?? []).filter({ $0.url.value?.url.absoluteString == url }).dropFirst(ordinal).first else {
                    return ext
                }
                return ext.translated(by: counterpart, in: language)
            }
        }
    }
}


extension ModelsR4.Extension {
    fileprivate func translated(by other: Self, in language: String) -> Self {
        var ext = self
        switch (value, other.value) {
        case let (.string(string), .string(otherString)?):
            ext.value = .string(string.translated(by: otherString, in: language))
        case let (.markdown(markdown), .markdown(otherMarkdown)?):
            ext.value = .markdown(markdown.translated(by: otherMarkdown, in: language))
        case let (.coding(coding), .coding(otherCoding)?):
            ext.value = .coding(coding.translated(by: otherCoding, in: language))
        case let (.attachment(attachment), .attachment(otherAttachment)?):
            var translated = attachment
            translated.title = attachment.title.translated(by: otherAttachment.title, in: language)
            ext.value = .attachment(translated)
        default:
            break
        }
        ext.extension = `extension`.translated(by: other.extension, in: language, urls: translatableItemExtensions)
        return ext
    }
}


extension ModelsR4.Coding {
    fileprivate func translated(by other: Self, in language: String) -> Self {
        var coding = self
        coding.display = display.translated(by: other.display, in: language)
        return coding
    }
}


extension FHIRPrimitive where PrimitiveType == FHIRString {
    /// The string carrying `other`'s value as its translation into `language`, as does a `rendering-markdown` equivalent it carries.
    fileprivate func translated(by other: Self, in language: String) -> Self {
        var string = self
        string.extension = `extension`.translated(by: other.extension, in: language, urls: translatableItemExtensions)
        if let content = other.value?.string {
            string.translations[language] = content
        }
        return string
    }
}


extension Optional where Wrapped == FHIRPrimitive<FHIRString> {
    fileprivate func translated(by other: Self, in language: String) -> Self {
        guard let other else {
            return self
        }
        return map { $0.translated(by: other, in: language) }
    }
}


extension ModelsR4.ResourceProxy {
    fileprivate var valueSetId: FHIRPrimitive<FHIRString>? {
        if case .valueSet(let valueSet) = self {
            valueSet.id
        } else {
            nil
        }
    }
}
