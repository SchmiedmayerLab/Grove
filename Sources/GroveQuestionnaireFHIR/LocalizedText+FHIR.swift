//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import FHIRModelsExtensions
import GroveQuestionnaire
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension GroveQuestionnaire.Questionnaire.LocalizedText {
    /// The text of a FHIR string with every `translation` it carries; `nil` when the string has no value.
    init?(_ primitive: FHIRPrimitive<ModelsR4.FHIRString>?) {
        guard let primitive, let base = primitive.value?.string else {
            return nil
        }
        self.init(base, translations: primitive.translations)
    }

    /// The FHIR string carrying the base text and one `translation` extension per language.
    func asFHIRStringPrimitive() -> FHIRPrimitive<ModelsR4.FHIRString> {
        var primitive = FHIRPrimitive(ModelsR4.FHIRString(base))
        primitive.translations = translations
        return primitive
    }
}
