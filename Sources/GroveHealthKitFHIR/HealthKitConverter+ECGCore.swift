//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    static func validatedWaveform(
        for record: HealthKitECGRecord,
        source: HealthKitECGSourceEvidence
    ) throws -> HealthKitECGValidatedWaveform {
        let points = try record.voltageMeasurements.enumerated().map { index, measurement in
            guard let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI) else {
                throw HealthKitConversionError.ecgEvidence(.missingLeadVoltage(index: index))
            }
            return HealthKitECGVoltagePoint(
                timeSinceSampleStart: measurement.timeSinceSampleStart,
                millivolts: quantity.doubleValue(for: .voltUnit(with: .milli))
            )
        }
        return try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: source.numberOfVoltageMeasurements,
            samplingFrequencyHertz: source.samplingFrequency,
            points: points
        )
    }

    static func ecgSourceEvidence(
        _ ecg: HKElectrocardiogram
    ) throws -> HealthKitECGSourceEvidence {
        HealthKitECGSourceEvidence(
            sourceTypeIdentifier: ecg.sampleType.identifier,
            startDate: ecg.startDate,
            endDate: ecg.endDate,
            timeZone: try healthKitTimeZone(for: ecg),
            classification: ecg.classification,
            symptomsStatus: ecg.symptomsStatus,
            numberOfVoltageMeasurements: ecg.numberOfVoltageMeasurements,
            averageHeartRate: ecg.averageHeartRate?.doubleValue(for: .count().unitDivided(by: .minute())),
            samplingFrequency: ecg.samplingFrequency?.doubleValue(for: .hertz()),
            algorithmVersion: (ecg.metadata?[HKMetadataKeyAppleECGAlgorithmVersion] as? NSNumber)?.intValue
        )
    }

    /// The ECG Observation content; symptoms are referenced by identifier because they travel as
    /// graphs of their own.
    static func ecgObservation(input: HealthKitECGObservationInput) throws -> Observation {
        let source = input.source
        guard source.endDate >= source.startDate else {
            throw HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)
        }
        let period = try effectivePeriod(
            source: source,
            waveform: input.waveform,
            timeZone: source.timeZone
        )
        var observation = baseECGObservation(source: source, waveform: input.waveform, effectivePeriod: period)
        observation.extension = (observation.extension ?? []) + (try requiredECGExtensions(source: source))
        observation.interpretation = [
            CodeableConcept(coding: [
                Coding(
                    code: try classificationCode(source.classification).asFHIRStringPrimitive(),
                    system: "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-ecg-classification"
                )
            ])
        ]
        if let algorithm = try algorithmVersionCode(source.algorithmVersion) {
            observation.method = CodeableConcept(coding: [
                Coding(
                    code: algorithm.asFHIRStringPrimitive(),
                    system: "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-ecg-algorithm-version"
                )
            ])
        }
        if !input.symptomOutputIdentifiers.isEmpty {
            observation.hasMember = input.symptomOutputIdentifiers.map { identifier in
                Reference(
                    identifier: identifier.fhirIdentifier,
                    type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.observation.rawValue))
                )
            }
        }
        return observation
    }

    /// The source's period average is a distinct clinical result derived from the ECG waveform.
    /// It therefore receives its own output identity and provenance target instead of being hidden
    /// in a waveform-specific extension or making the waveform claim the reverse relationship.
    static func ecgAverageHeartRateChild(input: HealthKitECGObservationInput) throws -> ExchangeOutputDraft? {
        guard let averageHeartRate = input.source.averageHeartRate else {
            return nil
        }
        guard averageHeartRate.isFinite else {
            throw HealthKitConversionError.ecgEvidence(.invalidAverageHeartRate)
        }
        let effective = try effectivePeriod(source: input.source, waveform: input.waveform, timeZone: input.source.timeZone)
        return ExchangeOutputDraft(
            role: "average-heart-rate",
            resource: .observation(try averageHeartRateObservation(value: averageHeartRate, effective: effective, input: input)),
            derivedFromPrimary: true
        )
    }

    private static func baseECGObservation(
        source: HealthKitECGSourceEvidence,
        waveform: HealthKitECGValidatedWaveform,
        effectivePeriod: Period
    ) -> Observation {
        var observation = Observation(
            code: CodeableConcept(
                coding: [
                    Coding(code: "11524-6", display: "EKG study", system: "http://loinc.org")
                ]
            ),
            status: FHIRPrimitive(.final)
        )
        applySourceTypeLineage(source.sourceTypeIdentifier, to: &observation)
        observation.meta = Meta(profile: HealthKitContract.electrocardiogramProfiles)
        // `issued` is deliberately absent. It states when this version of the record became
        // available, and HealthKit keeps no per-object modification time to answer that; a wall
        // clock would make an unchanged sample convert differently on every run. The conversion
        // instant is recorded once, on Provenance.
        observation.effective = .period(effectivePeriod)
        observation.component = [voltageComponent(waveform)]
        return observation
    }

    private static func voltageComponent(
        _ waveform: HealthKitECGValidatedWaveform
    ) -> ObservationComponent {
        ObservationComponent(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: "131329",
                        display: "MDC_ECG_ELEC_POTL_I",
                        system: Canonicals.mdc
                    )
                ]
            ),
            value: .sampledData(SampledData(
                data: waveform.data.asFHIRStringPrimitive(),
                dimensions: 1,
                origin: Quantity(
                    code: "mV",
                    system: Canonicals.ucum,
                    unit: "mV",
                    value: 0.asFHIRDecimalPrimitive()
                ),
                period: FHIRPrimitive(FHIRDecimal(waveform.periodMilliseconds))
            ))
        )
    }

    private static func requiredECGExtensions(
        source: HealthKitECGSourceEvidence
    ) throws -> [Extension] {
        [
            Extension(
                url: Canonicals.healthKitECGSymptomsStatusExtension,
                value: .code(try symptomsStatusCode(source.symptomsStatus).asFHIRStringPrimitive())
            ),
            Extension(
                url: Canonicals.healthKitECGSourcePeriodExtension,
                value: .period(Period(
                    end: FHIRPrimitive(try HealthKitEffectiveTime.exactDateTime(source.endDate, offset: 0, zone: source.timeZone)),
                    start: FHIRPrimitive(try HealthKitEffectiveTime.exactDateTime(source.startDate, offset: 0, zone: source.timeZone))
                ))
            )
        ]
    }

    private static func effectivePeriod(
        source: HealthKitECGSourceEvidence,
        waveform: HealthKitECGValidatedWaveform,
        timeZone: TimeZone
    ) throws -> Period {
        guard waveform.lastOffsetSeconds > waveform.firstOffsetSeconds else {
            throw HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)
        }
        return Period(
            end: FHIRPrimitive(try HealthKitEffectiveTime.exactDateTime(
                source.startDate,
                offset: waveform.lastOffsetSeconds,
                zone: timeZone
            )),
            start: FHIRPrimitive(try HealthKitEffectiveTime.exactDateTime(
                source.startDate,
                offset: waveform.firstOffsetSeconds,
                zone: timeZone
            ))
        )
    }

    private static func classificationCode(
        _ classification: HKElectrocardiogram.Classification
    ) throws -> String {
        switch classification {
        case .notSet: "notSet"
        case .sinusRhythm: "sinusRhythm"
        case .atrialFibrillation: "atrialFibrillation"
        case .inconclusiveLowHeartRate: "inconclusiveLowHeartRate"
        case .inconclusiveHighHeartRate: "inconclusiveHighHeartRate"
        case .inconclusivePoorReading: "inconclusivePoorReading"
        case .inconclusiveOther: "inconclusiveOther"
        case .unrecognized: "unrecognized"
        @unknown default:
            throw HealthKitConversionError.ecgEvidence(.unsupportedClassification(classification.rawValue))
        }
    }

    private static func symptomsStatusCode(
        _ status: HKElectrocardiogram.SymptomsStatus
    ) throws -> String {
        switch status {
        case .notSet: "notSet"
        case .none: "none"
        case .present: "present"
        @unknown default:
            throw HealthKitConversionError.ecgEvidence(.unsupportedSymptomsStatus(status.rawValue))
        }
    }

    private static func algorithmVersionCode(_ rawVersion: Int?) throws -> String? {
        guard let rawVersion else {
            return nil
        }
        return switch rawVersion {
        case HKAppleECGAlgorithmVersion.version1.rawValue: "version1"
        case HKAppleECGAlgorithmVersion.version2.rawValue: "version2"
        default:
            throw HealthKitConversionError.ecgEvidence(.unsupportedAlgorithmVersion(rawVersion))
        }
    }

    static func decimalQuantity(_ value: Double, code: String, display: String) throws -> Quantity {
        guard value.isFinite else {
            throw HealthKitConversionError.ecgEvidence(.invalidSamplingFrequency)
        }
        return Quantity(
            code: code.asFHIRStringPrimitive(),
            system: Canonicals.ucum,
            unit: display.asFHIRStringPrimitive(),
            value: try HealthKitMobileCanonicalization.scalarDecimal(value)
        )
    }

    static func healthKitTimeZone(for sample: HKSample) throws -> TimeZone {
        try healthKitTimeZone(metadata: sample.metadata ?? [:])
    }

    static func healthKitTimeZone(metadata: [String: Any]) throws -> TimeZone {
        try sourceTimeZone(metadata: metadata) ?? .utc
    }

    /// The time zone HealthKit states for a sample, or nil when it names none.
    static func sourceTimeZone(metadata: [String: Any]) throws -> TimeZone? {
        switch metadata[HKMetadataKeyTimeZone] {
        case nil:
            return nil
        case let identifier as String:
            guard let timeZone = TimeZone(identifier: identifier) else {
                throw HealthKitValueFailure.unsupportedMetadataValue(.timeZone)
            }
            return timeZone
        case .some:
            throw HealthKitValueFailure.unsupportedMetadataValue(.timeZone)
        }
    }
}

#endif
