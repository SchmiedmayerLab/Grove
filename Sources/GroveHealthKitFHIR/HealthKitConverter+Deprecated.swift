//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
public import GroveFHIRContract
public import HealthKit


// The deprecated context API: every entry point validates its context and forwards to the assembly the exporter uses,
// so both produce the same graphs. The exporter rework's final cleanup deletes this file.
@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Converts one sample only when the closed catalog admits its exact published contract.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert(
        _ sample: HKSample,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            try Self.validate(context: context)
            return try HealthKitAssembly(context: context.event).convert(sample, request: .init(context: context))
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: HealthKitSourceType(sample))
        }
    }

    /// Converts every input and keeps a typed failure for every record that was not emitted.
    ///
    /// A record whose context the caller could not supply fails with the caller's own error and
    /// never becomes a conversion refusal.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert<E: Error>(
        _ samples: some Sequence<HKSample>,
        context: (HKSample) throws(E) -> HealthKitConversionContext
    ) -> ConversionBatch<HealthKitConversionSet, HealthKitRecordFailure<E>> {
        var conversions: [HealthKitConversionSet] = []
        var failures: [HealthKitRecordFailure<E>] = []
        for sample in samples {
            guard let type = HealthKitSourceType(sample) else {
                failures.append(.unregisteredSourceType(uuid: sample.uuid, identifier: sample.sampleType.identifier))
                continue
            }
            let record = HealthKitSourceRecord(uuid: sample.uuid, type: type)
            let sampleContext: HealthKitConversionContext
            do {
                sampleContext = try context(sample)
            } catch {
                failures.append(.context(record, error))
                continue
            }
            do {
                conversions.append(try convert(sample, context: sampleContext))
            } catch {
                failures.append(.conversion(record, error))
            }
        }
        return ConversionBatch(conversions: conversions, failures: failures)
    }

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
            let plan = HealthKitContentPlan[.electrocardiogram]
            let evidence = try plan.ecgEvidence(record)
            return try HealthKitAssembly(context: context.event).convertECG(
                evidence,
                symptoms: record.correlatedSymptoms,
                plan: plan,
                request: .init(context: context),
                symptomRequests: try Self.symptomRequests(symptomContexts, for: record.correlatedSymptoms)
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: .electrocardiogram)
        }
    }

    /// Converts a heartbeat series into the recording document that carries its beats.
    ///
    /// No shared measurement models a beat series, and reducing one to a single Observation value
    /// would keep one beat and discard the rest, so the samples travel in the registry's
    /// `beat-interval-series` column schema instead.
    ///
    /// ```swift
    /// let conversion = try HealthKitConverter().convert(record, context: context)
    /// ```
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert(
        _ record: HealthKitHeartbeatSeriesRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            try Self.validate(context: context)
            return try HealthKitAssembly(context: context.event).convertHeartbeatSeries(record, request: .init(context: context))
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: .heartbeatSeries)
        }
    }

    /// Converts a workout route into the recording document that carries its track.
    ///
    /// - Returns: The route's graph, or `nil` under `RouteDisclosurePolicy.omit`, the default.
    ///   Omitting the route drops an addition rather than rejecting anything: the workout the
    ///   route belongs to converts on its own.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert(
        _ record: HealthKitWorkoutRouteRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet? {
        do {
            try Self.validate(context: context)
            return try HealthKitAssembly(context: context.event).convertWorkoutRoute(record, request: .init(context: context))
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: .workoutRoute)
        }
    }

    /// The complete retraction of a deleted record, as its own exchange event.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter.retract; removed with the exporter rework's final cleanup.")
    public func retraction(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext,
        occurred: RetractionOccurrence
    ) throws(HealthKitConversionError) -> RetractionEvent {
        try Self.validate(context: context)
        return try HealthKitAssembly(context: context.event).retraction(of: record, request: .init(context: context), occurred: occurred)
    }

    /// The logical targets a deletion retracts, named from the catalog alone.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter.retract; removed with the exporter rework's final cleanup.")
    public func retractionTargets(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> [RetractionTarget] {
        try Self.validate(context: context)
        return try HealthKitAssembly(context: context.event).retractionTargets(of: record, request: .init(context: context))
    }
}


#if !os(watchOS)
@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Carries the exact provider-issued DSTU2 or R4 JSON bytes surfaced by HealthKit in one
    /// validated R4 Grove exchange graph.
    ///
    /// The source release is mapped from `HKFHIRVersion.fhirRelease` to the attachment's versioned
    /// FHIR JSON media type. Grove validates only that the bytes contain one FHIR resource envelope;
    /// it never converts, re-encodes, or claims conformance over the provider's resource.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert(
        _ record: HKClinicalRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            try Self.validate(context: context)
            return try HealthKitAssembly(context: context.event).convert(record, request: .init(context: context))
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: HealthKitSourceType(record))
        }
    }

    /// Carries one CDA document exactly as HealthKit delivered it.
    ///
    /// The bytes are another issuer's document. Grove identifies it and records who wrote it, and
    /// never rewrites, reserializes, or asserts conformance over it — the same treatment a
    /// provider-issued clinical record receives.
    ///
    /// - Note: `HKCDADocumentSample.document` is populated only for a sample returned by an
    ///   `HKDocumentQuery` that asked for document data, so a sample from any other query fails
    ///   closed rather than converting to an empty payload.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter; removed with the exporter rework's final cleanup.")
    public func convert(
        _ sample: HKCDADocumentSample,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            try Self.validate(context: context)
            return try HealthKitAssembly(context: context.event).convert(sample, request: .init(context: context))
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: .cda)
        }
    }
}
#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The one check the typed context cannot make at construction: a disclosed native identifier
    /// system must not be one of the deployment's own graph identity systems.
    static func validate(context: HealthKitConversionContext) throws(HealthKitConversionError) {
        guard case let .authorized(nativeSystem, _) = context.options.nativeIdentifierDisclosure else {
            return
        }
        guard !context.identityScope.systems.all.contains(nativeSystem) else {
            throw .reservedIdentifierSystem
        }
    }

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
}

#endif
