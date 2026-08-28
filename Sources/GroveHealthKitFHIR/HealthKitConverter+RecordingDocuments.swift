//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape, and members are ordered to read as a narrative
// rather than by kind: each entry point precedes the builders it uses.
// swiftlint:disable multiline_literal_brackets type_contents_order file_types_order function_body_length

#if canImport(HealthKit)

import CoreLocation
import CryptoKit
import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// A payload format from the Grove recording-format registry that this adapter carries.
enum HealthKitRecordingFormat: String, Sendable {
    case beatIntervalSeries = "beat-interval-series"
    case locationTrackSamples = "location-track-samples"
    case clinicalDocument = "clinical-document"
    case fhirR4Resource = "fhir-r4-resource"

    var contentType: String {
        switch self {
        case .beatIntervalSeries, .locationTrackSamples: "text/csv"
        case .clinicalDocument: "application/hl7-cda+xml"
        case .fhirR4Resource: "application/fhir+json"
        }
    }
}


/// The published payload of one recording document, ready to be carried.
struct HealthKitRecordingEvidence: Sendable {
    let outputRole: String
    let format: HealthKitRecordingFormat
    let title: String
    let payload: Data
    let profiles: [FHIRPrimitive<Canonical>]
    let clinicalRecordTypeCode: String?
    let clinicalFHIRReleaseCode: String?

    init(
        outputRole: String,
        format: HealthKitRecordingFormat,
        title: String,
        payload: Data,
        profiles: [FHIRPrimitive<Canonical>] = [
            Profile.groveSensorRecordingDocument,
            HealthKitRecordingDocumentContract.profile
        ],
        clinicalRecordTypeCode: String? = nil,
        clinicalFHIRReleaseCode: String? = nil
    ) {
        self.outputRole = outputRole
        self.format = format
        self.title = title
        self.payload = payload
        self.profiles = profiles
        self.clinicalRecordTypeCode = clinicalRecordTypeCode
        self.clinicalFHIRReleaseCode = clinicalFHIRReleaseCode
    }
}


/// Canonicals the HealthKit recording document declares.
///
/// Hand-stated rather than read from ``Profile``: the generated contract is pinned to the
/// grove-fhir release this package validates against, and these land there when that pin moves.
enum HealthKitRecordingDocumentContract {
    static let profile: FHIRPrimitive<Canonical> =
        "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-recording-document"
    static let formatCodeSystem: FHIRPrimitive<FHIRURI> =
        "https://grovealliance.org/fhir/sensor/CodeSystem/grove-recording-format"
    /// The registry release a carried payload conforms to, written to `content.format.version`.
    static let registryVersion = "0.6.0"
    static let clinicalRecordTypeCodeSystem: FHIRPrimitive<FHIRURI> =
        "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-clinical-record-type"
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    private static let beatIntervalColumns = ["timestamp", "precededByGap"]
    private static let locationTrackColumns = [
        "timestamp",
        "latitude",
        "longitude",
        "altitude",
        "horizontalAccuracy",
        "verticalAccuracy",
        "speed",
        "speedAccuracy",
        "course",
        "courseAccuracy"
    ]

    /// Converts a heartbeat series into the recording document that carries its beats.
    ///
    /// No shared measurement models a beat series, and reducing one to a single Observation value
    /// would keep one beat and discard the rest, so the samples travel in the registry's
    /// `beat-interval-series` column schema instead.
    ///
    /// ```swift
    /// let conversion = try HealthKitConverter().convert(record, context: context)
    /// ```
    public func convert(
        _ record: HealthKitHeartbeatSeriesRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitDocumentConversion {
        do {
            return try Self.assembleDocumentGraph(
                for: record.series,
                evidence: HealthKitRecordingEvidence(
                    outputRole: "native-recording",
                    format: .beatIntervalSeries,
                    title: "Heartbeat series beat intervals",
                    payload: try Self.beatIntervalPayload(
                        seriesStart: record.series.startDate,
                        heartbeats: record.heartbeats,
                        sampleType: record.series.sampleType.identifier
                    )
                ),
                context: context
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    /// Converts a workout route into the recording document that carries its track.
    ///
    /// - Returns: The route's graph, or `nil` under ``HealthKitRouteDisclosurePolicy/omit``, the
    ///   default. Omitting the route drops an addition rather than rejecting anything: the workout
    ///   the route belongs to converts on its own.
    public func convert(
        _ record: HealthKitWorkoutRouteRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitDocumentConversion? {
        do {
            guard let payload = try Self.locationTrackPayload(
                record.locations,
                context: context,
                sampleType: record.route.sampleType.identifier
            ) else {
                return nil
            }
            return try Self.assembleDocumentGraph(
                for: record.route,
                evidence: HealthKitRecordingEvidence(
                    outputRole: "native-recording",
                    format: .locationTrackSamples,
                    title: "Workout route locations",
                    payload: payload
                ),
                context: context
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    static func beatIntervalPayload(
        seriesStart: Date,
        heartbeats: [HealthKitHeartbeat],
        sampleType: String
    ) throws -> Data {
        guard !heartbeats.isEmpty else {
            throw HealthKitConversionError.emptyRecordingSeries(sampleType: sampleType)
        }
        var writer = RecordingCSVWriter(columns: beatIntervalColumns)
        for heartbeat in heartbeats {
            // Composed in epoch seconds rather than by offsetting the Date: `Date` is anchored to
            // 2001, so offsetting one and reading it back as epoch seconds rounds twice and lands
            // a beat a fraction of a microsecond away from the instant it was recorded at.
            try writer.append([
                .number(seriesStart.timeIntervalSince1970 + heartbeat.timeSinceSeriesStart),
                .integer(heartbeat.precededByGap ? 1 : 0)
            ])
        }
        return writer.data()
    }

    /// The route's track, or `nil` when the deployment has not authorized disclosing one.
    static func locationTrackPayload(
        _ locations: [CLLocation],
        context: HealthKitConversionContext,
        sampleType: String
    ) throws -> Data? {
        guard context.routeDisclosurePolicy == .authorized else {
            return nil
        }
        guard !locations.isEmpty else {
            throw HealthKitConversionError.emptyRecordingSeries(sampleType: sampleType)
        }
        var writer = RecordingCSVWriter(columns: locationTrackColumns)
        for location in locations {
            try writer.append([
                .timestamp(location.timestamp),
                .number(location.coordinate.latitude),
                .number(location.coordinate.longitude),
                .number(location.altitude),
                .number(location.horizontalAccuracy),
                reported(location.verticalAccuracy),
                reported(location.speed),
                reported(location.speedAccuracy),
                reported(location.course),
                reported(location.courseAccuracy)
            ])
        }
        return writer.data()
    }

    static func assembleDocumentGraph(
        for sample: HKSample,
        evidence: HealthKitRecordingEvidence,
        context: HealthKitConversionContext
    ) throws -> HealthKitDocumentConversion {
        try validate(context: context)
        let envelope = try graphEnvelope(
            for: sample,
            context: context,
            outputRole: evidence.outputRole,
            outputDiscriminator: "single"
        )
        let artifactIdentity = try context.identityScope.sourceArtifact(
            adapterID: "healthkit",
            sourceType: sample.sampleType.identifier,
            repositoryScope: context.repositoryScope,
            nativeRecordID: envelope.sourceUUID,
            formatCode: evidence.format.rawValue,
            partIndex: 0
        )
        let document = try recordingDocument(
            for: sample,
            evidence: evidence,
            envelope: envelope,
            context: context,
            artifactIdentity: artifactIdentity
        )
        var provenance = try Self.provenance(
            sourceIdentifier: envelope.sourceRecord.fhirIdentifier,
            targetURL: envelope.primaryURL,
            converterURL: envelope.converterURL,
            sourceAuthorURL: envelope.sourceAuthorURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        let graph = try exchangeBundle(
            envelope: envelope,
            primary: ResourceProxy(with: document),
            provenance: provenance,
            context: context
        )
        return HealthKitDocumentConversion(
            sourceIdentifier: envelope.sourceRecord.fhirIdentifier,
            graphIdentifiers: HealthKitDocumentGraphIdentifiers(
                event: context.eventIdentifier.businessIdentifier,
                sourceRecord: envelope.sourceRecord,
                sourceOutput: envelope.primary,
                sourceArtifact: artifactIdentity,
                recordingDeviceSnapshot: envelope.recordingDevice?.identity,
                converterApplicationSnapshot: envelope.converterApplication.identity,
                converterHostSnapshot: envelope.converterHost.identity,
                sourceAuthorSnapshot: envelope.sourceAuthor?.author.identity,
                sourceAuthorHostSnapshot: envelope.sourceAuthor?.host?.identity,
                provenance: envelope.provenanceNode.identifier
            ),
            document: document,
            recordingDevice: envelope.recordingDevice?.resource,
            converterApplication: envelope.converterApplication.resource,
            converterHost: envelope.converterHost.resource,
            sourceAuthor: envelope.sourceAuthor?.author.resource,
            sourceAuthorHost: envelope.sourceAuthor?.host?.resource,
            provenance: provenance,
            graph: graph
        )
    }

    private static func recordingDocument(
        for sample: HKSample,
        evidence: HealthKitRecordingEvidence,
        envelope: GraphEnvelope,
        context: HealthKitConversionContext,
        artifactIdentity: BusinessIdentifier
    ) throws -> DocumentReference {
        let sourceTypeIdentifier = sample.sampleType.identifier
        var authors = envelope.recordingDeviceURL.map { [Reference(reference: $0.asFHIRStringPrimitive())] } ?? []
        authors.append(Reference(reference: envelope.converterURL.asFHIRStringPrimitive()))
        let typeCoding = if let clinicalRecordTypeCode = evidence.clinicalRecordTypeCode {
            Coding(
                code: clinicalRecordTypeCode.asFHIRStringPrimitive(),
                system: HealthKitRecordingDocumentContract.clinicalRecordTypeCodeSystem
            )
        } else {
            Coding(
                code: evidence.format.rawValue.asFHIRStringPrimitive(),
                system: HealthKitRecordingDocumentContract.formatCodeSystem
            )
        }
        var document = DocumentReference(
            author: authors,
            content: [DocumentReferenceContent(
                attachment: try attachment(evidence),
                format: Coding(
                    code: evidence.format.rawValue.asFHIRStringPrimitive(),
                    system: HealthKitRecordingDocumentContract.formatCodeSystem,
                    version: HealthKitRecordingDocumentContract.registryVersion.asFHIRStringPrimitive()
                )
            )],
            context: context.researchStudies.isEmpty
                ? nil
                : DocumentReferenceContext(related: context.researchStudies),
            date: FHIRPrimitive(try Instant(date: context.conversionInstant)),
            identifier: [
                envelope.sourceRecord.fhirIdentifier,
                envelope.primary.fhirIdentifier,
                artifactIdentity.fhirIdentifier
            ] + nativeIdentifiers(for: sample, policy: context.nativeIdentifierDisclosurePolicy),
            meta: Meta(profile: evidence.profiles),
            status: FHIRPrimitive(.current),
            subject: context.subject,
            type: CodeableConcept(coding: [typeCoding])
        )
        applySourceTypeLineage(sourceTypeIdentifier, to: &document)
        if let clinicalFHIRReleaseCode = evidence.clinicalFHIRReleaseCode {
            document.append(extension: Extension(
                    url: HealthKitContract.clinicalFHIRReleaseExtension,
                    value: .code(clinicalFHIRReleaseCode.asFHIRStringPrimitive())
                ))
        }
        document.id = context.repositoryIDs.document?.primitive
        return document
    }

    private static func attachment(_ evidence: HealthKitRecordingEvidence) throws -> Attachment {
        guard let size = Int32(exactly: evidence.payload.count) else {
            throw HealthKitConversionError.recordingPayloadTooLarge(byteCount: evidence.payload.count)
        }
        return Attachment(
            contentType: evidence.format.contentType.asFHIRStringPrimitive(),
            data: FHIRPrimitive(Base64Binary(with: evidence.payload)),
            hash: FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: evidence.payload)))),
            size: FHIRPrimitive(FHIRUnsignedInteger(size)),
            title: evidence.title.asFHIRStringPrimitive()
        )
    }

    /// CoreLocation reports an unavailable reading as a negative value, and the registry writes
    /// those columns empty rather than carrying a sentinel a reader would take for a measurement.
    private static func reported(_ value: Double) -> RecordingCSVWriter.Field {
        value < 0 ? .absent : .number(value)
    }
}

#endif

// swiftlint:enable multiline_literal_brackets type_contents_order
