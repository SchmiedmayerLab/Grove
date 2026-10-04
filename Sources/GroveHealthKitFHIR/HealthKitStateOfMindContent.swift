//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit
import ModelsR4


/// The parts of a reflection's Observation that every reflection shares, compiled from the State of Mind contract.
///
/// The value is the valence. The components are the kind, then the valence classification, then the labels and the
/// associations, each sorted by code with repeats kept; a value the tables do not name is dropped, and no coding
/// states a display. Every code is one its component's contract admits.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitStateOfMindContent: Sendable {
    /// A coded component, with the code it sorts by.
    struct Coded: Sendable {
        /// The value's code.
        let code: String
        /// The component.
        let component: ObservationComponent
    }

    /// The kind of each reflection.
    private static let kindCodes: KeyValuePairs<HKStateOfMind.Kind, String> = [
        .momentaryEmotion: "momentary-emotion",
        .dailyMood: "daily-mood"
    ]

    /// The class of each valence.
    private static let classificationCodes: KeyValuePairs<HKStateOfMind.ValenceClassification, String> = [
        .veryUnpleasant: "very-unpleasant",
        .unpleasant: "unpleasant",
        .slightlyUnpleasant: "slightly-unpleasant",
        .neutral: "neutral",
        .slightlyPleasant: "slightly-pleasant",
        .pleasant: "pleasant",
        .veryPleasant: "very-pleasant"
    ]

    /// The emotion of each label.
    private static let labelCodes: KeyValuePairs<HKStateOfMind.Label, String> = [
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

    /// The life area of each association.
    private static let associationCodes: KeyValuePairs<HKStateOfMind.Association, String> = [
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

    /// The valence, a dimensionless score in the contract's domain.
    let valence: QuantityTemplate
    /// The component of each kind.
    let kinds: [HKStateOfMind.Kind: ObservationComponent]
    /// The component of each valence classification.
    let classifications: [HKStateOfMind.ValenceClassification: ObservationComponent]
    /// The component of each label.
    let labels: [HKStateOfMind.Label: Coded]
    /// The component of each association.
    let associations: [HKStateOfMind.Association: Coded]

    /// The content of the State of Mind contract.
    init(_ contract: MeasurementContract) throws(HealthKitContentDefect) {
        guard let valence = contract.quantity else {
            throw HealthKitContentDefect("states no valence quantity")
        }
        self.valence = QuantityTemplate(valence)
        kinds = try Self.components("kind", Self.kindCodes, of: contract).mapValues(\.component)
        classifications = try Self.components("valence-classification", Self.classificationCodes, of: contract).mapValues(\.component)
        labels = try Self.components("label", Self.labelCodes, of: contract)
        associations = try Self.components("association", Self.associationCodes, of: contract)
    }

    /// The component of each value of one coded axis, in the result CodeSystem of the contract's component `id`,
    /// which must admit every code.
    private static func components<Value: Hashable>(
        _ id: String,
        _ codes: KeyValuePairs<Value, String>,
        of contract: MeasurementContract
    ) throws(HealthKitContentDefect) -> [Value: Coded] {
        guard let component = contract.components.first(where: { $0.id == id }),
              let system = component.resultCodeSystem else {
            throw HealthKitContentDefect("states no coded component \(id)")
        }
        let code = CodeableConcept(coding: [Coding(component.code, system: component.system)])
        let admitted = component.resultCodes.map(\.code)
        let coded = try codes.map { value, result throws(HealthKitContentDefect) in
            let concept = CodeableConcept(coding: [try Coding(result, system: system, admittedBy: admitted)])
            return (value, Coded(code: result, component: ObservationComponent(code: code, value: .codeableConcept(concept))))
        }
        return Dictionary(coded) { first, _ in first }
    }

    /// Sets a reflection's components, then its valence, on `observation`.
    func apply(to observation: inout Observation, reflection: HKStateOfMind) throws(HealthKitValueFailure) {
        let axes = [kinds[reflection.kind], classifications[reflection.valenceClassification]].compactMap(\.self)
        let labels = reflection.labels.compactMap { self.labels[$0] }.sorted { $0.code < $1.code }
        let associations = reflection.associations.compactMap { self.associations[$0] }.sorted { $0.code < $1.code }
        observation.component = axes + (labels + associations).map(\.component)
        observation.value = .quantity(try valence.quantity(reflection.valence))
    }
}

#endif
