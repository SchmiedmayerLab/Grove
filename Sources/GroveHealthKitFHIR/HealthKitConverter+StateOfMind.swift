//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape; the dispatch tables read as one table.
// swiftlint:disable multiline_literal_brackets

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    private static let stateOfMindLabels: [HKStateOfMind.Label: String] = [
        .amazed: "amazed",
        .amused: "amused",
        .angry: "angry",
        .anxious: "anxious",
        .ashamed: "ashamed",
        .brave: "brave",
        .calm: "calm",
        .content: "content",
        .disappointed: "disappointed",
        .discouraged: "discouraged",
        .disgusted: "disgusted",
        .embarrassed: "embarrassed",
        .excited: "excited",
        .frustrated: "frustrated",
        .grateful: "grateful",
        .guilty: "guilty",
        .happy: "happy",
        .hopeless: "hopeless",
        .irritated: "irritated",
        .jealous: "jealous",
        .joyful: "joyful",
        .lonely: "lonely",
        .passionate: "passionate",
        .peaceful: "peaceful",
        .proud: "proud",
        .relieved: "relieved",
        .sad: "sad",
        .scared: "scared",
        .stressed: "stressed",
        .surprised: "surprised",
        .worried: "worried",
        .annoyed: "annoyed",
        .confident: "confident",
        .drained: "drained",
        .hopeful: "hopeful",
        .indifferent: "indifferent",
        .overwhelmed: "overwhelmed",
        .satisfied: "satisfied"
    ]

    private static let stateOfMindAssociations: [HKStateOfMind.Association: String] = [
        .community: "community",
        .currentEvents: "current-events",
        .dating: "dating",
        .education: "education",
        .family: "family",
        .fitness: "fitness",
        .friends: "friends",
        .health: "health",
        .hobbies: "hobbies",
        .identity: "identity",
        .money: "money",
        .partner: "partner",
        .selfCare: "self-care",
        .spirituality: "spirituality",
        .tasks: "tasks",
        .travel: "travel",
        .work: "work",
        .weather: "weather"
    ]

    private static let stateOfMindKinds: [HKStateOfMind.Kind: String] = [
        .momentaryEmotion: "momentary-emotion",
        .dailyMood: "daily-mood"
    ]

    private static let stateOfMindValenceClassifications: [HKStateOfMind.ValenceClassification: String] = [
        .veryUnpleasant: "very-unpleasant",
        .unpleasant: "unpleasant",
        .slightlyUnpleasant: "slightly-unpleasant",
        .neutral: "neutral",
        .slightlyPleasant: "slightly-pleasant",
        .pleasant: "pleasant",
        .veryPleasant: "very-pleasant"
    ]

    /// The reflection's valence, which is the Observation value.
    ///
    /// Valence is the one numeric axis: a dimensionless −1…1 score, so UCUM's unity code applies.
    static func stateOfMindValue(_ sample: HKStateOfMind) throws -> Quantity {
        guard let contract = HealthKitMeasurementCatalog.stateOfMind.quantity else {
            throw HealthKitConversionError.invalidValue
        }
        return try fhirQuantity(value: sample.valence, contract: contract)
    }

    /// Every coded axis of the reflection.
    ///
    /// Labels and associations repeat, and are emitted in a stable order so an unchanged sample
    /// always converts to the same Observation.
    static func stateOfMindComponents(_ sample: HKStateOfMind) throws -> [ObservationComponent] {
        var components: [ObservationComponent] = []
        let contract = HealthKitMeasurementCatalog.stateOfMind
        if let kind = stateOfMindKinds[sample.kind] {
            components.append(try codedComponent(id: "kind", value: kind, contract: contract))
        }
        if let classification = stateOfMindValenceClassifications[sample.valenceClassification] {
            components.append(try codedComponent(id: "valence-classification", value: classification, contract: contract))
        }
        for label in sample.labels.compactMap({ stateOfMindLabels[$0] }).sorted() {
            components.append(try codedComponent(id: "label", value: label, contract: contract))
        }
        for association in sample.associations.compactMap({ stateOfMindAssociations[$0] }).sorted() {
            components.append(try codedComponent(id: "association", value: association, contract: contract))
        }
        return components
    }

    /// One coded component, with its code, system, and result system taken from the contract.
    private static func codedComponent(
        id: String,
        value: String,
        contract: MeasurementContract
    ) throws -> ObservationComponent {
        guard let component = contract.components.first(where: { $0.id == id }),
              let resultSystem = component.resultCodeSystem else {
            throw HealthKitConversionError.missingRequiredComponent(sampleType: contract.id, component: id)
        }
        return ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: FHIRPrimitive(FHIRString(stringLiteral: component.code)),
                system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
            )]),
            value: .codeableConcept(CodeableConcept(coding: [Coding(
                code: FHIRPrimitive(FHIRString(stringLiteral: value)),
                system: FHIRPrimitive(FHIRURI(stringLiteral: resultSystem))
            )]))
        )
    }
}

#endif

// swiftlint:enable multiline_literal_brackets
