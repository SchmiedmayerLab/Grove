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


// MARK: - Electrocardiogram

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// The requests of an ECG's correlated symptoms.
    enum SymptomRequests {
        /// One request per symptom, in the record's order: the context API's shape.
        case positional([Request])
        /// Each symptom's request under its sample's UUID: the exporter's shape, paired by event key.
        case keyed([UUID: Request])
    }

    /// Converts an already-fetched ECG and every correlated symptom as independently exchangeable
    /// source events, each symptom under its own request.
    func convertECG(_ record: HealthKitECGRecord, request: Request, symptomRequests: SymptomRequests) throws -> HealthKitConversionSet {
        let source = try HealthKitConverter.ecgSourceEvidence(record.electrocardiogram)
        return try convertECG(
            record.electrocardiogram,
            evidence: HealthKitECGEvidence(source: source, waveform: try HealthKitConverter.validatedWaveform(for: record, source: source)),
            symptoms: record.correlatedSymptoms,
            request: request,
            symptomRequests: symptomRequests
        )
    }

    /// `ecg` supplies only the envelope's identity, device and source facts; the evidence is given.
    func convertECG(
        _ ecg: HKSample,
        evidence: HealthKitECGEvidence,
        symptoms: [HKCategorySample],
        request: Request,
        symptomRequests: SymptomRequests
    ) throws -> HealthKitConversionSet {
        let companions = try symptomConversions(symptoms, source: evidence.source, symptomRequests: symptomRequests)
        let input = HealthKitECGObservationInput(
            source: evidence.source,
            waveform: evidence.waveform,
            symptomOutputIdentifiers: try validatedSymptomOutputIdentifiers(companions)
        )
        guard let output = HealthKitCatalog.primaryOutput(for: .electrocardiogram) else {
            throw HealthKitConversionError.unsupportedSourceType(.electrocardiogram)
        }
        let waveform = ExchangeOutputDraft(
            role: output.role,
            discriminator: output.discriminator,
            resource: .observation(try HealthKitConverter.ecgObservation(input: input))
        )
        var outputs = [waveform]
        if let averageHeartRate = try HealthKitConverter.ecgAverageHeartRateChild(input: input) {
            outputs.append(averageHeartRate)
        }
        let primary = try graph(for: ecg, type: .electrocardiogram, outputs: outputs, request: request)
        let events = [primary.identifiers.event] + companions.map(\.identifiers.event)
        guard Set(events).count == events.count else {
            throw HealthKitConversionError.ecgEvidence(.duplicateSymptomEventIdentity)
        }
        return HealthKitConversionSet(primary: primary, companions: companions)
    }

    /// Each correlated symptom under its own event, in the deterministic order the ECG references them.
    private func symptomConversions(
        _ correlatedSymptoms: [HKCategorySample],
        source: HealthKitECGSourceEvidence,
        symptomRequests: SymptomRequests
    ) throws -> [HealthKitConversion] {
        let requestsBySample: [UUID: Request]
        switch symptomRequests {
        case .positional(let requests):
            guard requests.count == correlatedSymptoms.count else {
                throw HealthKitConversionError.ecgEvidence(.symptomContextCountMismatch(
                    symptoms: correlatedSymptoms.count,
                    contexts: requests.count
                ))
            }
            requestsBySample = Dictionary(zip(correlatedSymptoms.map(\.uuid), requests), uniquingKeysWith: { first, _ in first })
        case .keyed(let requests):
            requestsBySample = requests
        }
        // Validation comes first, so an unsupported or duplicated symptom is refused as such.
        let symptoms = try HealthKitConverter.validatedSymptomSamples(correlatedSymptoms, status: source.symptomsStatus)
        return try symptoms.map { symptom in
            guard let request = requestsBySample[symptom.uuid] else {
                // The positional shape keys every symptom; the keyed shape keys every symptom of a registered type,
                // and validation admits only symptom types that are registered.
                preconditionFailure("Every validated symptom has a request in both shapes.")
            }
            return try convert(symptom, request: request).primary
        }
    }

    private func validatedSymptomOutputIdentifiers(_ conversions: [HealthKitConversion]) throws -> [RoledIdentifier] {
        let outputs = conversions.map(\.identifiers.primaryOutput)
        let expectedSystem = scope.identityScope.systems.opaque.sourceOutput
        guard outputs.allSatisfy({ $0.role == .sourceOutput && $0.identifier.system == expectedSystem }) else {
            throw HealthKitConversionError.ecgEvidence(.invalidSymptomOutputIdentity)
        }
        guard Set(outputs).count == outputs.count else {
            throw HealthKitConversionError.ecgEvidence(.duplicateSymptomOutputIdentity)
        }
        return outputs
    }
}


// MARK: - Recording documents

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// Converts a heartbeat series into the recording document that carries its beats.
    func convertHeartbeatSeries(_ record: HealthKitHeartbeatSeriesRecord, request: Request) throws -> HealthKitConversionSet {
        try documentGraph(
            for: record.series,
            type: .heartbeatSeries,
            evidence: HealthKitRecordingEvidence(
                outputRole: "native-recording",
                format: .beatIntervalSeries,
                title: "Heartbeat series beat intervals",
                payload: try HealthKitConverter.beatIntervalPayload(seriesStart: record.series.startDate, heartbeats: record.heartbeats)
            ),
            request: request
        )
    }

    /// Converts a workout route into the recording document that carries its track, or `nil` under
    /// `RouteDisclosurePolicy.omit`: omitting the route drops an addition rather than rejecting anything.
    func convertWorkoutRoute(_ record: HealthKitWorkoutRouteRecord, request: Request) throws -> HealthKitConversionSet? {
        guard request.options.routeDisclosure == .authorized else {
            return nil
        }
        return try documentGraph(
            for: record.route,
            type: .workoutRoute,
            evidence: HealthKitRecordingEvidence(
                outputRole: "native-recording",
                format: .locationTrackSamples,
                title: "Workout route locations",
                payload: try HealthKitConverter.locationTrackPayload(record.locations)
            ),
            request: request
        )
    }

    #if !os(watchOS)
    /// Carries the exact provider-issued DSTU2 or R4 JSON bytes surfaced by HealthKit in one validated
    /// R4 Grove exchange graph; Grove never converts, re-encodes, or claims conformance over them.
    func convertClinicalRecord(_ record: HKClinicalRecord, request: Request) throws -> HealthKitConversionSet {
        guard let fhirResource = record.fhirResource else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        guard let type = HealthKitSourceType(record) else {
            throw HealthKitConversionError.unregisteredSourceType(record.sampleType.identifier)
        }
        let evidence = try HealthKitConverter.clinicalRecordingEvidence(
            data: fhirResource.data,
            release: fhirResource.fhirVersion.fhirRelease,
            sourceTypeIdentifier: record.sampleType.identifier
        )
        return try documentGraph(for: record, type: type, evidence: evidence, request: request)
    }

    /// Carries a CDA document's bytes; `HKCDADocumentSample.document` is populated only by an
    /// `HKDocumentQuery` that asked for document data, so any other sample fails closed.
    func convertClinicalDocument(_ sample: HKCDADocumentSample, request: Request) throws -> HealthKitConversionSet {
        guard let document = sample.document, let data = document.documentData, !data.isEmpty else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return try documentGraph(
            for: sample,
            type: .cda,
            evidence: HealthKitRecordingEvidence(
                outputRole: "clinical-record",
                format: .clinicalDocument,
                title: title.isEmpty ? "Clinical document" : title,
                payload: data
            ),
            request: request
        )
    }
    #endif

    func documentGraph(
        for sample: HKSample,
        type: HealthKitSourceType,
        evidence: HealthKitRecordingEvidence,
        request: Request
    ) throws -> HealthKitConversionSet {
        let output = ExchangeOutputDraft(
            role: evidence.outputRole,
            resource: .document(try HealthKitConverter.recordingDocument(evidence: evidence, sourceTypeIdentifier: sample.sampleType.identifier)),
            links: [.subject, .recordingDevice, .studies],
            artifactFormatCode: evidence.format.rawValue
        )
        return HealthKitConversionSet(primary: try graph(for: sample, type: type, outputs: [output], request: request))
    }
}


// MARK: - Retraction

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// The complete retraction of a deleted record, as its own exchange event; every target is
    /// recomputed from the record's coordinates, so nothing from its conversion needs to be kept.
    func retraction(
        of record: HealthKitSourceRecord,
        request: Request,
        occurred: RetractionOccurrence
    ) throws(HealthKitConversionError) -> RetractionEvent {
        let targets = try retractionTargets(of: record, request: request)
        let sourceRecord = try sourceRecordIdentity(of: record)
        do throws(RetractionEventError) {
            return try RetractionEvent(
                targets: targets,
                context: eventContext(for: request),
                sourceRecord: sourceRecord.identifier,
                occurred: occurred
            )
        } catch {
            throw HealthKitConversionError(error)
        }
    }

    /// The logical targets a deletion retracts, named from the catalog alone: the same identity scope
    /// and output roles yield the same identifiers the addition minted. The sample's UUID rides along
    /// as each target's native record identifier exactly when the disclosure policy authorizes it.
    func retractionTargets(of record: HealthKitSourceRecord, request: Request) throws(HealthKitConversionError) -> [RetractionTarget] {
        let outputs = HealthKitCatalog.outputs(for: record.type)
        guard !outputs.isEmpty else {
            throw HealthKitConverter.unconvertibleSampleError(for: record.type)
        }
        let nativeRecordIdentifier = request.options.nativeIdentifierDisclosure.nativeRecordIdentifier(
            for: record.uuid.uuidString.lowercased()
        )
        let sourceRecord = try sourceRecordIdentity(of: record)
        var targets: [RetractionTarget] = []
        for output in outputs {
            let identity: RoledIdentifier
            do {
                identity = try sourceRecord.output(role: output.role, discriminator: output.discriminator)
            } catch {
                throw .opaqueIdentity(error)
            }
            do {
                targets.append(try RetractionTarget(
                    identifier: identity,
                    resourceType: output.resourceType,
                    role: output.retractionRole,
                    nativeRecordIdentifier: nativeRecordIdentifier
                ))
            } catch {
                throw .dependency(HealthKitDependencyFailure(underlying: error))
            }
        }
        return targets
    }

    private func sourceRecordIdentity(of record: HealthKitSourceRecord) throws(HealthKitConversionError) -> SourceRecordIdentity {
        do {
            return try scope.sourceRecord(sourceType: record.type.rawValue, nativeRecordID: record.uuid.uuidString.lowercased())
        } catch {
            throw .opaqueIdentity(error)
        }
    }
}

#endif
