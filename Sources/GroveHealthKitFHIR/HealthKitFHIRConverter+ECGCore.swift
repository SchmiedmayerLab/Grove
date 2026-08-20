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
extension HealthKitFHIRConverter {
    private static let ecgMDC: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    private static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"

    static func convertECG(
        _ record: HealthKitECGRecord,
        context: HealthKitFHIRConversionContext
    ) throws -> HealthKitFHIRConversion {
        try validate(context: context)
        let ecg = record.electrocardiogram
        let source = try ecgSourceEvidence(ecg)
        let symptoms = try validatedSymptoms(record.correlatedSymptoms, status: source.symptomsStatus)
        try validateSymptomSourceDisclosure(
            symptomCount: symptoms.count,
            policy: context.sourceRevisionDisclosurePolicy
        )
        let input = HealthKitECGObservationInput(
            source: source,
            waveform: try validatedWaveform(for: record, source: source),
            symptoms: symptoms,
            context: context
        )
        return try assembleGraph(for: ecg, context: context) { recordingDeviceURL, converterURL in
            try ecgObservation(
                input: input,
                graphContext: .init(
                    recordingDeviceURL: recordingDeviceURL,
                    converterURL: converterURL
                )
            )
        }
    }

    private static func validatedWaveform(
        for record: HealthKitECGRecord,
        source: HealthKitECGSourceEvidence
    ) throws -> HealthKitECGValidatedWaveform {
        let points = try record.voltageMeasurements.enumerated().map { index, measurement in
            guard let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI) else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.missingLeadVoltage(index: index))
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

    private static func ecgSourceEvidence(
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
            algorithmVersion: (ecg.metadata?[HKMetadataKeyAppleECGAlgorithmVersion] as? NSNumber)?.intValue,
            wasUserEntered: (ecg.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
        )
    }

    static func ecgObservation(
        input: HealthKitECGObservationInput,
        graphContext: HealthKitECGGraphContext
    ) throws -> Observation {
        let source = input.source
        guard source.endDate >= source.startDate else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSourcePeriod)
        }
        let period = try effectivePeriod(
            source: source,
            waveform: input.waveform,
            timeZone: source.timeZone
        )
        var observation = try baseECGObservation(
            source: source,
            waveform: input.waveform,
            effectivePeriod: period,
            context: input.context
        )
        observation.extension = try ecgExtensions(
            source: source,
            symptoms: input.symptoms
        )
        applyGraphContext(
            to: &observation,
            context: input.context,
            graphContext: graphContext,
            wasUserEntered: source.wasUserEntered
        )
        return observation
    }

    private static func baseECGObservation(
        source: HealthKitECGSourceEvidence,
        waveform: HealthKitECGValidatedWaveform,
        effectivePeriod: Period,
        context: HealthKitFHIRConversionContext
    ) throws -> Observation {
        var observation = Observation(
            code: CodeableConcept(
                coding: [
                    Coding(code: "11524-6", display: "EKG study", system: "http://loinc.org"),
                    Coding(
                        code: source.sourceTypeIdentifier.asFHIRStringPrimitive(),
                        display: "ECG",
                        system: GroveFHIRCanonical.healthKitSourceType
                    )
                ]
            ),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: GroveFHIRHealthKitCatalog.electrocardiogramProfiles)
        observation.subject = context.subject
        observation.issued = FHIRPrimitive(try Instant(date: context.issuedAt))
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
                        system: ecgMDC
                    )
                ]
            ),
            value: .sampledData(SampledData(
                data: waveform.data.asFHIRStringPrimitive(),
                dimensions: 1,
                origin: Quantity(
                    code: "mV",
                    system: ucum,
                    unit: "mV",
                    value: 0.asFHIRDecimalPrimitive()
                ),
                period: FHIRPrimitive(FHIRDecimal(waveform.periodMilliseconds))
            ))
        )
    }

    private static func ecgExtensions(
        source: HealthKitECGSourceEvidence,
        symptoms: [HealthKitECGSymptomEvidence]
    ) throws -> [Extension] {
        var extensions = try requiredECGExtensions(source: source)
        extensions.append(contentsOf: try symptoms.map(symptomExtension))
        extensions.append(contentsOf: try optionalECGExtensions(source))
        return extensions
    }

    private static func requiredECGExtensions(
        source: HealthKitECGSourceEvidence
    ) throws -> [Extension] {
        [
            Extension(
                url: GroveFHIRCanonical.healthKitECGClassificationExtension,
                value: .code(try classificationCode(source.classification).asFHIRStringPrimitive())
            ),
            Extension(
                url: GroveFHIRCanonical.healthKitECGSymptomsStatusExtension,
                value: .code(try symptomsStatusCode(source.symptomsStatus).asFHIRStringPrimitive())
            ),
            Extension(
                url: GroveFHIRCanonical.healthKitECGCountExtension,
                value: .integer(FHIRPrimitive(FHIRInteger(Int32(source.numberOfVoltageMeasurements))))
            ),
            Extension(
                url: GroveFHIRCanonical.healthKitECGSourcePeriodExtension,
                value: .period(Period(
                    end: FHIRPrimitive(try exactHealthKitDateTime(
                        source.endDate,
                        timeZone: source.timeZone
                    )),
                    start: FHIRPrimitive(try exactHealthKitDateTime(
                        source.startDate,
                        timeZone: source.timeZone
                    ))
                ))
            )
        ]
    }

    private static func optionalECGExtensions(_ source: HealthKitECGSourceEvidence) throws -> [Extension] {
        var extensions: [Extension] = []
        if let averageHeartRate = source.averageHeartRate {
            guard averageHeartRate.isFinite else {
                throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidAverageHeartRate)
            }
            extensions.append(Extension(
                url: GroveFHIRCanonical.healthKitECGAverageHeartRateExtension,
                value: .quantity(try decimalQuantity(
                    averageHeartRate,
                    code: "/min",
                    display: "beats/minute"
                ))
            ))
        }
        if let samplingFrequency = source.samplingFrequency {
            extensions.append(Extension(
                url: GroveFHIRCanonical.healthKitECGSamplingFrequencyExtension,
                value: .quantity(try decimalQuantity(samplingFrequency, code: "Hz", display: "Hz"))
            ))
        }
        if let algorithm = try algorithmVersionCode(source.algorithmVersion) {
            extensions.append(Extension(
                url: GroveFHIRCanonical.healthKitECGAlgorithmVersionExtension,
                value: .code(algorithm.asFHIRStringPrimitive())
            ))
        }
        return extensions
    }

    private static func applyGraphContext(
        to observation: inout Observation,
        context: HealthKitFHIRConversionContext,
        graphContext: HealthKitECGGraphContext,
        wasUserEntered: Bool
    ) {
        if wasUserEntered {
            applyManualRecordingMethod(to: &observation)
        }
        if let recordingDeviceURL = graphContext.recordingDeviceURL {
            observation.device = Reference(reference: recordingDeviceURL.asFHIRStringPrimitive())
        }
        if context.converterWasGateway {
            observation.append(
                extension: Extension(
                    url: GroveFHIRCanonical.gatewayDevice,
                    value: .reference(Reference(
                        reference: graphContext.converterURL.asFHIRStringPrimitive()
                    ))
                ),
                behaviour: .replace
            )
        }
        for study in context.researchStudies {
            observation.append(extension: Extension(
                url: GroveFHIRCanonical.researchStudy,
                value: .reference(study)
            ))
        }
    }

    private static func effectivePeriod(
        source: HealthKitECGSourceEvidence,
        waveform: HealthKitECGValidatedWaveform,
        timeZone: TimeZone
    ) throws -> Period {
        guard waveform.lastOffsetSeconds > waveform.firstOffsetSeconds else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSourcePeriod)
        }
        return Period(
            end: FHIRPrimitive(try exactHealthKitDateTime(
                source.startDate,
                offsetSeconds: waveform.lastOffsetSeconds,
                timeZone: timeZone
            )),
            start: FHIRPrimitive(try exactHealthKitDateTime(
                source.startDate,
                offsetSeconds: waveform.firstOffsetSeconds,
                timeZone: timeZone
            ))
        )
    }

    /// Constructs a FHIR dateTime from the shortest round-trip representation of
    /// Foundation's source instant, then adds an exact decimal HealthKit offset.
    /// Going through `Date.addingTimeInterval` would introduce a second binary
    /// floating-point rounding step and can make SampledData's period arithmetic
    /// fail despite a complete uniform voltage enumeration.
    static func exactHealthKitDateTime(
        _ date: Date,
        offsetSeconds: Decimal = 0,
        timeZone: TimeZone
    ) throws -> DateTime {
        let epochSeconds = date.timeIntervalSince1970
        guard epochSeconds.isFinite,
              let epochDecimal = Decimal(
                  string: String(epochSeconds),
                  locale: Locale(identifier: "en_US_POSIX")
              ) else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSourcePeriod)
        }
        let target = epochDecimal + offsetSeconds
        let approximateTarget = NSDecimalNumber(decimal: target).doubleValue
        guard approximateTarget.isFinite,
              approximateTarget >= Double(Int64.min),
              approximateTarget <= Double(Int64.max) else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSourcePeriod)
        }

        var wholeSeconds = Int64(floor(approximateTarget))
        var fractionalSecond = target - Decimal(wholeSeconds)
        if fractionalSecond < 0 {
            wholeSeconds -= 1
            fractionalSecond += 1
        } else if fractionalSecond >= 1 {
            wholeSeconds += 1
            fractionalSecond -= 1
        }

        let wholeSecondDate = Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: wholeSecondDate
        )
        guard let year = components.year,
              let month = components.month.flatMap(UInt8.init(exactly:)),
              let day = components.day.flatMap(UInt8.init(exactly:)),
              let hour = components.hour.flatMap(UInt8.init(exactly:)),
              let minute = components.minute.flatMap(UInt8.init(exactly:)),
              let second = components.second else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSourcePeriod)
        }
        return DateTime(
            date: FHIRDate(year: year, month: month, day: day),
            time: FHIRTime(
                hour: hour,
                minute: minute,
                second: Decimal(second) + fractionalSecond
            ),
            timezone: timeZone
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
            throw GroveHealthKitFHIRError.invalidECGEvidence(.unsupportedClassification(classification.rawValue))
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
            throw GroveHealthKitFHIRError.invalidECGEvidence(.unsupportedSymptomsStatus(status.rawValue))
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
            throw GroveHealthKitFHIRError.invalidECGEvidence(.unsupportedAlgorithmVersion(rawVersion))
        }
    }

    private static func decimalQuantity(_ value: Double, code: String, display: String) throws -> Quantity {
        guard value.isFinite else {
            throw GroveHealthKitFHIRError.invalidECGEvidence(.invalidSamplingFrequency)
        }
        return Quantity(
            code: code.asFHIRStringPrimitive(),
            system: ucum,
            unit: display.asFHIRStringPrimitive(),
            value: try HealthKitFHIRMobileCanonicalization.scalarDecimal(value)
        )
    }

    static func healthKitTimeZone(for sample: HKSample) throws -> TimeZone {
        guard let identifier = sample.metadata?[HKMetadataKeyTimeZone] as? String else {
            return .gmt
        }
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyTimeZone,
                value: identifier
            )
        }
        return timeZone
    }
}

#endif
