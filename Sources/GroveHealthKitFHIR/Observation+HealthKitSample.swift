//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The projection reads top-down from the entry point through measurement, envelope and values.

// swiftlint:disable file_length

#if canImport(HealthKit)

import Foundation
package import GroveFHIRContract
package import HealthKit
package import ModelsR4


/// Why a Grove observation cannot become a HealthKit sample; every case reports one registry code.
package enum HealthKitSampleProjectionError: Error, Equatable, Sendable {
    /// The observation's code names no Grove measurement.
    case measurementUnknown(system: String, code: String)
    /// The measurement has no single HealthKit type the projection can write: none or several read it, its value is
    /// one the projection does not invert (a workout, a reflection or a score), or the observation's HealthKit lineage
    /// names another source type.
    case measurementNotMappable(id: String)
    case unitNotMappable(code: String)
    case valueMissing(id: String)
    /// The value, or a metadata component's value, names no value of the HealthKit type: no category value or several
    /// state it, it is none of the codes the component admits, or a duration disagrees with the effective Period.
    case valueNotMappable(id: String)
    case componentMissing(id: String, code: String)
    /// The observation states no effective, or its instant does not parse.
    case effectiveMissing(id: String)
    /// The effective has a datatype the measurement's profile does not admit: a Period on an instant-only
    /// measurement, an instant on a Period-only one, or an instant or Timing anywhere.
    case effectiveTypeNotAdmitted(id: String)
    /// The effective Period cannot be a HealthKit sample's interval: it lacks a start or an end, an endpoint does not
    /// parse, it ends before it starts, it has zero width where the measurement requires a non-zero Period, or its
    /// duration is outside what HealthKit allows for the sample type.
    case effectivePeriodInvalid(id: String)

    package var diagnostic: ProducerDiagnostic {
        let (rule, location): (ExchangeGraphRule, String) = switch self {
        case .measurementUnknown, .measurementNotMappable: (.mobileInputUnsupportedSourceType, "Observation.code")
        case .unitNotMappable: (.mobileOutputFixedQuantityUnit, "Observation.valueQuantity.code")
        case .valueMissing: (.mobileInputValueShapeInvalid, "Observation.value")
        case .valueNotMappable: (.mobileInputUnsupportedSourceValue, "Observation.value")
        case .componentMissing: (.mobileInputRequiredComponentMissing, "Observation.component")
        case .effectiveMissing: (.mobileInputEffectivePeriodInvalid, "Observation.effective")
        case .effectiveTypeNotAdmitted: (.mobileInputEffectivePeriodInvalid, "Observation.effective[x]")
        case .effectivePeriodInvalid: (.mobileInputEffectivePeriodInvalid, "Observation.effectivePeriod")
        }
        return ProducerDiagnostic(code: rule.rawValue, reason: rule.reason, location: location, severity: rule.severity)
    }
}


/// One entry of a graph that could not be projected back into a sample.
package struct HealthKitSampleProjectionFailure: Error, Sendable {
    package let fullURL: FHIRPrimitive<FHIRURI>
    package let error: HealthKitSampleProjectionError
}


@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitSampleProjection {
    /// The interval and metadata every projected sample shares.
    struct SampleEnvelope {
        let start: Date
        let end: Date
        let metadata: [String: Any]
    }

    /// When an observation's effective says its sample happened, and the zone of the start's offset.
    private struct SampleInterval {
        let start: Date
        let end: Date
        let zone: TimeZone?
    }

    /// The source type a measurement lands on and the plan that reads it.
    struct Projection {
        /// The source type's identifier.
        let sourceType: String
        /// The Observation plan of the source type.
        let plan: ObservationPlan
    }

    /// The system and code of a coding.
    struct SystemCode: Hashable {
        /// The code system.
        let system: String
        /// The code.
        let code: String
    }

    /// Every generated measurement by its code's system and code, the first catalog stating one winning. Body-mass
    /// index, which no catalog lists, is unknown.
    static let measurements: [SystemCode: MeasurementContract] = Dictionary(
        (MeasurementCatalog.all + HealthKitMeasurementCatalog.all).map { (SystemCode(system: $0.code.system, code: $0.code.code), $0) }
    ) { first, _ in first }

    /// The source type each measurement lands on: the one type whose Observation plan reads the measurement with a value
    /// the projection inverts, a quantity (in its contract's unit, as a percentage or as a platform rate), a category
    /// value, a category duration, protection, or the blood-pressure panel. A measurement several such types read, or none, has none, so it refuses rather than
    /// guessing.
    static let projections: [String: Projection] = {
        let readers = HealthKitContentPlan.all.compactMap { plan -> (String, [Projection])? in
            guard case .observation(let content) = plan.route, inverts(content.value),
                  let measurement = plan.entry.measurements.first else {
                return nil
            }
            return (measurement.id, [Projection(sourceType: plan.sourceType.rawValue, plan: content)])
        }
        return Dictionary(readers, uniquingKeysWith: +).compactMapValues { $0.count == 1 ? $0[0] : nil }
    }()

    /// The one sample `observation` describes, read from the content plans: its code names the measurement, the
    /// measurement the source type whose plan reads it, and the plan how the value becomes the sample's: a quantity as
    /// the plan reads it, a category value from the plan's coded values, and a blood-pressure panel a correlation of the
    /// plan's members. A metadata component the plan states becomes its metadata key.
    static func sample(of observation: ModelsR4.Observation, syncIdentifier: String?) throws(HealthKitSampleProjectionError) -> HKSample {
        let coding = observation.code.coding?.first
        let system = coding?.system?.value?.url.absoluteString ?? ""
        let code = coding?.code?.value?.string ?? ""
        guard let contract = measurements[SystemCode(system: system, code: code)] else {
            throw .measurementUnknown(system: system, code: code)
        }
        let projection = try projection(of: observation, contract: contract)
        switch projection.plan.value {
        case .bloodPressure(let members):
            let type = HKCorrelationType(HKCorrelationTypeIdentifier(rawValue: projection.sourceType))
            let envelope = try envelope(of: observation, contract: contract, sampleType: type, syncIdentifier: syncIdentifier)
            return try correlation(of: observation, members: members, contract: contract, envelope: envelope)
        case .quantity(_, let read):
            let type = HKQuantityType(HKQuantityTypeIdentifier(rawValue: projection.sourceType))
            let envelope = try envelope(of: observation, contract: contract, sampleType: type, syncIdentifier: syncIdentifier)
            guard case .quantity(let quantity)? = observation.value else {
                throw .valueMissing(id: contract.id)
            }
            return HKQuantitySample(
                type: type,
                quantity: try healthKitQuantity(quantity, contract: contract.quantity, read: read, measurementID: contract.id),
                start: envelope.start,
                end: envelope.end,
                metadata: try metadata(of: observation, envelope: envelope, rule: projection.plan.metadataComponent, contract: contract)
            )
        case .coded, .duration, .protection:
            let type = HKCategoryType(HKCategoryTypeIdentifier(rawValue: projection.sourceType))
            let envelope = try envelope(of: observation, contract: contract, sampleType: type, syncIdentifier: syncIdentifier)
            return try category(of: observation, type: type, plan: projection.plan, contract: contract, envelope: envelope)
        case .workout, .stateOfMind:
            throw .measurementNotMappable(id: contract.id)
        }
    }

    /// Whether the projection inverts a value rule.
    private static func inverts(_ rule: ValueRule) -> Bool {
        switch rule {
        case .quantity(_, .unit), .quantity(_, .percent), .quantity(_, .platformRate), .coded, .duration, .protection, .bloodPressure: true
        case .quantity(_, .score), .workout, .stateOfMind: false
        }
    }

    /// The source type `observation` lands on: its measurement's, unless the observation's HealthKit lineage names
    /// another source type, as an ECG's average heart rate does. An observation without lineage keeps its
    /// measurement's.
    private static func projection(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> Projection {
        guard let projection = projections[contract.id],
              sourceTypeLineage(of: observation).map({ $0 == projection.sourceType }) ?? true else {
            throw .measurementNotMappable(id: contract.id)
        }
        return projection
    }

    /// The correlation a blood-pressure panel describes: one sample per member of the plan, in its order, each from the
    /// panel's component the member's template codes, read in the member's unit.
    private static func correlation(
        of observation: ModelsR4.Observation,
        members: [BloodPressureMember],
        contract: MeasurementContract,
        envelope: SampleEnvelope
    ) throws(HealthKitSampleProjectionError) -> HKCorrelation {
        let samples = try members.map { member throws(HealthKitSampleProjectionError) -> HKSample in
            let declared = contract.components.first { $0.id == member.component }
            let stated = observation.component?.first { states($0.code, member.template.code) }
            guard let declared, let stated, case .quantity(let quantity) = stated.value else {
                throw .componentMissing(id: contract.id, code: declared?.code ?? member.component)
            }
            return HKQuantitySample(
                type: HKQuantityType(member.quantityType),
                quantity: try healthKitQuantity(quantity, contract: declared.quantity, read: .unit(member.binding), measurementID: contract.id),
                start: envelope.start,
                end: envelope.end
            )
        }
        return HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: envelope.start,
            end: envelope.end,
            objects: Set(samples),
            metadata: envelope.metadata
        )
    }

    /// The interval and metadata the observation states: its effective interval (in the proleptic Gregorian calendar,
    /// as the converter states it) and zone, within the duration HealthKit allows for `sampleType`, manual entry, and
    /// the sync identifier and version a re-projected reading replaces its earlier sample by.
    private static func envelope(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract,
        sampleType: HKSampleType,
        syncIdentifier: String?
    ) throws(HealthKitSampleProjectionError) -> SampleEnvelope {
        let interval = try interval(of: observation, contract: contract)
        let duration = interval.end.timeIntervalSince(interval.start)
        // The allowed-duration getters raise for a type without that restriction, so the flags are read first.
        guard !(sampleType.isMinimumDurationRestricted && duration < sampleType.minimumAllowedDuration),
              !(sampleType.isMaximumDurationRestricted && duration > sampleType.maximumAllowedDuration) else {
            throw .effectivePeriodInvalid(id: contract.id)
        }
        var metadata: [String: Any] = [:]
        if let zone = interval.zone {
            metadata[HKMetadataKeyTimeZone] = zone.identifier
        }
        if isManualEntry(observation) {
            metadata[HKMetadataKeyWasUserEntered] = true
        }
        if let syncIdentifier = syncIdentifier ?? sourceOutputIdentity(of: observation) {
            metadata[HKMetadataKeySyncIdentifier] = syncIdentifier
            metadata[HKMetadataKeySyncVersion] = writerRecordVersion(of: observation)
                ?? (observation.status.value == .amended ? 2 : 1)
        }
        return SampleEnvelope(start: interval.start, end: interval.end, metadata: metadata)
    }

    /// The interval the observation's effective states where the measurement's profile admits its datatype: an
    /// instant as a zero-width interval, a Period as its endpoints when they are an interval the profile admits.
    /// HealthKit needs an end, so an open Period refuses rather than guessing one.
    private static func interval(
        of observation: ModelsR4.Observation,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> SampleInterval {
        let rule = EffectiveRule(contract)
        switch observation.effective {
        case nil:
            throw .effectiveMissing(id: contract.id)
        case .dateTime(let effective) where rule == .instant || rule == .instantOrInterval:
            guard let instant = instant(effective) else {
                throw .effectiveMissing(id: contract.id)
            }
            return SampleInterval(start: instant.date, end: instant.date, zone: instant.zone)
        case .period(let period) where rule != .instant:
            // A pair reversed by less than a millisecond can round to one wire millisecond; HealthKit raises on it.
            guard let start = instant(period.start), let end = instant(period.end), start.date <= end.date,
                  (try? rule.admitsPeriod(from: start.date, to: end.date)) == true else {
                throw .effectivePeriodInvalid(id: contract.id)
            }
            return SampleInterval(start: start.date, end: end.date, zone: start.zone)
        default:
            throw .effectiveTypeNotAdmitted(id: contract.id)
        }
    }

    /// The instant a date-time states and the zone of its offset, or `nil` when it states none or one HealthKit cannot
    /// hold: from `Date.distantFuture` (4001-01-01T00:00:00Z) on, `HKSample` raises an uncatchable exception.
    private static func instant(_ dateTime: FHIRPrimitive<DateTime>?) -> (date: Date, zone: TimeZone?)? {
        guard let value = dateTime?.value, let date = HealthKitEffectiveTime.instant(of: value), date < .distantFuture else {
            return nil
        }
        return (date, value.timeZone)
    }

    /// The source type the observation's `healthkit-source-type` extension names, if it states one.
    private static func sourceTypeLineage(of observation: ModelsR4.Observation) -> String? {
        let marker = observation.extension?.first { $0.url == Canonicals.healthKitSourceTypeExtension }
        guard case .code(let code)? = marker?.value else {
            return nil
        }
        return code.value?.string
    }

    private static func writerRecordVersion(of observation: ModelsR4.Observation) -> Int? {
        let marker = observation.extension?.first { $0.url == Canonicals.writerRecordVersion }
        guard case .string(let value)? = marker?.value,
              let version = value.value?.string else {
            return nil
        }
        return Int(version)
    }

    private static func sourceOutputIdentity(of observation: ModelsR4.Observation) -> String? {
        observation.identifier?.first { identifier in
            identifier.type?.coding?.contains {
                $0.system == Canonicals.identifierRoleCodeSystem
                    && $0.code?.value?.string == GroveIdentifierRole.sourceOutput.rawValue
            } == true
        }?.value?.value?.string
    }

    private static func isManualEntry(_ observation: ModelsR4.Observation) -> Bool {
        let url = Canonicals.recordingMethod.value?.url.absoluteString
        return observation.extension?.contains { marker in
            guard marker.url.value?.url.absoluteString == url,
                  case .coding(let coding)? = marker.value else {
                return false
            }
            return coding.code?.value?.string == "manual-entry"
        } ?? false
    }

    /// The value under the unit its measurement contract fixes, read back as the plan reads it.
    ///
    /// The stated system and code are checked against the contract rather than looked up: a code
    /// from another dimension would otherwise mint an HKQuantity that `HKQuantitySample` rejects
    /// with an uncatchable exception. The value is read from the decimal's text, as `NSDecimalNumber`
    /// reads 1.32 as 1.3199999999999998.
    private static func healthKitQuantity(
        _ quantity: Quantity,
        contract: QuantityContract?,
        read: QuantityRead,
        measurementID: String
    ) throws(HealthKitSampleProjectionError) -> HKQuantity {
        guard let decimal = quantity.value?.value?.decimal else {
            throw HealthKitSampleProjectionError.valueMissing(id: measurementID)
        }
        let code = quantity.code?.value?.string ?? ""
        guard let contract,
              quantity.system?.value?.url.absoluteString == contract.system,
              code == contract.code else {
            throw HealthKitSampleProjectionError.unitNotMappable(code: code)
        }
        guard let healthKitQuantity = read.quantity(stating: decimal.description) else {
            throw HealthKitSampleProjectionError.valueMissing(id: measurementID)
        }
        return healthKitQuantity
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitSampleProjection {
    /// One millisecond, the most that rounding each endpoint to the nearest millisecond moves a Period's length, and a
    /// nanosecond for the binary64 arithmetic.
    private static let durationTolerance = 0.001 + 1e-9

    /// The category sample a plan's category value describes: the raw value of the coded value the observation states,
    /// or `HKCategoryValue.notApplicable` for a duration, whose interval is the effective Period its stated length must
    /// agree with, and for protection, which becomes `HKMetadataKeySexualActivityProtectionUsed` unless unknown.
    static func category(
        of observation: ModelsR4.Observation,
        type: HKCategoryType,
        plan: ObservationPlan,
        contract: MeasurementContract,
        envelope: SampleEnvelope
    ) throws(HealthKitSampleProjectionError) -> HKCategorySample {
        let value: Int
        var protection: [String: Any] = [:]
        switch plan.value {
        case .coded(let values, _):
            value = try categoryValue(of: observation, values: values, contract: contract)
        case .duration(_, let secondsPerUnit):
            try requireDuration(of: observation, secondsPerUnit: secondsPerUnit, envelope: envelope, contract: contract)
            value = HKCategoryValue.notApplicable.rawValue
        case let .protection(unknown, protected, unprotected):
            protection = try protectionMetadata(of: observation, unknown: unknown, protected: protected, unprotected: unprotected, contract: contract)
            value = HKCategoryValue.notApplicable.rawValue
        case .quantity, .bloodPressure, .workout, .stateOfMind:
            throw .measurementNotMappable(id: contract.id)
        }
        let metadata = try metadata(of: observation, envelope: envelope, rule: plan.metadataComponent, contract: contract)
        return HKCategorySample(
            type: type,
            value: value,
            start: envelope.start,
            end: envelope.end,
            metadata: metadata.merging(protection) { _, protection in protection }
        )
    }

    /// Requires a duration's value to be a quantity in its contract's unit that agrees with the effective Period. The
    /// exporter states the sample's exact length but rounds each endpoint to the millisecond, so the two differ by up to
    /// ``durationTolerance``; the Period, which HealthKit keeps as the sample's interval, wins.
    private static func requireDuration(
        of observation: ModelsR4.Observation,
        secondsPerUnit: Double,
        envelope: SampleEnvelope,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) {
        guard case .quantity(let quantity)? = observation.value, let decimal = quantity.value?.value?.decimal else {
            throw .valueMissing(id: contract.id)
        }
        let code = quantity.code?.value?.string ?? ""
        guard quantity.system?.value?.url.absoluteString == contract.quantity?.system, code == contract.quantity?.code else {
            throw .unitNotMappable(code: code)
        }
        guard let stated = Double(decimal.description),
              abs(stated * secondsPerUnit - envelope.end.timeIntervalSince(envelope.start)) <= durationTolerance else {
            throw .valueNotMappable(id: contract.id)
        }
    }

    /// `HKMetadataKeySexualActivityProtectionUsed` as the stated value says, or nothing when it is unknown.
    private static func protectionMetadata(
        of observation: ModelsR4.Observation,
        unknown: CodeableConcept,
        protected: CodeableConcept,
        unprotected: CodeableConcept,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> [String: Any] {
        guard case .codeableConcept(let stated)? = observation.value else {
            throw .valueMissing(id: contract.id)
        }
        let key = HealthKitConversionError.MetadataField.sexualActivityProtectionUsed.key
        let candidates: [(key: [String: Any], concept: CodeableConcept)] = [([key: true], protected), ([key: false], unprotected), ([:], unknown)]
        guard let metadata = onlyMatch(stated, among: candidates) else {
            throw .valueNotMappable(id: contract.id)
        }
        return metadata
    }

    /// The raw value of the one coded value the observation states, with the value's notification occurrence among its
    /// components where it has one; no such value, or several, refuse.
    private static func categoryValue(
        of observation: ModelsR4.Observation,
        values: [Int: CodedValue],
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> Int {
        guard case .codeableConcept(let stated)? = observation.value else {
            throw .valueMissing(id: contract.id)
        }
        let matches = values.filter { _, coded in
            guard states(stated, coded.value) else {
                return false
            }
            guard let occurrence = coded.occurrence else {
                return true
            }
            return observation.component?.contains { component in
                guard states(component.code, occurrence.code),
                      case .codeableConcept(let statedOccurrence)? = component.value,
                      case .codeableConcept(let expected)? = occurrence.value else {
                    return false
                }
                return states(statedOccurrence, expected)
            } ?? false
        }
        guard matches.count == 1, let raw = matches.first?.key else {
            throw .valueNotMappable(id: contract.id)
        }
        return raw
    }

    /// The envelope's metadata and the metadata key a plan states as a component, read back from the component the
    /// observation states under the rule's code through the rule's values: a Boolean where the rule reads one, else
    /// the number. A required component the observation does not state is missing; an optional one is left out.
    static func metadata(
        of observation: ModelsR4.Observation,
        envelope: SampleEnvelope,
        rule: MetadataComponentRule?,
        contract: MeasurementContract
    ) throws(HealthKitSampleProjectionError) -> [String: Any] {
        var metadata = envelope.metadata
        guard let rule else {
            return metadata
        }
        guard let component = observation.component?.first(where: { states($0.code, rule.code) }) else {
            guard rule.reading == .optionalInteger else {
                throw .componentMissing(id: contract.id, code: codes(of: rule.code).first?.code ?? "")
            }
            return metadata
        }
        guard case .codeableConcept(let stated)? = component.value,
              let raw = onlyMatch(stated, among: rule.values.map { ($0.key, $0.value) }) else {
            throw .valueNotMappable(id: contract.id)
        }
        metadata[rule.field.key] = rule.reading == .requiredBoolean ? raw == 1 : raw
        return metadata
    }

    /// Whether `stated` states `concept` without contradicting it: it carries the concept's first coding, and in every
    /// system the concept codes, no other code. A coded value Grove states carries its shared coding first, then its
    /// HealthKit case, which a consumer may drop; a coding in a system the concept does not code is a translation.
    private static func states(_ stated: CodeableConcept, _ concept: CodeableConcept) -> Bool {
        let statedCodes = codes(of: stated)
        let conceptCodes = codes(of: concept)
        guard let first = conceptCodes.first, statedCodes.contains(first) else {
            return false
        }
        return conceptCodes.allSatisfy { coding in
            statedCodes.allSatisfy { $0.system != coding.system || $0 == coding }
        }
    }

    /// The key of the one candidate `stated` states; none, or several, is no key.
    private static func onlyMatch<Key>(_ stated: CodeableConcept, among candidates: [(key: Key, concept: CodeableConcept)]) -> Key? {
        let matches = candidates.filter { states(stated, $0.concept) }
        return matches.count == 1 ? matches[0].key : nil
    }

    /// The system and code of each coding a concept states.
    private static func codes(of concept: CodeableConcept) -> [SystemCode] {
        (concept.coding ?? []).map { coding in
            SystemCode(system: coding.system?.value?.url.absoluteString ?? "", code: coding.code?.value?.string ?? "")
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Observation {
    /// The one sample this observation describes.
    ///
    /// This is the reverse of the exporter's observation assembly, derived from the same content
    /// plans: the code selects the measurement contract, the contract selects the one HealthKit
    /// type whose plan reads it, and the plan reads the value back. A quantity is read in the
    /// published unit binding of its UCUM unit; a category value is the one HealthKit value whose
    /// coding the observation states, its first coding alone sufficing, together with a
    /// notification's occurrence component; a duration's sample spans the effective Period; and a
    /// blood-pressure panel becomes a correlation of its members. A percentage becomes the fraction
    /// HealthKit keeps, its decimal shifted two places in one correctly rounded conversion. A
    /// measurement read by several HealthKit types, or by none, refuses rather than guessing, and so
    /// do workouts, reflections, scores, and an observation whose HealthKit lineage names another
    /// source type.
    ///
    /// An `effectiveDateTime` becomes an instant sample and an `effectivePeriod` the sample's start and
    /// end, each only where the measurement's profile admits that datatype and within the duration
    /// HealthKit allows for the type; anything else refuses with a typed error.
    ///
    /// The effective time is read in the proleptic Gregorian calendar the converter states it in,
    /// so a reading from before the 1582 calendar reform lands on its own instant. An instant
    /// HealthKit cannot hold, from 4001-01-01T00:00:00Z (`Date.distantFuture`) on, refuses with
    /// ``HealthKitSampleProjectionError/effectiveMissing(id:)``, and a Period bound there with
    /// ``HealthKitSampleProjectionError/effectivePeriodInvalid(id:)``.
    ///
    /// A manual-entry recording method becomes `HKMetadataKeyWasUserEntered`, a metadata
    /// component the measurement states (a menstrual flow's cycle start, an insulin delivery's
    /// reason, a heart rate's motion context) its metadata key, the effective
    /// start's zone `HKMetadataKeyTimeZone`, and the minted source-output identity
    /// `HKMetadataKeySyncIdentifier`, so a reading re-projected from any exchange graph replaces
    /// the earlier sample instead of duplicating it.
    ///
    /// Not used by any clients but used and needed by tests, hence package visibility rather than public.
    ///
    /// - Parameter syncIdentifier: A stable per-reading discriminator in place of the source-output identity.
    package func healthKitSample(syncIdentifier: String? = nil) throws(HealthKitSampleProjectionError) -> HKSample {
        try HealthKitSampleProjection.sample(of: self, syncIdentifier: syncIdentifier)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ExchangeGraph {
    /// Every Observation of the graph as the sample it describes, with a typed failure for each that refuses.
    package func healthKitSamples() -> ConversionBatch<HKSample, HealthKitSampleProjectionFailure> {
        var samples: [HKSample] = []
        var failures: [HealthKitSampleProjectionFailure] = []
        for entry in bundle.entry ?? [] {
            guard case .observation(let observation)? = entry.resource, let fullURL = entry.fullUrl else {
                continue
            }
            do {
                samples.append(try observation.healthKitSample())
            } catch {
                failures.append(HealthKitSampleProjectionFailure(fullURL: fullURL, error: error))
            }
        }
        return ConversionBatch(conversions: samples, failures: failures)
    }
}

#endif
