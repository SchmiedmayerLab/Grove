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
    private static let ecgMDC: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    private static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"

    static func convertECG(
        _ record: HealthKitECGRecord,
        context: HealthKitConversionContext,
        symptomConversions: [HealthKitConversion]
    ) throws -> HealthKitConversionSet {
        try validate(context: context)
        let ecg = record.electrocardiogram
        let source = try ecgSourceEvidence(ecg)
        let symptomOutputs = try validatedSymptomConversions(
            for: record,
            source: source,
            conversions: symptomConversions,
            context: context
        )
        let input = HealthKitECGObservationInput(
            source: source,
            waveform: try validatedWaveform(for: record, source: source),
            symptomOutputIdentifiers: symptomOutputs,
            context: context
        )
        let primary = try assembleGraph(
            for: ecg,
            context: context,
            outputRole: "electrocardiogram",
            childBuilder: { envelope in
                guard let companion = try ecgAverageHeartRateChild(
                    input: input,
                    envelope: envelope
                ) else {
                    return []
                }
                return [companion]
            }
        ) { recordingDeviceURL, converterURL in
            try ecgObservation(
                input: input,
                graphContext: .init(
                    recordingDeviceURL: recordingDeviceURL,
                    converterURL: converterURL
                )
            )
        }
        let events = [primary.graphIdentifiers.event] + symptomConversions.map(\.graphIdentifiers.event)
        guard Set(events).count == events.count else {
            throw HealthKitConversionError.invalidECGEvidence(.duplicateSymptomEventIdentity)
        }
        guard !symptomOutputs.contains(primary.graphIdentifiers.primaryOutput) else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSymptomOutputIdentity)
        }
        return HealthKitConversionSet(primary: primary, companions: symptomConversions)
    }

    private static func validatedSymptomConversions(
        for record: HealthKitECGRecord,
        source: HealthKitECGSourceEvidence,
        conversions: [HealthKitConversion],
        context: HealthKitConversionContext
    ) throws -> [BusinessIdentifier] {
        let symptoms = try validatedSymptomSamples(record.correlatedSymptoms, status: source.symptomsStatus)
        guard symptoms.map(\.uuid) == conversions.map(\.localSourceUUID) else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSymptomOutputIdentity)
        }
        for conversion in conversions {
            try validateSymptomConversionContext(
                subject: conversion.observation.subject,
                subjectIdentity: conversion.subjectIdentity,
                repositoryScope: conversion.repositoryScope,
                expectedContext: context
            )
        }
        return try validatedSymptomOutputIdentifiers(
            conversions,
            expectedSystem: context.identityScope.systems.sourceOutput
        )
    }

    static func validateSymptomConversionContext(
        subject: Reference?,
        subjectIdentity: BusinessIdentifier,
        repositoryScope: BusinessIdentifier,
        expectedContext: HealthKitConversionContext
    ) throws {
        guard subject == expectedContext.subject,
              subjectIdentity == expectedContext.subjectIdentity,
              repositoryScope == expectedContext.repositoryScope else {
            throw HealthKitConversionError.invalidECGEvidence(.mismatchedSymptomContext)
        }
    }

    private static func validatedSymptomOutputIdentifiers(
        _ conversions: [HealthKitConversion],
        expectedSystem: IdentifierSystem
    ) throws -> [BusinessIdentifier] {
        let outputs = conversions.map(\.graphIdentifiers.primaryOutput)
        guard outputs.allSatisfy({
            $0.role == .sourceOutput && $0.system == expectedSystem
        }) else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSymptomOutputIdentity)
        }
        guard Set(outputs).count == outputs.count else {
            throw HealthKitConversionError.invalidECGEvidence(.duplicateSymptomOutputIdentity)
        }
        return outputs
    }

    private static func validatedWaveform(
        for record: HealthKitECGRecord,
        source: HealthKitECGSourceEvidence
    ) throws -> HealthKitECGValidatedWaveform {
        let points = try record.voltageMeasurements.enumerated().map { index, measurement in
            guard let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI) else {
                throw HealthKitConversionError.invalidECGEvidence(.missingLeadVoltage(index: index))
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
            throw HealthKitConversionError.invalidECGEvidence(.invalidSourcePeriod)
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
        applyGraphContext(
            to: &observation,
            context: input.context,
            graphContext: graphContext,
            wasUserEntered: source.wasUserEntered
        )
        return observation
    }

    /// The source's period average is a distinct clinical result derived from the ECG waveform.
    /// It therefore receives its own output identity and provenance target instead of being hidden
    /// in a waveform-specific extension or making the waveform claim the reverse relationship.
    static func ecgAverageHeartRateChild(
        input: HealthKitECGObservationInput,
        envelope: GraphEnvelope
    ) throws -> GraphChildOutput? {
        guard let averageHeartRate = input.source.averageHeartRate else {
            return nil
        }
        guard averageHeartRate.isFinite else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidAverageHeartRate)
        }
        let identity = try input.context.identityScope.sourceOutput(
            adapterID: "healthkit",
            sourceType: input.source.sourceTypeIdentifier,
            repositoryScope: input.context.repositoryScope,
            nativeRecordID: envelope.sourceUUID,
            outputRole: "average-heart-rate",
            outputDiscriminator: "single"
        )
        let effective = try effectivePeriod(
            source: input.source,
            waveform: input.waveform,
            timeZone: input.source.timeZone
        )
        let observation = try averageHeartRateObservation(
            value: averageHeartRate,
            identity: identity,
            effective: effective,
            input: input,
            envelope: envelope
        )
        return GraphChildOutput(
            identity: identity,
            observation: observation,
            primaryRelationship: .none
        )
    }

    private static func baseECGObservation(
        source: HealthKitECGSourceEvidence,
        waveform: HealthKitECGValidatedWaveform,
        effectivePeriod: Period,
        context: HealthKitConversionContext
    ) throws -> Observation {
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
        observation.subject = context.subject
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

    static func applyGraphContext(
        to observation: inout Observation,
        context: HealthKitConversionContext,
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
                    url: Canonicals.gatewayDevice,
                    value: .reference(Reference(
                        reference: graphContext.converterURL.asFHIRStringPrimitive()
                    ))
                ),
                behaviour: .replace
            )
        }
        for study in context.researchStudies {
            observation.append(extension: Extension(
                url: Canonicals.researchStudy,
                value: .reference(study)
            ))
        }
        if let protocolCanonical = context.protocolCanonical {
            observation.append(
                extension: Extension(
                    url: Canonicals.instantiatesCanonical,
                    value: .canonical(FHIRPrimitive(Canonical(stringLiteral: protocolCanonical)))
                ),
                behaviour: .replace
            )
        }
    }

    private static func effectivePeriod(
        source: HealthKitECGSourceEvidence,
        waveform: HealthKitECGValidatedWaveform,
        timeZone: TimeZone
    ) throws -> Period {
        guard waveform.lastOffsetSeconds > waveform.firstOffsetSeconds else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSourcePeriod)
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
            throw HealthKitConversionError.invalidECGEvidence(.unsupportedClassification(classification.rawValue))
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
            throw HealthKitConversionError.invalidECGEvidence(.unsupportedSymptomsStatus(status.rawValue))
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
            throw HealthKitConversionError.invalidECGEvidence(.unsupportedAlgorithmVersion(rawVersion))
        }
    }

    static func decimalQuantity(_ value: Double, code: String, display: String) throws -> Quantity {
        guard value.isFinite else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSamplingFrequency)
        }
        return Quantity(
            code: code.asFHIRStringPrimitive(),
            system: ucum,
            unit: display.asFHIRStringPrimitive(),
            value: try HealthKitMobileCanonicalization.scalarDecimal(value)
        )
    }

    static func healthKitTimeZone(for sample: HKSample) throws -> TimeZone {
        guard let identifier = sample.metadata?[HKMetadataKeyTimeZone] as? String else {
            return .gmt
        }
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw HealthKitConversionError.unsupportedMetadataValue(
                key: HKMetadataKeyTimeZone,
                value: identifier
            )
        }
        return timeZone
    }
}

#endif
