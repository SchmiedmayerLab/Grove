//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


/// What one content builder made of a record: the tokens of what it built, or the error it threw.
enum ContentBuilderOutcome: Equatable {
    /// The built content's JSON tokens.
    case built(LosslessJSONValue)
    /// The thrown error, with its type and payload.
    case threw(String)

    /// Whether the builder refused the record.
    var isRefusal: Bool {
        if case .threw = self {
            return true
        }
        return false
    }

    /// The outcome as tokens: the built content's, or an object naming the error.
    var tokens: LosslessJSONValue {
        switch self {
        case .built(let tokens): tokens
        case .threw(let error): .object(["threw": .string(error)])
        }
    }

    /// The outcome of `build`.
    init(_ build: () throws -> LosslessJSONValue) {
        do {
            self = .built(try build())
        } catch {
            self = .threw(String(reflecting: error))
        }
    }
}


/// Today's content builders and the content plans' builders, run on the same record (oracle O4): today's as today's
/// assembly composes them, the plans' as the rewired assembly will. Every pair of outcomes must be equal: the same
/// JSON tokens, or the same error.
///
/// Temporary: it reads the old content internals, so the old code's deletion (M6) deletes it.
enum ContentBuilderPair {
    /// Both outcomes.
    typealias Outcomes = (today: ContentBuilderOutcome, planned: ContentBuilderOutcome)

    /// A route that has no builder of the kind asked for.
    struct NoBuilder: Error {
        /// The source type.
        let type: HealthKitSourceType
    }

    /// The system of the output identifiers an ECG's symptoms are referenced by here.
    private static let symptomOutputSystem: IdentifierSystem = "https://example.org/fhir/NamingSystem/symptom-output"

    /// Both builders' outcomes for `source`, or `nil` when no builder runs for its record: a type the inventory does
    /// not list, or a route whose sample entry refuses without building (O3 pins those refusals).
    static func outcomes(of source: ContentCorpusSource) throws -> Outcomes? {
        switch source.record {
        case .electrocardiogram(let reading):
            let record = try ContentCorpusSamples.electrocardiogram(source, reading: reading)
            return (ContentBuilderOutcome { try todaysElectrocardiogram(record) }, ContentBuilderOutcome { try plannedElectrocardiogram(record) })
        case .heartbeatSeries(let beats):
            let record = try ContentCorpusSamples.heartbeatSeries(source, beats: beats)
            let today = ContentBuilderOutcome {
                let payload = try HealthKitConverter.beatIntervalPayload(seriesStart: record.series.startDate, heartbeats: record.heartbeats)
                return try todaysDocument(record.series, format: .beatIntervalSeries, title: "Heartbeat series beat intervals", payload: payload)
            }
            return (today, ContentBuilderOutcome { try render(try documentPlan(.heartbeatSeries).document(record)) })
        case .workoutRoute(let locations, _):
            let record = try ContentCorpusSamples.workoutRoute(source, locations: locations)
            let today = ContentBuilderOutcome {
                let payload = try HealthKitConverter.locationTrackPayload(record.locations)
                return try todaysDocument(record.route, format: .locationTrackSamples, title: "Workout route locations", payload: payload)
            }
            return (today, ContentBuilderOutcome { try render(try documentPlan(.workoutRoute).document(record)) })
        default:
            return try outcomes(of: try ContentCorpusSamples.sample(source))
        }
    }

    /// Both builders' outcomes for a sample at the sample entry point.
    static func outcomes(of sample: HKSample) throws -> Outcomes? {
        guard let plan = HealthKitContentPlan.plan(for: sample) else {
            return nil
        }
        switch plan.route {
        case .observation(let observation):
            let today = ContentBuilderOutcome {
                guard let binding = HealthKitCatalog.binding(for: sample) else {
                    throw HealthKitConverter.unconvertibleSampleError(for: plan.sourceType)
                }
                return try render(try HealthKitConverter.observation(for: sample, binding: binding))
            }
            let planned = ContentBuilderOutcome {
                try render(try observation.observation(sample, metadata: HealthKitSampleMetadata(sample, rule: plan.metadata)))
            }
            return (today, planned)
        case .clinical(let document):
            #if os(watchOS)
            return nil
            #else
            let today = ContentBuilderOutcome { try render(try todaysClinicalDocument(sample)) }
            return (today, ContentBuilderOutcome { try render(try document.document(carrying: sample)) })
            #endif
        case .electrocardiogram, .recording, .refused:
            return nil
        }
    }

    /// A resource's JSON tokens.
    static func render(_ resource: some Encodable) throws -> LosslessJSONValue {
        try LosslessJSONValue(parsing: JSONEncoder().encode(resource))
    }

    /// The document plan of a recording or clinical type.
    private static func documentPlan(_ type: HealthKitSourceType) throws -> DocumentPlan {
        switch HealthKitContentPlan[type].route {
        case .recording(let document), .clinical(let document): document
        default: throw NoBuilder(type: type)
        }
    }

    /// Today's recording document of `payload`, as today's assembly states it.
    private static func todaysDocument(
        _ sample: HKSample,
        format: RegisteredRecordingFormat,
        title: String,
        payload: Data
    ) throws -> LosslessJSONValue {
        let evidence = HealthKitRecordingEvidence(outputRole: "native-recording", format: format, title: title, payload: payload)
        return try render(try HealthKitConverter.recordingDocument(evidence: evidence, sourceTypeIdentifier: sample.sampleType.identifier))
    }
}


extension ContentBuilderPair {
    /// Today's ECG outputs of `record`, as today's assembly composes them: the evidence, the waveform, the validated
    /// symptoms, then the waveform Observation and the average heart rate.
    private static func todaysElectrocardiogram(_ record: HealthKitECGRecord) throws -> LosslessJSONValue {
        let source = try HealthKitConverter.ecgSourceEvidence(record.electrocardiogram)
        let waveform = try HealthKitConverter.validatedWaveform(for: record, source: source)
        let symptoms = try HealthKitConverter.validatedSymptomSamples(record.correlatedSymptoms, status: source.symptomsStatus)
        let input = HealthKitECGObservationInput(source: source, waveform: waveform, symptomOutputIdentifiers: try identifiers(of: symptoms))
        guard let output = HealthKitCatalog.primaryOutput(for: .electrocardiogram) else {
            throw NoBuilder(type: .electrocardiogram)
        }
        let observation = try HealthKitConverter.ecgObservation(input: input)
        var drafts = [ExchangeOutputDraft(role: output.role, discriminator: output.discriminator, resource: .observation(observation))]
        if let averageHeartRate = try HealthKitConverter.ecgAverageHeartRateChild(input: input) {
            drafts.append(averageHeartRate)
        }
        return try render(symptoms, drafts: drafts)
    }

    /// The plans' ECG outputs of `record`, as the rewired assembly will compose them.
    private static func plannedElectrocardiogram(_ record: HealthKitECGRecord) throws -> LosslessJSONValue {
        let plan = HealthKitContentPlan[.electrocardiogram]
        guard case .electrocardiogram(let content) = plan.route else {
            throw NoBuilder(type: .electrocardiogram)
        }
        let ecg = record.electrocardiogram
        let evidence = try content.evidence(record, metadata: HealthKitSampleMetadata(ecg, rule: plan.metadata))
        let symptoms = try HealthKitECGContent.validatedSymptoms(record.correlatedSymptoms, status: ecg.symptomsStatus)
        return try render(symptoms, drafts: try content.outputs(evidence, symptoms: try identifiers(of: symptoms)))
    }

    /// The output identifiers the symptoms are referenced by: their own UUIDs, here.
    private static func identifiers(of symptoms: [HKCategorySample]) throws -> [RoledIdentifier] {
        try symptoms.map { symptom in
            RoledIdentifier(identifier: try BusinessIdentifier(system: symptomOutputSystem, value: symptom.uuid.uuidString), role: .sourceOutput)
        }
    }

    /// The validated symptoms' order and every draft as it enters the graph.
    private static func render(_ symptoms: [HKCategorySample], drafts: [ExchangeOutputDraft]) throws -> LosslessJSONValue {
        .object([
            "symptoms": .array(symptoms.map { .string($0.uuid.uuidString) }),
            "drafts": .array(try drafts.map(render(draft:)))
        ])
    }

    /// A draft: its identity, the statements it carries, and its resource.
    private static func render(draft: ExchangeOutputDraft) throws -> LosslessJSONValue {
        let resource = switch draft.resource {
        case .observation(let observation): try render(observation)
        case .document(let document): try render(document)
        }
        return .object([
            "role": .string(draft.role),
            "discriminator": .string(draft.discriminator),
            "links": .number(String(draft.links.rawValue)),
            "derivedFromPrimary": .boolean(draft.derivedFromPrimary),
            "artifactFormatCode": draft.artifactFormatCode.map(LosslessJSONValue.string) ?? .null,
            "wasUserEntered": .boolean(draft.wasUserEntered),
            "resource": resource
        ])
    }
}


#if !os(watchOS)
extension ContentBuilderPair {
    /// Today's clinical document of a clinical record or CDA sample, as today's assembly composes it.
    private static func todaysClinicalDocument(_ sample: HKSample) throws -> DocumentReference {
        let identifier = sample.sampleType.identifier
        if let record = sample as? HKClinicalRecord {
            guard let resource = record.fhirResource else {
                throw HealthKitConversionError.clinicalRecord(.empty)
            }
            let release = resource.fhirVersion.fhirRelease
            let evidence = try HealthKitConverter.clinicalRecordingEvidence(data: resource.data, release: release, sourceTypeIdentifier: identifier)
            return try HealthKitConverter.recordingDocument(evidence: evidence, sourceTypeIdentifier: identifier)
        }
        guard let document = (sample as? HKCDADocumentSample)?.document, let data = document.documentData, !data.isEmpty else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = HealthKitRecordingEvidence(
            outputRole: "clinical-record",
            format: .clinicalDocument,
            title: title.isEmpty ? "Clinical document" : title,
            payload: data
        )
        return try HealthKitConverter.recordingDocument(evidence: evidence, sourceTypeIdentifier: identifier)
    }
}


extension DocumentPlan {
    /// The document carrying a clinical record's or CDA sample's bytes, dispatched on the sample's class as the
    /// rewired assembly will.
    fileprivate func document(carrying sample: HKSample) throws -> DocumentReference {
        if let record = sample as? HKClinicalRecord {
            return try document(record)
        }
        guard let cda = sample as? HKCDADocumentSample else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        return try document(cda)
    }
}
#endif

#endif
