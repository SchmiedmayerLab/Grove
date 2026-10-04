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


/// How a quantity value is read from its sample.
@available(iOS 18, macOS 15, watchOS 11, *)
enum QuantityRead: Sendable {
    /// The sample's quantity in this unit.
    case unit(HKUnit)
    /// The sample's quantity as a fraction, stated in percent.
    case percent
    /// A scored assessment's score.
    case score
}


/// One member of a blood-pressure correlation: the contract component it becomes, the quantity type it is stated as
/// and the unit it is read in.
@available(iOS 18, macOS 15, watchOS 11, *)
struct BloodPressureMember: Sendable {
    /// The contract component's id, which a correlation without the member misses.
    let component: String
    /// The member's quantity type.
    let quantityType: HKQuantityTypeIdentifier
    /// The component's UCUM code and display unit, and the HealthKit unit the member is read in.
    let binding: HealthKitUnitBinding
    /// The component the member's reading becomes.
    let template: ComponentTemplate
}


/// How an Observation's value is read from its sample, compiled against the contract.
@available(iOS 18, macOS 15, watchOS 11, *)
enum ValueRule: Sendable {
    /// A quantity, read as `QuantityRead` says, in the contract's quantity.
    case quantity(QuantityTemplate, QuantityRead)
    /// A category value: the coded value of each raw value the table maps. A raw value in `unresolved` maps to a code
    /// the contract does not admit and has no normative code; any other unmapped raw value is unsupported.
    case coded(values: [Int: CodeableConcept], unresolved: Set<Int>)
    /// A category sample's duration in the contract's quantity, whose unit lasts `secondsPerUnit` seconds; the sample
    /// states `HKCategoryValue.notApplicable`.
    case duration(QuantityTemplate, secondsPerUnit: Double)
    /// Whether protection was used: unknown when the metadata states nothing, else as the Boolean says; the sample
    /// states `HKCategoryValue.notApplicable`.
    case protection(unknown: CodeableConcept, protected: CodeableConcept, unprotected: CodeableConcept)
    /// The panel's members, one component each, in the contract's component order, and no value.
    case bloodPressure([BloodPressureMember])
    /// A workout session's activity and statistics.
    case workout(HealthKitWorkoutContent)
    /// A reflection's valence and coded axes.
    case stateOfMind(HealthKitStateOfMindContent)
}


/// Everything about one source type's Observation that does not depend on the sample.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ObservationPlan: Sendable {
    /// The Observation every sample of the type starts from: its code with the display and the required codings,
    /// status final, the source-type extension, the profiles, the category and the aggregation method.
    let skeleton: Observation
    /// How the effective time is drawn from the sample's start and end.
    let effective: EffectiveRule
    /// How the value is read.
    let value: ValueRule
    /// The metadata stated as a further component, after the value's own components.
    let metadataComponent: MetadataComponentRule?

    /// The Observation a source type's content starts from: final, of `code`, with the source-type extension as its
    /// only content extension, its profiles, and the category and aggregation method its measurement fixes.
    ///
    /// HealthKit keeps no per-object availability time, so `issued` stays absent; the conversion time is on Provenance.
    static func skeleton(
        code: CodeableConcept,
        sourceType: HealthKitSourceType,
        profiles: [FHIRPrimitive<Canonical>],
        category: CodingContract? = nil,
        method: MethodContract? = nil
    ) -> Observation {
        var observation = Observation(code: code, status: FHIRPrimitive(.final))
        observation.extension = [sourceType.lineage]
        observation.meta = Meta(profile: profiles)
        observation.category = category.map { [CodeableConcept(coding: [Coding($0)])] }
        observation.method = method.map { method in
            CodeableConcept(coding: [Coding(method.code, display: method.display, system: Canonicals.aggregationMethodCodeSystem)])
        }
        return observation
    }
}

#endif
