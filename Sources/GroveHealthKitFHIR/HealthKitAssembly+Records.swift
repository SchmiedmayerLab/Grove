//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


// MARK: - Electrocardiogram

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitContentPlan {
    /// An ECG record's evidence under this plan, read once and validated: its zone, voltages and algorithm version,
    /// beside the sample's metadata, bridged once for the record. It is the first step of an ECG's conversion; the
    /// exporter takes it when it plans the record.
    func ecgEvidence(
        _ ecg: HKElectrocardiogram,
        voltages: [HKElectrocardiogram.VoltageMeasurement]
    ) throws -> HealthKitECGContent.Evidence {
        guard case .electrocardiogram(let content) = route else {
            throw refusal
        }
        return try content.evidence(ecg, voltages: voltages, metadata: HealthKitSampleMetadata(ecg, rule: metadata))
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// Converts an ECG whose evidence is read and validated (``HealthKitContentPlan/ecgEvidence(_:voltages:)``) and every
    /// correlated symptom as independently exchangeable source records, each symptom under the request keyed by its
    /// sample's UUID: the symptoms are validated first, each converting as its own record, then the waveform and its
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
        let outputs = try content.outputs(evidence, symptoms: companions.map(\.identifiers.primaryOutput))
        let primary = try graph(for: ecg, type: plan.sourceType, metadata: evidence.metadata, outputs: outputs, request: request)
        return [primary] + companions
    }

    /// Each correlated symptom as its own record, in the deterministic order the ECG references them.
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
}


// MARK: - Recording documents

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitContentPlan {
    /// The recording document this plan carries a record of its type in, which states the payload's format.
    func recordingDocument() throws(HealthKitConversionError) -> DocumentPlan {
        guard case .recording(let document) = route else {
            throw refusal
        }
        return document
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// Converts a heartbeat series into the recording document that carries `recording`, its beat intervals.
    func convertHeartbeatSeries(
        _ series: HKHeartbeatSeriesSample,
        recording: Data,
        plan: HealthKitContentPlan = HealthKitContentPlan[.heartbeatSeries],
        request: Request
    ) throws -> [Conversion] {
        try documentGraph(for: series, plan: plan, document: try plan.recordingDocument().document(recording: recording), request: request)
    }

    /// Converts a workout route into the recording document that carries `recording`, its track. The exporter builds
    /// nothing for a route while ``HealthKitFHIRExporter/Options/route`` is `.omit`, so only an authorized one gets here.
    func convertWorkoutRoute(
        _ route: HKWorkoutRoute,
        recording: Data,
        plan: HealthKitContentPlan = HealthKitContentPlan[.workoutRoute],
        request: Request
    ) throws -> [Conversion] {
        try documentGraph(for: route, plan: plan, document: try plan.recordingDocument().document(recording: recording), request: request)
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

    #if !os(watchOS)
    /// Converts a clinical record and the files HealthKit stores with it: the record's clinical-record document, exactly as
    /// it is without files, and one attachment document per file, in part order, each appending to it and stating its
    /// subject, date, author and studies.
    func convertClinicalRecord(
        _ record: HKClinicalRecord,
        attachments: [HealthKitFHIRExporter.Record.ClinicalAttachment],
        plan: HealthKitContentPlan,
        request: Request
    ) throws -> [Conversion] {
        guard case .clinical(let documentPlan) = plan.route else {
            throw plan.refusal
        }
        let clinical = try clinicalDocument(record, plan: plan, document: documentPlan)
        var companions: [ExchangeOutputDraft] = []
        var unsupportedMetadata = false
        for (partIndex, attachment) in attachments.inPartOrder.enumerated() {
            let metadata = HealthKitSourceMetadata(
                sample: nil,
                values: attachment.metadata.mapValues { $0 as Any },
                policy: options.metadata
            )
            unsupportedMetadata = unsupportedMetadata || metadata.unsupportedCount > 0
            companions.append(ExchangeOutputDraft(
                role: HealthKitContract.clinicalAttachmentOutputRole,
                discriminator: attachment.identifier.uuidString.lowercased(),
                resource: .document(try documentPlan.attachmentDocument(attachment)),
                links: plan.outputs[0].links,
                appendsToPrimary: true,
                artifactFormatCode: HealthKitContract.clinicalAttachmentPayloadFormatCode,
                artifactPartIndex: UInt64(partIndex),
                trailingExtensions: metadata.container.map { [$0] } ?? []
            ))
        }
        // An attachment's metadata value the extension cannot carry is withheld, as a sample's is.
        let warnings = unsupportedMetadata
            ? [ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKAttachment.metadata")]
            : []
        return try documentGraph(for: record, plan: plan, document: clinical, companions: companions, companionWarnings: warnings, request: request)
    }
    #endif

    /// One document's graph under `sample`'s envelope, with the `companions` that follow the document, such as a clinical
    /// record's attachments, and what they withheld as `companionWarnings`.
    func documentGraph(
        for sample: HKSample,
        plan: HealthKitContentPlan,
        document: DocumentReference,
        companions: [ExchangeOutputDraft] = [],
        companionWarnings: [ProducerDiagnostic] = [],
        request: Request
    ) throws -> [Conversion] {
        let metadata = HealthKitSampleMetadata(sample, rule: plan.metadata)
        var document = document
        if case .recording = plan.route, document.context?.period == nil {
            let zone = try metadata.timeZone()
            guard try EffectiveRule.interval(nonZero: false).admitsPeriod(from: sample.startDate, to: sample.endDate) else {
                throw HealthKitConversionError.ValueFailure.effectivePeriodInvalid
            }
            var context = document.context ?? DocumentReferenceContext()
            context.period = try HealthKitEffectiveTime.period(start: sample.startDate, end: sample.endDate, zone: zone)
            document.context = context
        }
        let output = plan.outputs[0].draft(.document(document))
        return [
            try graph(
                for: sample,
                type: plan.sourceType,
                metadata: metadata,
                outputs: [output] + companions,
                additionalWarnings: companionWarnings,
                request: request
            )
        ]
    }
}


// MARK: - Retraction

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// The retraction of the deleted record of `type` with `uuid`, as a record of its own. Its one target is the source
    /// record, so it restates no output list from the current catalog: it suppresses every output of every version of the
    /// record, one only an earlier conversion emitted included, and nothing from a conversion needs to be kept. The
    /// sample's UUID rides along as the target's native record identifier exactly when
    /// ``HealthKitFHIRExporter/Options/nativeIdentifier`` authorizes it.
    func retraction(
        of uuid: UUID,
        type: HealthKitSourceType,
        request: Request,
        occurred: RetractionRecord.Occurrence
    ) throws(HealthKitConversionError) -> RetractionRecord {
        let plan = HealthKitContentPlan[type]
        guard !plan.outputs.isEmpty else {
            throw plan.refusal
        }
        let sourceRecord = try sourceRecordIdentity(of: uuid, type: type)
        let target: RetractionRecord.Target
        do {
            target = try RetractionRecord.Target(
                sourceRecord: sourceRecord.identifier,
                nativeRecordIdentifier: disclosure.nativeIdentifier.nativeRecordIdentifier(for: uuid.uuidString.lowercased())
            )
        } catch {
            throw HealthKitConversionError(dependency: error)
        }
        do throws(RetractionRecord.ValidationError) {
            return try ExchangeGraphAssembler(envelope: ExchangeEnvelope(scope: scope, facts: request.facts)).retraction(
                of: sourceRecord.identifier,
                targets: [target],
                occurred: occurred,
                at: request.instant
            )
        } catch {
            throw HealthKitConversionError(error)
        }
    }

    private func sourceRecordIdentity(of uuid: UUID, type: HealthKitSourceType) throws(HealthKitConversionError) -> SourceRecordIdentity {
        do {
            return try scope.sourceRecord(sourceType: type.rawValue, nativeRecordID: uuid.uuidString.lowercased())
        } catch {
            throw .exchangeIdentity(error)
        }
    }
}

#endif
