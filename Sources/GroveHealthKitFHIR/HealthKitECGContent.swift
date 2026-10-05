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


/// The parts of an ECG's two Observations that every ECG shares, compiled once from the generated ECG claim, and the
/// builders that complete them from one ECG record.
///
/// A record converts in three steps: ``evidence(_:voltages:metadata:)`` reads and validates the record,
/// ``validatedSymptoms(_:status:)`` checks its symptoms (the assembly then converts each symptom as a graph of its
/// own), and ``outputs(_:symptoms:)`` builds the waveform and its average heart rate. Each check is its own statement,
/// so a record with several faults is refused for the first one checked, in this order: the zone; the lead's voltages,
/// their count, offsets, period, sampling frequency and finiteness; the symptoms status, then the symptoms; the ECG's
/// end not before its start; the effective Period (the offsets' order, then its end and start instants); the source
/// period's end and start instants; the classification; the algorithm version; the average heart rate.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitECGContent: Sendable {
    /// An ECG record read once and validated: what the outputs state beside the sample's own facts.
    struct Evidence {
        /// The ECG.
        let electrocardiogram: HKElectrocardiogram
        /// The zone its instants are stated in: the one its metadata names, else UTC.
        let zone: TimeZone
        /// Its validated voltages.
        let waveform: Waveform
        /// The algorithm version its metadata states, if any.
        let algorithmVersion: Int?
        /// The ECG's metadata, bridged once: the graph's source facts read it too.
        let metadata: HealthKitSampleMetadata
    }

    /// An ECG's validated voltages: offsets that rise by one exact uniform period from the first to the last, and
    /// every voltage finite.
    struct Waveform: Sendable {
        /// The first voltage's offset from the ECG's start, in seconds, the exact decimal its shortest text states.
        let firstOffset: Decimal
        /// The last voltage's offset, in seconds.
        let lastOffset: Decimal
        /// The period between voltages, in milliseconds.
        let period: Decimal
        /// The voltages in the claim's unit, as SampledData data.
        let data: String
    }

    /// The ECG's own metadata: its algorithm version, which the waveform states as its method.
    static let metadataRule = MetadataRule(contentFields: [.appleECGAlgorithmVersion])

    /// The waveform's output, which links everything.
    let waveformSlot: HealthKitOutputSlot
    /// The average heart rate's output, derived from the waveform.
    let averageHeartRateSlot: HealthKitOutputSlot
    /// The waveform Observation before its effective time, ECG extensions, interpretation, method, voltages and members.
    let waveformSkeleton: Observation
    /// The code of the waveform's voltage component: the lead the claim reads.
    let lead: CodeableConcept
    /// The origin of the voltage SampledData: zero in the claim's voltage unit.
    let voltageOrigin: Quantity
    /// The HealthKit unit of the claim's voltage unit, which the voltages are read in.
    let voltageUnit: HKUnit
    /// The interpretation of each classification the claim admits.
    let classifications: [HKElectrocardiogram.Classification: CodeableConcept]
    /// The method of each algorithm version the claim admits.
    let algorithmVersions: [Int: CodeableConcept]
    /// The average heart rate's Observation before its effective time and value.
    let averageHeartRateSkeleton: Observation
    /// The average heart rate's quantity, in its measurement's unit.
    let averageHeartRateQuantity: QuantityTemplate
    /// The HealthKit unit of that measurement's unit, which the ECG's average heart rate is read in.
    let averageHeartRateUnit: HKUnit

    /// The content of the ECG claim for the ECG source type.
    init(sourceType: HealthKitSourceType) throws(HealthKitContentDefect) {
        let claim = HealthKitElectrocardiogramClaim.self
        let measurement = claim.averageHeartRateMeasurement
        guard let heartRate = measurement.quantity else {
            throw HealthKitContentDefect("the average heart rate's measurement \(measurement.id) states no quantity")
        }
        waveformSlot = .primary(role: claim.waveform.role, discriminator: claim.waveform.discriminator)
        averageHeartRateSlot = .derived(role: claim.averageHeartRate.role, discriminator: claim.averageHeartRate.discriminator)
        waveformSkeleton = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [Coding(claim.waveformCode)]),
            sourceType: sourceType,
            profiles: claim.waveform.profiles
        )
        lead = CodeableConcept(coding: [Coding(claim.leadCode)])
        var origin = QuantityTemplate(claim.voltageQuantity).empty
        origin.value = FHIRPrimitive(FHIRDecimal(0))
        voltageOrigin = origin
        voltageUnit = try claim.voltageQuantity.binding().unit
        classifications = claim.classificationCodes.mapValues { CodeableConcept(coding: [Coding($0, system: claim.classificationSystem)]) }
        algorithmVersions = claim.algorithmVersionCodes.mapValues { CodeableConcept(coding: [Coding($0, system: claim.algorithmVersionSystem)]) }
        averageHeartRateSkeleton = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [Coding(claim.averageHeartRateCode)]),
            sourceType: sourceType,
            profiles: claim.averageHeartRate.profiles,
            category: HealthKitContentRules.category(of: measurement)
        )
        averageHeartRateQuantity = QuantityTemplate(heartRate)
        averageHeartRateUnit = try heartRate.binding().unit
    }

    /// An ECG's correlated symptoms in the order the waveform references them, by type and then lowercase UUID: as
    /// many as its symptoms status says (some when present, none otherwise), each of a type the claim admits, each
    /// sample once. Each symptom's value is checked when it converts as its own graph.
    static func validatedSymptoms(
        _ symptoms: [HKCategorySample],
        status: HKElectrocardiogram.SymptomsStatus
    ) throws(HealthKitConversionError) -> [HKCategorySample] {
        guard HealthKitElectrocardiogramClaim.symptomsStatusCodes[status] != nil else {
            throw .ecgEvidence(.unsupportedSymptomsStatus(status.rawValue))
        }
        guard status != .present || !symptoms.isEmpty else {
            throw .ecgEvidence(.symptomsRequired)
        }
        guard status == .present || symptoms.isEmpty else {
            throw .ecgEvidence(.unexpectedSymptoms)
        }
        var seen: Set<UUID> = []
        for symptom in symptoms {
            let identifier = symptom.categoryType.identifier
            guard let type = HealthKitSourceType(rawValue: identifier),
                  HealthKitElectrocardiogramClaim.correlatedSymptomSourceTypes.contains(type) else {
                throw .ecgEvidence(.unsupportedSymptomType(identifier))
            }
            guard seen.insert(symptom.uuid).inserted else {
                throw .ecgEvidence(.duplicateSymptomSource(symptom.uuid))
            }
        }
        let order = { (symptom: HKCategorySample) in (symptom.categoryType.identifier, symptom.uuid.uuidString.lowercased()) }
        return symptoms.sorted { order($0) < order($1) }
    }

    /// What `ecg` and its `voltages` state, read once and validated: the zone its metadata names (else UTC), then its
    /// voltages in the claim's unit, then the algorithm version the same metadata states.
    func evidence(
        _ ecg: HKElectrocardiogram,
        voltages: [HKElectrocardiogram.VoltageMeasurement],
        metadata: HealthKitSampleMetadata
    ) throws -> Evidence {
        let zone = try metadata.timeZone() ?? .utc
        return Evidence(
            electrocardiogram: ecg,
            zone: zone,
            waveform: try Waveform(ecg, voltages: voltages, unit: voltageUnit),
            algorithmVersion: (metadata.values[HKMetadataKeyAppleECGAlgorithmVersion] as? NSNumber)?.intValue,
            metadata: metadata
        )
    }

    /// The waveform's draft, then the average heart rate's when the ECG states one. The waveform references each
    /// symptom by its output identifier; the average heart rate states the waveform's effective Period. The assembly
    /// states the ECG's entry method on both, as on every output of one record.
    func outputs(_ evidence: Evidence, symptoms: [RoledIdentifier]) throws -> [ExchangeOutputDraft] {
        let ecg = evidence.electrocardiogram
        guard ecg.endDate >= ecg.startDate else {
            throw HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)
        }
        let effective = try evidence.effectivePeriod()
        let drafts = [waveformSlot.draft(.observation(try waveformObservation(evidence, effective: effective, symptoms: symptoms)))]
        guard let beatsPerMinute = ecg.averageHeartRate?.doubleValue(for: averageHeartRateUnit) else {
            return drafts
        }
        // Heart rate has no value domain: an average the adapter cannot state exactly, nonfinite or beyond the decimal
        // model, is ECG evidence it cannot represent.
        guard let quantity = try? averageHeartRateQuantity.quantity(beatsPerMinute) else {
            throw HealthKitConversionError.ecgEvidence(.invalidAverageHeartRate)
        }
        var heartRate = averageHeartRateSkeleton
        heartRate.effective = .period(effective)
        heartRate.value = .quantity(quantity)
        return drafts + [averageHeartRateSlot.draft(.observation(heartRate))]
    }

    /// The waveform Observation: the voltages as SampledData over the effective Period, the symptoms status and the
    /// ECG's own period as extensions, the classification as interpretation, the algorithm version as method, and
    /// each symptom as an identifier-only member.
    private func waveformObservation(
        _ evidence: Evidence,
        effective: Period,
        symptoms: [RoledIdentifier]
    ) throws(HealthKitConversionError) -> Observation {
        let ecg = evidence.electrocardiogram
        guard let status = HealthKitElectrocardiogramClaim.symptomsStatusCodes[ecg.symptomsStatus] else {
            throw .ecgEvidence(.unsupportedSymptomsStatus(ecg.symptomsStatus.rawValue))
        }
        let sourcePeriod = try evidence.sourcePeriod()
        guard let interpretation = classifications[ecg.classification] else {
            throw .ecgEvidence(.unsupportedClassification(ecg.classification.rawValue))
        }
        var observation = waveformSkeleton
        if let version = evidence.algorithmVersion {
            guard let method = algorithmVersions[version] else {
                throw .ecgEvidence(.unsupportedAlgorithmVersion(version))
            }
            observation.method = method
        }
        observation.effective = .period(effective)
        observation.extension = (observation.extension ?? []) + [
            Extension(url: Canonicals.healthKitECGSymptomsStatusExtension, value: .code(status.asFHIRStringPrimitive())),
            Extension(url: Canonicals.healthKitECGSourcePeriodExtension, value: .period(sourcePeriod))
        ]
        observation.interpretation = [interpretation]
        let voltages = SampledData(
            data: evidence.waveform.data.asFHIRStringPrimitive(),
            dimensions: 1,
            origin: voltageOrigin,
            period: FHIRPrimitive(FHIRDecimal(evidence.waveform.period))
        )
        observation.component = [ObservationComponent(code: lead, value: .sampledData(voltages))]
        observation.hasMember = symptoms.isEmpty ? nil : symptoms.map { symptom in
            Reference(identifier: symptom.fhirIdentifier, type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.observation.rawValue)))
        }
        return observation
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitECGContent.Evidence {
    /// The waveform's effective Period: the ECG's start plus the first voltage's offset, to its start plus the last
    /// one's, each added exactly.
    func effectivePeriod() throws(HealthKitConversionError) -> Period {
        guard waveform.lastOffset > waveform.firstOffset else {
            throw .ecgEvidence(.invalidSourcePeriod)
        }
        let start = electrocardiogram.startDate
        return try period(start: start, plus: waveform.firstOffset, end: start, plus: waveform.lastOffset)
    }

    /// The ECG's own start and end.
    func sourcePeriod() throws(HealthKitConversionError) -> Period {
        try period(start: electrocardiogram.startDate, plus: 0, end: electrocardiogram.endDate, plus: 0)
    }

    /// The Period from `start` plus `startOffset` seconds to `end` plus `endOffset`, each instant exact in the zone;
    /// the end is stated first, as its failure takes precedence.
    private func period(start: Date, plus startOffset: Decimal, end: Date, plus endOffset: Decimal) throws(HealthKitConversionError) -> Period {
        let end = try HealthKitEffectiveTime.exactDateTime(end, offset: endOffset, zone: zone)
        let start = try HealthKitEffectiveTime.exactDateTime(start, offset: startOffset, zone: zone)
        return Period(end: FHIRPrimitive(end), start: FHIRPrimitive(start))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitECGContent.Waveform {
    /// The waveform of `ecg`'s `measurements`, read in `unit`: each states the claim's lead, they are exactly as many as
    /// the ECG reports and at least two, their offsets rise by one exact uniform period that agrees with the ECG's
    /// sampling frequency, and each voltage is finite.
    init(
        _ ecg: HKElectrocardiogram,
        voltages measurements: [HKElectrocardiogram.VoltageMeasurement],
        unit: HKUnit
    ) throws(HealthKitConversionError) {
        let voltages = try measurements.enumerated().map { index, measurement throws(HealthKitConversionError) in
            guard let voltage = measurement.quantity(for: HealthKitElectrocardiogramClaim.sourceLead) else {
                throw .ecgEvidence(.missingLeadVoltage(index: index))
            }
            return voltage.doubleValue(for: unit)
        }
        try Self.requireCount(ecg.numberOfVoltageMeasurements, supplied: voltages.count)
        let offsets = try Self.offsets(measurements)
        let period = try Self.period(offsets)
        try Self.requireFrequency(ecg.samplingFrequency?.doubleValue(for: .hertz()), period: period)
        let data = try voltages.enumerated().map { index, voltage throws(HealthKitConversionError) in
            guard voltage.isFinite else {
                throw .ecgEvidence(.invalidLeadVoltage(index: index))
            }
            return String(groveFHIRPlainDecimal: voltage)
        }
        self.init(firstOffset: offsets[0], lastOffset: offsets[offsets.count - 1], period: period, data: data.joined(separator: " "))
    }

    /// The ECG reports a positive count, and exactly that many voltages, at least two, are supplied.
    static func requireCount(_ reported: Int, supplied: Int) throws(HealthKitConversionError) {
        guard reported > 0 else {
            throw .ecgEvidence(.invalidReportedVoltageCount(reported))
        }
        guard supplied == reported else {
            throw .ecgEvidence(.voltageCountMismatch(reported: reported, supplied: supplied))
        }
        guard supplied >= 2 else {
            throw .ecgEvidence(.insufficientVoltageMeasurements)
        }
    }

    /// Each voltage's offset in seconds as the exact decimal its shortest text states: finite, not negative, and
    /// strictly rising.
    private static func offsets(_ measurements: [HKElectrocardiogram.VoltageMeasurement]) throws(HealthKitConversionError) -> [Decimal] {
        let offsets = try measurements.enumerated().map { index, measurement throws(HealthKitConversionError) in
            let offset = measurement.timeSinceSampleStart
            guard offset.isFinite, offset >= 0, let exact = Decimal(string: String(offset), locale: .posix) else {
                throw .ecgEvidence(.invalidOffset(index: index))
            }
            return exact
        }
        for index in offsets.indices.dropFirst() where offsets[index] <= offsets[index - 1] {
            throw .ecgEvidence(.invalidOffset(index: index))
        }
        return offsets
    }

    /// The period in milliseconds: every offset is the first plus a whole number of the first two's difference.
    private static func period(_ offsets: [Decimal]) throws(HealthKitConversionError) -> Decimal {
        let step = offsets[1] - offsets[0]
        for index in offsets.indices.dropFirst(2) where offsets[index] != offsets[0] + Decimal(index) * step {
            throw .ecgEvidence(.nonUniformOffset(index: index))
        }
        let period = step * 1_000
        guard period > 0, !period.isNaN else {
            throw .ecgEvidence(.invalidOffset(index: 1))
        }
        return period
    }

    /// A stated sampling frequency is finite and positive, and the one the period (in milliseconds) states.
    ///
    /// The guide canonicalizes the frequency and 1000 / period to their shortest round-trip decimals and requires them
    /// equal, with no tolerance. Equal shortest round-trip decimals are equal binary64 values, so the frequency must be
    /// the binary64 nearest the quotient as `Decimal` divides it (to at least 37 significant digits less the
    /// period's), which one correctly rounded parse finds. For a period of at most ten significant digits that is the
    /// exact quotient's nearest binary64: a 3 ms period admits 333.3333333333333 Hz, although no decimal times 3 is
    /// 1000, and refuses the binary64 one step above it.
    static func requireFrequency(_ hertz: Double?, period: Decimal) throws(HealthKitConversionError) {
        guard let hertz else {
            return
        }
        guard hertz.isFinite, hertz > 0 else {
            throw .ecgEvidence(.invalidSamplingFrequency)
        }
        guard hertz == Double((1_000 / period).description) else {
            throw .ecgEvidence(.samplingFrequencyMismatch)
        }
    }
}

#endif
