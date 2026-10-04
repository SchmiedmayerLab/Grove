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


/// The metadata keys a source type's own content carries, and whether its record holds its correlation's members'
/// metadata. The keys every path can carry (the time zone, manual entry and the sync pair) are carried as the graph's
/// outputs show; every other key is withheld and reported.
@available(iOS 18, macOS 15, watchOS 11, *)
struct MetadataRule: Sendable {
    /// The rule of a type whose content reads no metadata key of its own.
    static let noContentKeys = MetadataRule(contentFields: [])

    /// The keys the type's content carries when stated, each read where the content reads it: whether protection was
    /// used, a metadata component, an ECG's algorithm version.
    let contentFields: [HealthKitConversionError.MetadataField]
    /// Whether the metadata of the correlation's members (`HKCorrelation.objects`) belongs to the record: they state
    /// its time zone and manual entry where the correlation states none. Only blood pressure's rule reads members; a
    /// food correlation's objects are records of their own.
    let readsMembers: Bool

    /// The rule of a type whose content carries `contentFields`, reading its members' metadata when `readsMembers`.
    init(contentFields: [HealthKitConversionError.MetadataField], readsMembers: Bool = false) {
        self.contentFields = contentFields
        self.readsMembers = readsMembers
    }
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
/// their order. Which keys the graph withholds is known once its outputs are drafted (``withheldKeys(in:)``).
///
/// A blood-pressure correlation's record also holds its members' metadata: the correlation's own time zone and
/// manual-entry flag decide when it states them; otherwise the members state the zone every member naming one names,
/// and manual entry only when every member states it.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitSampleMetadata {
    /// The sample's metadata, empty when it states none.
    let values: [String: Any]
    /// The metadata of each member of the correlation, in no particular order; empty unless the rule reads members.
    let memberValues: [[String: Any]]
    /// The metadata of each object the sample contains that states some: a correlation's objects, a workout's events
    /// and activities, and each activity's events. Only the withheld keys read it; a blood-pressure correlation's
    /// zone and manual entry read ``memberValues``.
    let containedValues: [[String: Any]]
    /// Whether the record states manual entry: `HKMetadataKeyWasUserEntered` is explicitly `true` on the sample or,
    /// when the sample states no Boolean, on each of its members, of which there is at least one.
    let wasUserEntered: Bool
    /// The keys the type's own content carries when stated.
    private let contentFields: [HealthKitConversionError.MetadataField]

    /// Whether the effective time has a named zone: the sample names one, valid or not, or its members agree on one.
    var statesTimeZone: Bool {
        values[HKMetadataKeyTimeZone] != nil || (try? memberTimeZone()) != nil
    }

    /// The metadata of `sample` under `rule`: the keys its type's content carries, and whether its members' metadata
    /// belongs to its record.
    init(_ sample: HKSample, rule: MetadataRule) {
        values = sample.metadata ?? [:]
        let members = rule.readsMembers ? (sample as? HKCorrelation)?.objects : nil
        memberValues = members?.map { $0.metadata ?? [:] } ?? []
        containedValues = Self.containedMetadata(of: sample)
        wasUserEntered = switch values[HKMetadataKeyWasUserEntered] {
        case let stated as Bool:
            stated
        default:
            !memberValues.isEmpty && memberValues.allSatisfy { ($0[HKMetadataKeyWasUserEntered] as? Bool) == true }
        }
        contentFields = rule.contentFields
    }

    /// The metadata of each object `sample` contains that states some; a sample of any other class contains none.
    private static func containedMetadata(of sample: HKSample) -> [[String: Any]] {
        switch sample {
        case let correlation as HKCorrelation:
            return correlation.objects.compactMap(\.metadata)
        case let workout as HKWorkout:
            let activities = workout.workoutActivities
            let events = (workout.workoutEvents ?? []) + activities.flatMap(\.workoutEvents)
            return events.compactMap(\.metadata) + activities.compactMap(\.metadata)
        default:
            return []
        }
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


// MARK: - Withheld keys

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitSampleMetadata {
    /// The record's metadata as its conversion reads it: the sample's own, plus, where a blood-pressure correlation
    /// states no such key, the zone its members agree on (by identifier, as the effective time names it) and manual
    /// entry when every member states it.
    private var recordValues: [String: Any] {
        guard !memberValues.isEmpty else {
            return values
        }
        var record = values
        if record[HKMetadataKeyTimeZone] == nil, let zone = try? memberTimeZone() {
            record[HKMetadataKeyTimeZone] = zone.identifier
        }
        if record[HKMetadataKeyWasUserEntered] == nil, wasUserEntered {
            record[HKMetadataKeyWasUserEntered] = true
        }
        return record
    }

    /// Every key of `record` that `carried` lacks, and every key a `contained` object states unless the record carries
    /// the equal value under it, each once and sorted. Manual entry stated `false` is never withheld, as the guide
    /// represents it by omission (healthkit mapping.md: "omission means the converter does not know the capture mode").
    static func withheldKeys(record: [String: Any], contained: [[String: Any]], carried: [String: Any]) -> [String] {
        var withheld = Set(record.keys.filter { carried[$0] == nil })
        for metadata in contained {
            for (key, value) in metadata where !isCarried(key, value: value, carried: carried) {
                withheld.insert(key)
            }
        }
        return withheld.sorted()
    }

    /// Whether a contained object's `value` for `key` is carried: manual entry explicitly `false`, which every path
    /// represents by omission, or the very value the record carries under the key.
    private static func isCarried(_ key: String, value: Any, carried: [String: Any]) -> Bool {
        if key == HKMetadataKeyWasUserEntered, (value as? Bool) == false {
            return true
        }
        return (carried[key] as? NSObject)?.isEqual(value) == true
    }

    /// The keys the sample, or an object it contains, carried that the graph's `outputs` do not represent, each once and
    /// sorted. The outputs are final but for the envelope: they state the record's entry method and writer record.
    ///
    /// A key is carried only through the representation the guide publishes for it, on an output that has that
    /// representation: "There is no generic metadata extension." (healthkit mapping.md, Supported HealthKit metadata)
    /// A blood-pressure member's zone or manual entry that the record takes, because the correlation states none,
    /// is carried as the record's own would be.
    func withheldKeys(in outputs: [ExchangeOutputDraft]) -> [String] {
        guard !values.isEmpty || !containedValues.isEmpty else {
            return []
        }
        let carried = recordValues.filter { key, value in
            carries(key, value: value, in: outputs)
        }
        return Self.withheldKeys(record: values, contained: containedValues, carried: carried)
    }

    /// Whether `outputs` represent the sample's `value` for `key`:
    /// - the sync pair as the writer-record identity and version, which only an Observation primary states, and only for
    ///   an attributable writer (healthkit profiles.fsh, healthkit-writer-record-1);
    /// - manual entry, `false` by omission and `true` as an Observation's manual-entry recording method;
    /// - the time zone as a `timezone` extension on an Observation's effective time (mapping.md: "Map an available
    ///   IANA time-zone name to the standard FHIR `timezone` extension"), which a document has no element for;
    /// - a key of the type's own content when its reader accepts the value.
    private func carries(_ key: String, value: Any, in outputs: [ExchangeOutputDraft]) -> Bool {
        switch key {
        case HKMetadataKeySyncIdentifier, HKMetadataKeySyncVersion:
            return outputs.first?.writerRecord != nil
        case HKMetadataKeyWasUserEntered:
            guard let entered = value as? Bool else {
                return false
            }
            return !entered || outputs.contains(where: \.statesManualEntry)
        case HKMetadataKeyTimeZone:
            return outputs.contains(where: \.namesEffectiveZone)
        default:
            return contentFields.contains { $0.key == key && $0.readerAccepts(value) }
        }
    }
}


extension ExchangeOutputDraft {
    /// Whether the output is an Observation stating the manual-entry recording method.
    fileprivate var statesManualEntry: Bool {
        if case .observation = resource { links.contains(.manualEntry) && wasUserEntered } else { false }
    }

    /// Whether the output is an Observation naming the zone of its effective time in a `timezone` extension.
    fileprivate var namesEffectiveZone: Bool {
        guard case .observation(let observation) = resource else {
            return false
        }
        return switch observation.effective {
        case .dateTime(let instant): instant.namesZone
        case .period(let period): period.start?.namesZone == true || period.end?.namesZone == true
        case .instant, .timing, nil: false
        }
    }
}


extension FHIRPrimitive<DateTime> {
    /// Whether the date-time names its zone in a `timezone` extension.
    fileprivate var namesZone: Bool {
        self.extension?.contains { $0.url == Canonicals.timezone } == true
    }
}

#endif
