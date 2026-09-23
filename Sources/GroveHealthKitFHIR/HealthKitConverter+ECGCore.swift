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
    static func convertECG(
        _ record: HealthKitECGRecord,
        context: HealthKitConversionContext,
        symptomContexts: [HealthKitConversionContext]
    ) throws -> HealthKitConversionSet {
        try validate(context: context)
        let ecg = record.electrocardiogram
        let source = try ecgSourceEvidence(ecg)
        let symptomConversions = try symptomConversions(
            for: record,
            source: source,
            context: context,
            symptomContexts: symptomContexts
        )
        let input = HealthKitECGObservationInput(
            source: source,
            waveform: try validatedWaveform(for: record, source: source),
            symptomOutputIdentifiers: try validatedSymptomOutputIdentifiers(
                symptomConversions,
                expectedSystem: context.identityScope.systems.opaque.sourceOutput
            )
        )
        guard let output = HealthKitCatalog.primaryOutput(for: .electrocardiogram) else {
            throw HealthKitConversionError.unsupportedSourceType(.electrocardiogram)
        }
        let primary = try assembleGraph(
            for: ecg,
            context: context,
            outputRole: output.role,
            outputDiscriminator: output.discriminator,
            childBuilder: { envelope in
                try ecgAverageHeartRateChild(input: input, envelope: envelope).map { [$0] } ?? []
            }
        ) { graphContext in
            try ecgObservation(input: input, graphContext: graphContext)
        }
        let events = [primary.primary.identifiers.event] + symptomConversions.map(\.identifiers.event)
        guard Set(events).count == events.count else {
            throw HealthKitConversionError.ecgEvidence(.duplicateSymptomEventIdentity)
        }
        guard !input.symptomOutputIdentifiers.contains(primary.primary.identifiers.primaryOutput) else {
            throw HealthKitConversionError.ecgEvidence(.invalidSymptomOutputIdentity)
        }
        return HealthKitConversionSet(
            primary: primary.primary,
            companions: symptomConversions,
            warnings: primary.warnings
        )
    }

    /// Converts each correlated symptom under its own event context, in the deterministic order the
    /// ECG references them.
    private static func symptomConversions(
        for record: HealthKitECGRecord,
        source: HealthKitECGSourceEvidence,
        context: HealthKitConversionContext,
        symptomContexts: [HealthKitConversionContext]
    ) throws -> [HealthKitConversion] {
        guard symptomContexts.count == record.correlatedSymptoms.count else {
            throw HealthKitConversionError.ecgEvidence(.symptomContextCountMismatch(
                symptoms: record.correlatedSymptoms.count,
                contexts: symptomContexts.count
            ))
        }
        let contextsBySample = Dictionary(
            record.correlatedSymptoms.map(\.uuid).enumerated().map { ($1, symptomContexts[$0]) },
            uniquingKeysWith: { first, _ in first }
        )
        let symptoms = try validatedSymptomSamples(record.correlatedSymptoms, status: source.symptomsStatus)
        return try symptoms.map { symptom in
            guard let symptomContext = contextsBySample[symptom.uuid] else {
                throw HealthKitConversionError.ecgEvidence(.duplicateSymptomSource(symptom.uuid))
            }
            try validateSymptomConversionContext(symptomContext, expectedContext: context)
            let set = try convertSample(symptom, context: symptomContext)
            return set.primary
        }
    }

    /// A companion belongs to the same subject, repository scope and identity scope as the ECG.
    static func validateSymptomConversionContext(
        _ symptomContext: HealthKitConversionContext,
        expectedContext: HealthKitConversionContext
    ) throws {
        guard symptomContext.event.subject == expectedContext.event.subject,
              symptomContext.repositoryScope == expectedContext.repositoryScope,
              symptomContext.identityScope.systems == expectedContext.identityScope.systems,
              symptomContext.identityScope.keyID == expectedContext.identityScope.keyID,
              symptomContext.identityScope.epoch == expectedContext.identityScope.epoch else {
            throw HealthKitConversionError.ecgEvidence(.mismatchedSymptomContext)
        }
    }

    private static func validatedSymptomOutputIdentifiers(
        _ conversions: [HealthKitConversion],
        expectedSystem: IdentifierSystem
    ) throws -> [RoledIdentifier] {
        let outputs = conversions.map(\.identifiers.primaryOutput)
        guard outputs.allSatisfy({
            $0.role == .sourceOutput && $0.identifier.system == expectedSystem
        }) else {
            throw HealthKitConversionError.ecgEvidence(.invalidSymptomOutputIdentity)
        }
        guard Set(outputs).count == outputs.count else {
            throw HealthKitConversionError.ecgEvidence(.duplicateSymptomOutputIdentity)
        }
        return outputs
    }

    private static func validatedWaveform(
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
        graphContext: HealthKitGraphContext
    ) throws -> Observation {
        let source = input.source
        guard source.endDate >= source.startDate else {
            throw HealthKitConversionError.ecgEvidence(.invalidSourcePeriod)
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
            subject: graphContext.subject
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
            throw HealthKitConversionError.ecgEvidence(.invalidAverageHeartRate)
        }
        let identity = try envelope.sourceRecord.output(role: "average-heart-rate", discriminator: "single")
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
        subject: Reference
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
        observation.subject = subject
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
        graphContext: HealthKitGraphContext,
        wasUserEntered: Bool
    ) {
        if wasUserEntered {
            applyManualRecordingMethod(to: &observation)
        }
        if let recordingDeviceURL = graphContext.recordingDeviceURL {
            observation.device = Reference(reference: recordingDeviceURL.asFHIRStringPrimitive())
        }
        if let gatewayURL = graphContext.gatewayURL {
            observation.append(
                extension: Extension(
                    url: Canonicals.gatewayDevice,
                    value: .reference(Reference(reference: gatewayURL.asFHIRStringPrimitive()))
                ),
                behaviour: .replace
            )
        }
        for study in graphContext.studyReferences {
            observation.append(extension: Extension(url: Canonicals.researchStudy, value: .reference(study)))
        }
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
