//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import GroveHealthKitFHIRMacros
import HealthKit
import ModelsR4


@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
extension HKStateOfMind: FHIRObservationBuildable {
    func build(_ observation: inout Observation, mapping: SampleTypesFHIRMapping) throws {
        let mapping = mapping.stateOfMindTypeMapping
        observation.append(codings: mapping.codings)
        observation.append(categories: mapping.categories.map { CodeableConcept(coding: [$0]) })
        // Every axis is a coded component: the kind, the classification, and the
        // (repeating) labels and associations. Only the valence is numeric — a
        // dimensionless -1…1 score, so UCUM's unity code applies.
        observation.append(component: .init(
            code: CodeableConcept(coding: mapping.kind.codings),
            value: .codeableConcept(CodeableConcept(coding: [self.kind.asCoding]))
        ))
        observation.append(component: .init(
            code: CodeableConcept(coding: mapping.valence.codings),
            value: .quantity(Quantity(
                code: "1".asFHIRStringPrimitive(),
                system: GroveFHIRVocabulary.ucum,
                unit: "score".asFHIRStringPrimitive(),
                value: try self.valence.asFHIRDecimalPrimitiveSafe()
            ))
        ))
        observation.append(component: .init(
            code: CodeableConcept(coding: mapping.valenceClassification.codings),
            value: .codeableConcept(CodeableConcept(coding: [self.valenceClassification.asCoding]))
        ))
        // Sorted so repeated components are emitted deterministically.
        for label in self.labels.sorted(by: { $0.rawValue < $1.rawValue }) {
            observation.append(component: .init(
                code: CodeableConcept(coding: mapping.label.codings),
                value: .codeableConcept(CodeableConcept(coding: [label.asCoding]))
            ))
        }
        for association in self.associations.sorted(by: { $0.rawValue < $1.rawValue }) {
            observation.append(component: .init(
                code: CodeableConcept(coding: mapping.association.codings),
                value: .codeableConcept(CodeableConcept(coding: [association.asCoding]))
            ))
        }
    }
}


@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
@SynthesizeDisplayProperty(
    HKStateOfMind.Kind.self,
    .momentaryEmotion, .dailyMood
)
@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
extension HKStateOfMind.Kind: FHIRCodingConvertibleHKEnum {}


@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
@SynthesizeDisplayProperty(
    HKStateOfMind.ValenceClassification.self,
    .veryUnpleasant, .unpleasant, .slightlyUnpleasant, .neutral, .slightlyPleasant, .pleasant, .veryPleasant
)
@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
extension HKStateOfMind.ValenceClassification: FHIRCodingConvertibleHKEnum {}


@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
@SynthesizeDisplayProperty(
    HKStateOfMind.Label.self,
    .amazed, .amused, .angry, .anxious, .ashamed, .brave, .calm, .content, .disappointed, .discouraged,
    .disgusted, .embarrassed, .excited, .frustrated, .grateful, .guilty, .happy, .hopeless, .irritated,
    .jealous, .joyful, .lonely, .passionate, .peaceful, .proud, .relieved, .sad, .scared, .stressed,
    .surprised, .worried, .annoyed, .confident, .drained, .hopeful, .indifferent, .overwhelmed, .satisfied
)
@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
extension HKStateOfMind.Label: FHIRCodingConvertibleHKEnum {}


@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
@SynthesizeDisplayProperty(
    HKStateOfMind.Association.self,
    .community, .currentEvents, .dating, .education, .family, .fitness, .friends, .health, .hobbies,
    .identity, .money, .partner, .selfCare, .spirituality, .tasks, .travel, .work, .weather
)
@available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
extension HKStateOfMind.Association: FHIRCodingConvertibleHKEnum {}

#endif
