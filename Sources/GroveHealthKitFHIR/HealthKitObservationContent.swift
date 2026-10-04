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
    /// The sample's quantity in the HealthKit unit its contract's unit binds to, which the public catalog and the
    /// reverse projection state.
    case unit(HealthKitCatalog.UnitBinding)
    /// A per-session rate HealthKit already computed, read as a plain count and bound to no unit.
    case platformRate
    /// The sample's quantity as a fraction, stated in percent by a decimal shift (``percent(ofFraction:)``).
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
    let binding: HealthKitCatalog.UnitBinding
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

    /// The Observation of one sample: the skeleton, stating the sample's effective time and value, then the metadata
    /// component. Each step is its own statement, so a sample with several faults is refused for the first one
    /// checked: the time zone, the effective time, the value, the metadata. Every fault is a
    /// `HealthKitConversionError.ValueFailure`, except a quantity value the decimal model cannot hold
    /// (``QuantityTemplate/quantity(_:)``).
    func observation(_ sample: HKSample, metadata: HealthKitSampleMetadata) throws -> Observation {
        let zone = try metadata.timeZone()
        var observation = skeleton
        observation.effective = try effective.value(start: sample.startDate, end: sample.endDate, zone: zone)
        try value.apply(to: &observation, sample: sample, metadata: metadata)
        if let component = try metadataComponent?.component(metadata) {
            observation.component = (observation.component ?? []) + [component]
        }
        return observation
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ValueRule {
    /// A category sample that states only that it occurred states `HKCategoryValue.notApplicable`; any other value is
    /// unsupported.
    private static func requireNotApplicable(_ sample: HKSample) throws(HealthKitConversionError.ValueFailure) {
        let raw = try sample.cast(to: HKCategorySample.self).value
        guard raw == HKCategoryValue.notApplicable.rawValue else {
            throw .unsupportedValue(raw)
        }
    }

    /// Whether protection was used: `unknown` when the metadata states nothing, else as its Boolean says; any other
    /// value is unsupported.
    private static func protection(
        _ metadata: HealthKitSampleMetadata,
        unknown: CodeableConcept,
        protected: CodeableConcept,
        unprotected: CodeableConcept
    ) throws(HealthKitConversionError.ValueFailure) -> CodeableConcept {
        switch metadata.values[HealthKitConversionError.MetadataField.sexualActivityProtectionUsed.key] {
        case nil: unknown
        case let used as Bool: used ? protected : unprotected
        case .some: throw .unsupportedMetadataValue(.sexualActivityProtectionUsed)
        }
    }

    /// Sets what `sample` states on `observation`: its value; a panel's components and no value; or a workout's or
    /// reflection's components, then its value.
    func apply(to observation: inout Observation, sample: HKSample, metadata: HealthKitSampleMetadata) throws {
        switch self {
        case let .quantity(template, read):
            observation.value = .quantity(try template.quantity(try read.value(of: sample)))
        case let .coded(values, unresolved):
            let raw = try sample.cast(to: HKCategorySample.self).value
            guard let value = values[raw] else {
                throw unresolved.contains(raw) ? HealthKitConversionError.ValueFailure.missingNormativeCode : .unsupportedValue(raw)
            }
            observation.value = .codeableConcept(value)
        case let .duration(template, secondsPerUnit):
            try Self.requireNotApplicable(sample)
            observation.value = .quantity(try template.quantity(sample.endDate.timeIntervalSince(sample.startDate) / secondsPerUnit))
        case let .protection(unknown, protected, unprotected):
            try Self.requireNotApplicable(sample)
            let value = try Self.protection(metadata, unknown: unknown, protected: protected, unprotected: unprotected)
            observation.value = .codeableConcept(value)
        case .bloodPressure(let members):
            let correlation = try sample.cast(to: HKCorrelation.self)
            observation.component = try members.map { try $0.component(in: correlation) }
        case .workout(let content):
            try content.apply(to: &observation, workout: try sample.cast(to: HKWorkout.self))
        case .stateOfMind(let content):
            try content.apply(to: &observation, reflection: try sample.cast(to: HKStateOfMind.self))
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuantityRead {
    /// `fraction`, where 1 means 100 %, stated in percent without multiplying in binary64.
    ///
    /// The fraction's shortest round-trip text is parsed back with its exponent raised by two: one correctly rounded
    /// conversion of the exact decimal product, so 0.282 becomes 28.2 rather than the 28.199999999999996 that
    /// `fraction * 100` yields. The quantity template then states the result as its own shortest round-trip decimal,
    /// which never has more significant digits than the fraction's text. A non-finite fraction yields NaN, which the
    /// template refuses as it refuses any other non-finite value; a finite fraction's text always parses.
    static func percent(ofFraction fraction: Double) -> Double {
        guard fraction.isFinite, let scaled = Double(String(groveFHIRPlainDecimal: fraction) + "e2") else {
            return .nan
        }
        return scaled
    }

    /// The value read from `sample`: a quantity in its unit or as a count, a fraction in percent, or a score.
    func value(of sample: HKSample) throws(HealthKitConversionError.ValueFailure) -> Double {
        switch self {
        case .unit(let binding): try sample.cast(to: HKQuantitySample.self).quantity.doubleValue(for: binding.unit)
        case .platformRate: try sample.cast(to: HKQuantitySample.self).quantity.doubleValue(for: .count())
        case .percent: Self.percent(ofFraction: try sample.cast(to: HKQuantitySample.self).quantity.doubleValue(for: .percent()))
        case .score: Double(try sample.cast(to: HKScoredAssessment.self).score)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BloodPressureMember {
    /// The component the member's reading in `correlation` becomes: the first sample of the member's type, read in
    /// the member's unit. A correlation without one misses the component.
    func component(in correlation: HKCorrelation) throws -> ObservationComponent {
        let reading = correlation.objects.lazy
            .compactMap { $0 as? HKQuantitySample }
            .first { $0.quantityType.identifier == quantityType.rawValue }
        guard let reading else {
            throw HealthKitConversionError.ValueFailure.requiredComponentMissing(component: component)
        }
        return try template.component(reading.quantity.doubleValue(for: binding.unit))
    }
}


extension HKSample {
    /// The sample as the class its plan reads; a sample of another class has an invalid shape.
    fileprivate func cast<Sample: HKSample>(to _: Sample.Type) throws(HealthKitConversionError.ValueFailure) -> Sample {
        guard let sample = self as? Sample else {
            throw .shapeInvalid
        }
        return sample
    }
}

#endif
