//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape, and members are ordered to read as a narrative
// rather than by kind: each entry point precedes the builders it uses.
// swiftlint:disable multiline_literal_brackets type_contents_order file_types_order

#if canImport(HealthKit)

import CoreLocation
import CryptoKit
import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// The published payload of one recording document, ready to be carried.
struct HealthKitRecordingEvidence: Sendable {
    let outputRole: String
    let format: RegisteredRecordingFormat
    let title: String
    let payload: Data
    let profiles: [FHIRPrimitive<Canonical>]
    let clinicalRecordTypeCode: String?
    let clinicalFHIRReleaseCode: String?

    var contentType: String? {
        if format == .fhirResource {
            guard let clinicalFHIRReleaseCode else {
                return nil
            }
            return HealthKitContract.clinicalFHIRContentTypeByRelease[clinicalFHIRReleaseCode]
        }
        return format.registeredContentType
    }

    init(
        outputRole: String,
        format: RegisteredRecordingFormat,
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
enum HealthKitRecordingDocumentContract {
    static let profile = Profile.healthkitRecordingDocument
    static let formatCodeSystem = FHIRPrimitive(FHIRURI(
        stringLiteral: RecordingFormatContract.recordingFormatCodeSystem
    ))
    static let clinicalRecordTypeCodeSystem: FHIRPrimitive<FHIRURI> =
        "https://grovealliance.org/fhir/healthkit/CodeSystem/healthkit-clinical-record-type"
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
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

    static func beatIntervalPayload(
        seriesStart: Date,
        heartbeats: [HealthKitHeartbeat]
    ) throws -> Data {
        guard !heartbeats.isEmpty else {
            throw HealthKitValueFailure.emptyRecordingSeries
        }
        var writer = try RecordingCSVWriter(format: .beatIntervalSeries)
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

    /// The route's track in the registry's `location-track-samples` column schema.
    static func locationTrackPayload(_ locations: [CLLocation]) throws -> Data {
        guard !locations.isEmpty else {
            throw HealthKitValueFailure.emptyRecordingSeries
        }
        var writer = try RecordingCSVWriter(format: .locationTrackSamples)
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

    /// The DocumentReference content of one recording document; the envelope adds identities,
    /// subject, authors, date and study context.
    static func recordingDocument(evidence: HealthKitRecordingEvidence, sourceTypeIdentifier: String) throws -> DocumentReference {
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
            content: [DocumentReferenceContent(
                attachment: try attachment(evidence),
                format: Coding(
                    code: evidence.format.rawValue.asFHIRStringPrimitive(),
                    system: HealthKitRecordingDocumentContract.formatCodeSystem
                )
            )],
            meta: Meta(profile: evidence.profiles),
            status: FHIRPrimitive(.current),
            type: CodeableConcept(coding: [typeCoding])
        )
        applySourceTypeLineage(sourceTypeIdentifier, to: &document)
        return document
    }

    private static func attachment(_ evidence: HealthKitRecordingEvidence) throws -> Attachment {
        guard let size = Int32(exactly: evidence.payload.count) else {
            throw HealthKitValueFailure.recordingPayloadTooLarge(byteCount: evidence.payload.count)
        }
        return Attachment(
            contentType: evidence.contentType?.asFHIRStringPrimitive(),
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
