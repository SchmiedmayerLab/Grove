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


/// Which of a sample's metadata keys its conversion consumes; every other key is withheld and reported.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MetadataRule: Sendable {
    /// The rule of every source type today: the adapter's whole typed allowlist, whichever keys a path reads.
    static let allowlist = MetadataRule(consumedKeys: HealthKitMetadataField.keys)

    /// The keys the conversion reads and carries, or validates.
    let consumedKeys: Set<String>
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
    let field: HealthKitMetadataField
    /// How it is read.
    let reading: Reading
    /// The component's code.
    let code: CodeableConcept
    /// The component value of each admitted metadata value; a Boolean reads as 1 when true and 0 when false.
    let values: [Int: CodeableConcept]

    /// A component coded by the metadata key itself in the adapter's metadata-key CodeSystem.
    private init(field: HealthKitMetadataField, reading: Reading, display: String, vocabulary: MetadataVocabulary) {
        let code = Coding(code: field.key.asFHIRStringPrimitive(), display: display.asFHIRStringPrimitive(), system: Canonicals.healthKitMetadataKey)
        self.init(
            field: field,
            reading: reading,
            code: CodeableConcept(coding: [code]),
            values: vocabulary.codings.mapValues { CodeableConcept(coding: [$0]) }
        )
    }

    /// A component of the given code and values.
    private init(field: HealthKitMetadataField, reading: Reading, code: CodeableConcept, values: [Int: CodeableConcept]) {
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
        func value(_ code: String) throws(HealthKitContentDefect) -> CodeableConcept {
            guard let result = component.resultCodes.first(where: { $0.code == code }) else {
                throw HealthKitContentDefect("admits no cycleStart \(code)")
            }
            return CodeableConcept(coding: [Coding(result.code, display: result.display, system: system)])
        }
        let started = try value("cycle-start")
        let notStarted = try value("not-cycle-start")
        return MetadataComponentRule(
            field: .menstrualCycleStart,
            reading: .requiredBoolean,
            code: CodeableConcept(coding: [Coding(component.code, system: component.system)]),
            values: [1: started, 0: notStarted]
        )
    }

    /// The component the sample's metadata states, or `nil` when an optional value is absent.
    func component(_ metadata: HealthKitSampleMetadata) throws(HealthKitValueFailure) -> ObservationComponent? {
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
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitSampleMetadata {
    /// The sample's metadata, empty when it states none.
    let values: [String: Any]
    /// Whether `HKMetadataKeyWasUserEntered` is explicitly `true`.
    let wasUserEntered: Bool
    /// The keys the conversion withholds, sorted.
    let withheldKeys: [String]

    /// Whether the sample names a time zone at all, valid or not.
    var statesTimeZone: Bool {
        values[HKMetadataKeyTimeZone] != nil
    }

    /// The metadata of `sample`, withholding what `rule` does not consume.
    init(_ sample: HKSample, rule: MetadataRule) {
        values = sample.metadata ?? [:]
        wasUserEntered = (values[HKMetadataKeyWasUserEntered] as? Bool) == true
        withheldKeys = values.keys.filter { !rule.consumedKeys.contains($0) }.sorted()
    }

    /// The time zone the sample names, or `nil` when it names none; a name that is not a known zone is unsupported.
    func timeZone() throws(HealthKitValueFailure) -> TimeZone? {
        switch values[HKMetadataKeyTimeZone] {
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
}

#endif
