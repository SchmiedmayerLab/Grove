//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import CryptoKit
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// Why a workout route cannot be carried, for a reason no registered input rule names (a route states no measurement
/// and the location-track columns no value domain), so the conversion reports it as `mobile-input.unclassified`.
enum WorkoutRouteFailure: Error {
    /// CoreLocation marks a fix's coordinate invalid with a negative horizontal accuracy.
    case invalidCoordinate
}


/// The parts of a source type's recording or clinical document that every document of the type shares, and the
/// builders that carry one record's bytes in it.
///
/// The bytes are carried exactly as HealthKit delivered them, or as the registry's column schema writes a series;
/// the guide: "Do not parse and reserialize, relabel, upgrade, downgrade, or otherwise rewrite those bytes."
@available(iOS 18, macOS 15, watchOS 11, *)
struct DocumentPlan: Sendable {
    /// The registered format of the carried bytes.
    let format: RegisteredRecordingFormat
    /// The DocumentReference before its content: status current, its profiles, its type and the source-type extension.
    let skeleton: DocumentReference
    /// The content's format coding.
    let formatCoding: Coding
    /// The attachment's title; a CDA document states its own and falls back to this one.
    let title: String

    /// The plan of documents of `format` claiming `profiles`, typed by `typeCoding`, else by their format.
    init(
        sourceType: HealthKitSourceType,
        format: RegisteredRecordingFormat,
        profiles: [FHIRPrimitive<Canonical>],
        typeCoding: Coding? = nil,
        title: String
    ) {
        let formatCoding = Coding(format.rawValue, system: RegisteredRecordingFormat.codeSystem)
        var skeleton = DocumentReference(
            content: [],
            meta: Meta(profile: profiles),
            status: FHIRPrimitive(.current),
            type: CodeableConcept(coding: [typeCoding ?? formatCoding])
        )
        skeleton.extension = [sourceType.lineage]
        self.format = format
        self.skeleton = skeleton
        self.formatCoding = formatCoding
        self.title = title
    }

    /// CoreLocation reports an unavailable reading as a negative value; the registry writes such a column empty
    /// rather than carrying a sentinel a reader would take for a measurement.
    private static func reported(_ value: Double) -> RecordingCSVWriter.Field {
        value < 0 ? .absent : .number(value)
    }

    /// A heartbeat series' beats in the plan's format, the registry's `beat-interval-series` column schema: one row per
    /// beat, its instant in epoch seconds and whether a gap preceded it. A series without beats is refused. The
    /// exporter's companion fingerprint digests exactly these bytes.
    func beatIntervals(seriesStart: Date, heartbeats: [HealthKitFHIRExporter.Record.Heartbeat]) throws -> Data {
        guard !heartbeats.isEmpty else {
            throw HealthKitConversionError.ValueFailure.emptyRecordingSeries
        }
        var writer = try RecordingCSVWriter(format: format)
        // Composed in epoch seconds rather than by offsetting the start: `Date` counts from 2001, so offsetting one
        // and reading it back as epoch seconds rounds twice and moves the beat.
        let start = seriesStart.timeIntervalSince1970
        for beat in heartbeats {
            try writer.append([.number(start + beat.timeSinceSeriesStart), .integer(beat.precededByGap ? 1 : 0)])
        }
        return writer.data()
    }

    /// A workout route's fixes in the plan's format, the registry's `location-track-samples` column schema, one row
    /// per fix. A route without fixes is refused. So is a route with a fix whose horizontal accuracy CoreLocation
    /// reports negative, its marker for an invalid coordinate: every row states a WGS 84 position and its radius of
    /// uncertainty, a column that cannot be empty, and no fix may be left out. The exporter's companion fingerprint
    /// digests exactly these bytes.
    func locationTrack(_ locations: [CLLocation]) throws -> Data {
        guard !locations.isEmpty else {
            throw HealthKitConversionError.ValueFailure.emptyRecordingSeries
        }
        var writer = try RecordingCSVWriter(format: format)
        for fix in locations {
            if fix.horizontalAccuracy < 0 {
                throw WorkoutRouteFailure.invalidCoordinate
            }
            try writer.append([
                .timestamp(fix.timestamp),
                .number(fix.coordinate.latitude),
                .number(fix.coordinate.longitude),
                .number(fix.altitude),
                .number(fix.horizontalAccuracy),
                Self.reported(fix.verticalAccuracy),
                Self.reported(fix.speed),
                Self.reported(fix.speedAccuracy),
                Self.reported(fix.course),
                Self.reported(fix.courseAccuracy)
            ])
        }
        return writer.data()
    }

    /// The document of a heartbeat series, carrying the intervals of its `beats`.
    func document(_ series: HKHeartbeatSeriesSample, beats: [HealthKitFHIRExporter.Record.Heartbeat]) throws -> DocumentReference {
        let payload = try beatIntervals(seriesStart: series.startDate, heartbeats: beats)
        return try document(payload, title: title, contentType: format.registeredContentType)
    }

    /// The document of a workout route, carrying the track of its `locations`.
    func document(locations: [CLLocation]) throws -> DocumentReference {
        try document(try locationTrack(locations), title: title, contentType: format.registeredContentType)
    }

    /// The document carrying `payload` under `title`, with its SHA-1 hash and size.
    private func document(_ payload: Data, title: String, contentType: String?) throws(HealthKitConversionError.ValueFailure) -> DocumentReference {
        guard let size = Int32(exactly: payload.count) else {
            throw .recordingPayloadTooLarge(byteCount: payload.count)
        }
        let attachment = Attachment(
            contentType: contentType?.asFHIRStringPrimitive(),
            data: FHIRPrimitive(Base64Binary(with: payload)),
            hash: FHIRPrimitive(Base64Binary(with: Data(Insecure.SHA1.hash(data: payload)))),
            size: FHIRPrimitive(FHIRUnsignedInteger(size)),
            title: title.asFHIRStringPrimitive()
        )
        var document = skeleton
        document.content = [DocumentReferenceContent(attachment: attachment, format: formatCoding)]
        return document
    }
}


#if !os(watchOS)
@available(iOS 18, macOS 15, watchOS 11, *)
extension DocumentPlan {
    /// The release code of a FHIR release the guide may admit, or `nil` for any other.
    private static func releaseCode(_ release: HKFHIRRelease) -> String? {
        switch release {
        case .dstu2: "dstu2"
        case .r4: "r4"
        default: nil
        }
    }

    /// The document carrying a clinical record's provider-issued FHIR resource: one JSON resource of an admitted
    /// release, typed by that release's media type. Grove never converts or claims conformance over it.
    func document(_ record: HKClinicalRecord) throws -> DocumentReference {
        guard let resource = record.fhirResource else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        guard let release = Self.releaseCode(resource.fhirVersion.fhirRelease),
              HealthKitContract.admittedClinicalFHIRReleaseCodes.contains(release) else {
            throw HealthKitConversionError.clinicalRecord(.unsupportedRelease)
        }
        do {
            try FHIRJSONResourcePayload.validate(resource.data)
        } catch {
            throw HealthKitConversionError.clinicalRecord(.undecodable)
        }
        return try document(resource.data, title: title, contentType: HealthKitContract.clinicalFHIRContentTypeByRelease[release])
    }

    /// The document carrying a CDA document, under the title it states, else the plan's. Only an `HKDocumentQuery`
    /// that asked for document data fills one in, so a sample from any other query is refused as empty.
    func document(_ sample: HKCDADocumentSample) throws -> DocumentReference {
        guard let document = sample.document, let data = document.documentData, !data.isEmpty else {
            throw HealthKitConversionError.clinicalRecord(.empty)
        }
        let stated = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return try self.document(data, title: stated.isEmpty ? title : stated, contentType: format.registeredContentType)
    }
}
#endif

#endif
