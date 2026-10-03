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
    /// Converts an already-fetched ECG and every correlated symptom as independently exchangeable
    /// source events.
    ///
    /// One context per symptom, in the record's order, is intentionally required. Reusing the
    /// ECG's event context for a symptom would collapse two source-record revisions into one
    /// event, while omitting symptom conversions would leave identifier-only `hasMember`
    /// references dangling.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert(
        _ record: HealthKitECGRecord,
        context: HealthKitConversionContext,
        symptomContexts: [HealthKitConversionContext]
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            try Self.validate(context: context)
            for symptomContext in symptomContexts {
                try Self.validateSymptomConversionContext(symptomContext, expectedContext: context)
            }
            let evidence = try HealthKitECGEvidence(record)
            return try HealthKitAssembly(context: context.event).convertECG(
                record.electrocardiogram,
                evidence: evidence,
                symptoms: record.correlatedSymptoms,
                request: .init(context: context),
                symptomRequests: try Self.symptomRequests(symptomContexts, for: record.correlatedSymptoms)
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: .electrocardiogram)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The context API's one context per symptom, in the record's order, as the assembly's requests keyed by each
    /// symptom's UUID; a repeated symptom keeps its first context, and the symptom validation refuses it.
    static func symptomRequests(
        _ contexts: [HealthKitConversionContext],
        for symptoms: [HKCategorySample]
    ) throws -> [UUID: HealthKitAssembly.Request] {
        guard contexts.count == symptoms.count else {
            throw HealthKitConversionError.ecgEvidence(.symptomContextCountMismatch(symptoms: symptoms.count, contexts: contexts.count))
        }
        return Dictionary(zip(symptoms.map(\.uuid), contexts.map(HealthKitAssembly.Request.init(context:)))) { first, _ in first }
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

    static func averageHeartRateObservation(
        value: Double,
        effective: Period,
        input: HealthKitECGObservationInput
    ) throws -> Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(
                    code: "8867-4",
                    display: "Heart rate",
                    system: "http://loinc.org"
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.category = [
            CodeableConcept(coding: [
                Coding(
                    code: "vital-signs",
                    display: "Vital Signs",
                    system: "http://terminology.hl7.org/CodeSystem/observation-category"
                )
            ])
        ]
        applySourceTypeLineage(input.source.sourceTypeIdentifier, to: &observation)
        observation.meta = Meta(profile: [
            Profile.groveMobileHeartRate,
            Profile.healthkitEcgAverageHeartRateObservation
        ])
        observation.effective = .period(effective)
        observation.value = .quantity(try decimalQuantity(
            value,
            code: "/min",
            display: "beats/minute"
        ))
        return observation
    }
}

#endif
