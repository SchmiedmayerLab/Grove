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
extension HealthKitContentPlan {
    /// An ECG record's evidence under this plan, read once and validated: its zone, voltages and algorithm version,
    /// beside the sample's metadata, bridged once for the graph. It is the first step of an ECG's conversion; the
    /// exporter takes it when it plans the record, as the record's fingerprint covers the voltages.
    func ecgEvidence(_ record: HealthKitECGRecord) throws -> HealthKitECGContent.Evidence {
        guard case .electrocardiogram(let content) = route else {
            throw refusal
        }
        return try content.evidence(record, metadata: HealthKitSampleMetadata(record.electrocardiogram, rule: metadata))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// Converts an ECG whose evidence is read and validated (``HealthKitContentPlan/ecgEvidence(_:)``) and every
    /// correlated symptom as independently exchangeable source events, each symptom under the request keyed by its
    /// sample's UUID: the symptoms are validated first, each converting as its own graph, then the waveform and its
    /// average heart rate are built.
    func convertECG(
        _ evidence: HealthKitECGContent.Evidence,
        symptoms: [HKCategorySample],
        plan: HealthKitContentPlan = HealthKitContentPlan[.electrocardiogram],
        request: Request,
        symptomRequests: [UUID: Request]
    ) throws -> [Conversion] {
        guard case .electrocardiogram(let content) = plan.route else {
            throw plan.refusal
        }
        let ecg = evidence.electrocardiogram
        let companions = try symptomConversions(symptoms, status: ecg.symptomsStatus, symptomRequests: symptomRequests)
        let outputs = try content.outputs(evidence, symptoms: try validatedSymptomOutputIdentifiers(companions))
        let primary = try graph(for: ecg, type: plan.sourceType, metadata: evidence.metadata, outputs: outputs, request: request)
        let events = [primary.identifiers.event] + companions.map(\.identifiers.event)
        guard Set(events).count == events.count else {
            throw HealthKitConversionError.ecgEvidence(.duplicateSymptomEventIdentity)
        }
        return [primary] + companions
    }

    /// Each correlated symptom under its own event, in the deterministic order the ECG references them.
    private func symptomConversions(
        _ correlatedSymptoms: [HKCategorySample],
        status: HKElectrocardiogram.SymptomsStatus,
        symptomRequests: [UUID: Request]
    ) throws -> [Conversion] {
        // Validation comes first, so an unsupported or duplicated symptom is refused as such.
        let symptoms = try HealthKitECGContent.validatedSymptoms(correlatedSymptoms, status: status)
        return try symptoms.flatMap { symptom in
            guard let request = symptomRequests[symptom.uuid] else {
                // The exporter keys every symptom of a registered type, and validation admits only registered types.
                preconditionFailure("Every validated symptom has a request.")
            }
            return try convert(symptom, request: request)
        }
    }

    private func validatedSymptomOutputIdentifiers(_ conversions: [Conversion]) throws -> [RoledIdentifier] {
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
extension HealthKitContentPlan {
    /// The recording document this plan carries a record of its type in, which states the payload's format; the
    /// exporter's companion fingerprint writes the payload through it too.
    func recordingDocument() throws(HealthKitConversionError) -> DocumentPlan {
        guard case .recording(let document) = route else {
            throw refusal
        }
        return document
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// Converts a heartbeat series into the recording document that carries its beats.
    func convertHeartbeatSeries(
        _ record: HealthKitHeartbeatSeriesRecord,
        plan: HealthKitContentPlan = HealthKitContentPlan[.heartbeatSeries],
        request: Request
    ) throws -> [Conversion] {
        try documentGraph(for: record.series, plan: plan, document: try plan.recordingDocument().document(record), request: request)
    }

    /// Converts a workout route into the recording document that carries its track, or into nothing while
    /// ``HealthKitFHIRExporter/Options/route`` is `.omit`: omitting the route drops an addition rather than rejecting
    /// anything.
    func convertWorkoutRoute(
        _ record: HealthKitWorkoutRouteRecord,
        plan: HealthKitContentPlan = HealthKitContentPlan[.workoutRoute],
        request: Request
    ) throws -> [Conversion] {
        guard options.route == .authorized else {
            return []
        }
        return try documentGraph(for: record.route, plan: plan, document: try plan.recordingDocument().document(record), request: request)
    }

    /// The document carrying a clinical record's provider-issued FHIR resource or a CDA document's bytes, exactly as
    /// HealthKit delivered them. A sample of another class carries neither, so it is refused as the inventory refuses a
    /// bare sample of a platform-exclusive type; watchOS has no clinical records, and its plans refuse these types.
    func clinicalDocument(_ sample: HKSample, plan: HealthKitContentPlan, document: DocumentPlan) throws -> DocumentReference {
        #if !os(watchOS)
        if let record = sample as? HKClinicalRecord {
            return try document.document(record)
        }
        if let cda = sample as? HKCDADocumentSample {
            return try document.document(cda)
        }
        #endif
        throw HealthKitConversionError.platformExclusiveSourceType(plan.sourceType)
    }

    /// One document's graph under `sample`'s envelope.
    func documentGraph(
        for sample: HKSample,
        plan: HealthKitContentPlan,
        document: DocumentReference,
        request: Request
    ) throws -> [Conversion] {
        let metadata = HealthKitSampleMetadata(sample, rule: plan.metadata)
        let output = plan.outputs[0].draft(.document(document))
        return [try graph(for: sample, type: plan.sourceType, metadata: metadata, outputs: [output], request: request)]
    }
}


// MARK: - Retraction

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// The complete retraction of the deleted record of `type` with `uuid`, as its own exchange event; every target
    /// is recomputed from the record's coordinates, so nothing from its conversion needs to be kept.
    func retraction(
        of uuid: UUID,
        type: HealthKitSourceType,
        request: Request,
        occurred: RetractionOccurrence
    ) throws(HealthKitConversionError) -> RetractionEvent {
        let targets = try retractionTargets(of: uuid, type: type)
        let sourceRecord = try sourceRecordIdentity(of: uuid, type: type)
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
    /// as each target's native record identifier exactly when ``HealthKitFHIRExporter/Options/nativeIdentifier``
    /// authorizes it.
    private func retractionTargets(of uuid: UUID, type: HealthKitSourceType) throws(HealthKitConversionError) -> [RetractionTarget] {
        let plan = HealthKitContentPlan[type]
        guard !plan.outputs.isEmpty else {
            throw plan.refusal
        }
        let nativeRecordIdentifier = options.nativeIdentifier.nativeRecordIdentifier(for: uuid.uuidString.lowercased())
        let sourceRecord = try sourceRecordIdentity(of: uuid, type: type)
        var targets: [RetractionTarget] = []
        for output in plan.outputs {
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
                throw HealthKitConversionError(dependency: error)
            }
        }
        return targets
    }

    private func sourceRecordIdentity(of uuid: UUID, type: HealthKitSourceType) throws(HealthKitConversionError) -> SourceRecordIdentity {
        do {
            return try scope.sourceRecord(sourceType: type.rawValue, nativeRecordID: uuid.uuidString.lowercased())
        } catch {
            throw .opaqueIdentity(error)
        }
    }
}

#endif
