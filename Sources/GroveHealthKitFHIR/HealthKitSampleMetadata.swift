//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// Which of a sample's metadata keys its conversion consumes, and whose metadata belongs to its record; every other
/// key is withheld and reported.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MetadataRule: Sendable {
    /// The rule of every source type but blood pressure: the adapter's whole typed allowlist, whichever keys a path
    /// reads, over the sample's own metadata.
    static let allowlist = MetadataRule(consumedKeys: HealthKitConversionError.MetadataField.keys, readsMembers: false)
    /// Blood pressure's rule: the allowlist over the correlation's metadata and its members'. A food correlation's
    /// objects are records of their own, so no other rule reads members.
    static let bloodPressure = MetadataRule(consumedKeys: HealthKitConversionError.MetadataField.keys, readsMembers: true)

    /// The keys the conversion reads and carries, or validates.
    let consumedKeys: Set<String>
    /// Whether the metadata of the correlation's members (`HKCorrelation.objects`) belongs to the record: they state
    /// its time zone and manual entry where the correlation states none, and their keys are withheld like its own.
    let readsMembers: Bool
}


/// One metadata key a source type states as an Observation component: the component's code, and the coded value of
/// each metadata value it admits.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MetadataComponentRule: Sendable {
    /// How the metadata value is read.
    enum Reading: Sendable {
        /// A number, else nothing: an absent or non-numeric value states no component.
        case optionalInteger
        /// A number: an absent or non-numeric value is missing.
        case requiredInteger
        /// A Boolean: an absent value is missing, any other value unsupported.
        case requiredBoolean
    }

    /// `HKMetadataKeyHeartRateMotionContext`, stated when HealthKit states it.
    static let heartRateMotionContext = MetadataComponentRule(
        field: .heartRateMotionContext,
        reading: .optionalInteger,
        display: "Heart Rate Motion Context",
        vocabulary: .heartRateMotionContext
    )

    /// `HKMetadataKeyInsulinDeliveryReason`, which every insulin delivery states.
    static let insulinDeliveryReason = MetadataComponentRule(
        field: .insulinDeliveryReason,
        reading: .requiredInteger,
        display: "Insulin Delivery Reason",
        vocabulary: .insulinDeliveryReason
    )

    /// The metadata field read.
    let field: HealthKitConversionError.MetadataField
    /// How it is read.
    let reading: Reading
    /// The component's code.
    let code: CodeableConcept
    /// The component value of each admitted metadata value; a Boolean reads as 1 when true and 0 when false.
    let values: [Int: CodeableConcept]

    /// A component coded by the metadata key itself in the adapter's metadata-key CodeSystem.
    private init(field: HealthKitConversionError.MetadataField, reading: Reading, display: String, vocabulary: MetadataVocabulary) {
        let code = Coding(field.key, display: display, system: Canonicals.healthKitMetadataKey)
        self.init(
            field: field,
            reading: reading,
            code: CodeableConcept(coding: [code]),
            values: vocabulary.codings.mapValues { CodeableConcept(coding: [$0]) }
        )
    }

    /// A component of the given code and values.
    private init(field: HealthKitConversionError.MetadataField, reading: Reading, code: CodeableConcept, values: [Int: CodeableConcept]) {
        self.field = field
        self.reading = reading
        self.code = code
        self.values = values
    }

    /// `HKMetadataKeyMenstrualCycleStart`, which every menstrual flow states, as the contract's cycle-start component.
    static func menstrualCycleStart(_ contract: MeasurementContract) throws(HealthKitContentDefect) -> MetadataComponentRule {
        guard let component = contract.components.first(where: { $0.id == "cycleStart" }),
              let system = component.resultCodeSystem else {
            throw HealthKitContentDefect("states no coded cycleStart component")
        }
        let started = try component.resultCodes.concept("cycle-start", system: system)
        let notStarted = try component.resultCodes.concept("not-cycle-start", system: system)
        return MetadataComponentRule(
            field: .menstrualCycleStart,
            reading: .requiredBoolean,
            code: CodeableConcept(coding: [Coding(component.code, system: component.system)]),
            values: [1: started, 0: notStarted]
        )
    }

    /// The component the sample's metadata states, or `nil` when an optional value is absent.
    func component(_ metadata: HealthKitSampleMetadata) throws(HealthKitConversionError.ValueFailure) -> ObservationComponent? {
        let stated = metadata.values[field.key]
        let raw: Int
        switch reading {
        case .optionalInteger:
            guard let number = stated as? NSNumber else {
                return nil
            }
            raw = number.intValue
        case .requiredInteger:
            guard let number = stated as? NSNumber else {
                throw .requiredMetadataMissing(field)
            }
            raw = number.intValue
        case .requiredBoolean:
            switch stated {
            case nil:
                throw .requiredMetadataMissing(field)
            case let flag as Bool:
                raw = flag ? 1 : 0
            case .some:
                throw .unsupportedMetadataValue(field)
            }
        }
        guard let value = values[raw] else {
            throw .unsupportedMetadataValue(field)
        }
        return ObservationComponent(code: code, value: .codeableConcept(value))
    }
}


/// One sample's metadata, bridged from HealthKit once and read by every step of its conversion.
///
/// Building it never fails: each value is read, and refused, where the conversion reads it, so the failures keep
/// their order.
///
/// A blood-pressure correlation's record also holds its members' metadata: the correlation's own time zone and
/// manual-entry flag decide when it states them; otherwise the members state the zone every member naming one names,
/// and manual entry only when every member states it. Their keys outside the allowlist are withheld with the
/// correlation's.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitSampleMetadata {
    /// The sample's metadata, empty when it states none.
    let values: [String: Any]
    /// The metadata of each member of the correlation, in no particular order; empty unless the rule reads members.
    let memberValues: [[String: Any]]
    /// Whether the record states manual entry: `HKMetadataKeyWasUserEntered` is explicitly `true` on the sample or,
    /// when the sample states no Boolean, on each of its members, of which there is at least one.
    let wasUserEntered: Bool
    /// The keys the conversion withholds, the sample's and its members', each once and sorted.
    let withheldKeys: [String]

    /// Whether the effective time has a named zone: the sample names one, valid or not, or its members agree on one.
    var statesTimeZone: Bool {
        values[HKMetadataKeyTimeZone] != nil || (try? memberTimeZone()) != nil
    }

    /// The metadata of `sample`, withholding what `rule` does not consume.
    init(_ sample: HKSample, rule: MetadataRule) {
        values = sample.metadata ?? [:]
        let members = rule.readsMembers ? (sample as? HKCorrelation)?.objects : nil
        memberValues = members?.map { $0.metadata ?? [:] } ?? []
        wasUserEntered = switch values[HKMetadataKeyWasUserEntered] {
        case let stated as Bool:
            stated
        default:
            !memberValues.isEmpty && memberValues.allSatisfy { ($0[HKMetadataKeyWasUserEntered] as? Bool) == true }
        }
        let unconsumed = { (metadata: [String: Any]) in
            metadata.keys.filter { !rule.consumedKeys.contains($0) }
        }
        withheldKeys = Set(unconsumed(values) + memberValues.flatMap(unconsumed)).sorted()
    }

    /// The zone a name in `metadata` names, or `nil` when it names none; a name that is not a known zone is unsupported.
    private static func timeZone(in metadata: [String: Any]) throws(HealthKitConversionError.ValueFailure) -> TimeZone? {
        switch metadata[HKMetadataKeyTimeZone] {
        case nil:
            return nil
        case let identifier as String:
            guard let zone = TimeZone(identifier: identifier) else {
                throw .unsupportedMetadataValue(.timeZone)
            }
            return zone
        case .some:
            throw .unsupportedMetadataValue(.timeZone)
        }
    }

    /// The time zone the effective time is stated in: the sample's, else its members' agreed one, else `nil`.
    func timeZone() throws(HealthKitConversionError.ValueFailure) -> TimeZone? {
        guard values[HKMetadataKeyTimeZone] == nil else {
            return try Self.timeZone(in: values)
        }
        return try memberTimeZone()
    }

    /// The zone every member naming one names, by identifier, so an alias disagrees; `nil` when none names one or
    /// they disagree. Every member's name is checked, so the outcome does not depend on their order.
    private func memberTimeZone() throws(HealthKitConversionError.ValueFailure) -> TimeZone? {
        let zones = try memberValues.map { metadata throws(HealthKitConversionError.ValueFailure) in
            try Self.timeZone(in: metadata)
        }
        .compactMap(\.self)
        return Set(zones.map(\.identifier)).count == 1 ? zones.first : nil
    }
}

#endif
