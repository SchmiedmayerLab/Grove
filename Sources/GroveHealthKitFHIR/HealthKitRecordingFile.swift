//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import CoreLocation
public import Foundation
public import GroveFHIRContract
public import HealthKit


/// A complete workout route or heartbeat series, written into a recording file without retaining its samples or its
/// complete CSV in memory.
///
/// Export one as ``HealthKitFHIRExporter/Record/fileRecording(_:)``. The file is a temporary snapshot; copy it into
/// durable storage before acknowledging collection.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitRecordingFile: Sendable {
    /// Why a recording file could not be created.
    public enum RecordingError: Error, Equatable, Sendable {
        /// The attachment path is not a relative reference without empty or dot segments, a query or a fragment.
        case invalidRelativePath
        /// The sequence delivered another number of elements than the series sample states.
        case incompleteSeries
    }

    /// The recording's bytes in the sample's registered format.
    public let file: RecordingFile
    /// The relative path the recording's attachment URL states.
    public let relativePath: String
    /// The registered format of the recording.
    public let format: RegisteredRecordingFormat
    let sample: HKSeriesSample

    /// Writes a workout route's locations as a location track.
    ///
    /// The sequence must deliver exactly the route's number of locations. A query error, cancellation, an invalid row or
    /// an exceeded byte limit throws instead of returning a partial recording.
    ///
    /// - Parameters:
    ///   - route: The workout route.
    ///   - locations: The route's locations, in order, as a demand-driven sequence.
    ///   - relativePath: The relative path the attachment URL states.
    ///   - maximumByteCount: The most bytes the recording may take, between 1 and `Int32.max`.
    @concurrent
    public static func workoutRoute(
        _ route: HKWorkoutRoute,
        locations: some AsyncSequence<CLLocation, any Error> & Sendable,
        relativePath: String,
        maximumByteCount: Int
    ) async throws -> Self {
        try await recording(
            of: route,
            format: .locationTrackSamples,
            elements: locations,
            relativePath: relativePath,
            maximumByteCount: maximumByteCount,
            fields: DocumentPlan.locationFields
        )
    }

    /// Writes a heartbeat series' beats as a beat interval series.
    ///
    /// The sequence must deliver exactly the series' number of beats. A query error, cancellation, an invalid row or an
    /// exceeded byte limit throws instead of returning a partial recording.
    ///
    /// - Parameters:
    ///   - series: The heartbeat series.
    ///   - beats: The series' beats, in order, as a demand-driven sequence.
    ///   - relativePath: The relative path the attachment URL states.
    ///   - maximumByteCount: The most bytes the recording may take, between 1 and `Int32.max`.
    @concurrent
    public static func heartbeatSeries(
        _ series: HKHeartbeatSeriesSample,
        beats: some AsyncSequence<HealthKitFHIRExporter.Record.Heartbeat, any Error> & Sendable,
        relativePath: String,
        maximumByteCount: Int
    ) async throws -> Self {
        let start = series.startDate.timeIntervalSince1970
        return try await recording(
            of: series,
            format: .beatIntervalSeries,
            elements: beats,
            relativePath: relativePath,
            maximumByteCount: maximumByteCount
        ) { DocumentPlan.heartbeatFields($0, start: start) }
    }

    // The sample, its format and path, the byte limit and the row mapping each vary by recording kind.
    @concurrent
    // swiftlint:disable:next function_parameter_count
    private static func recording<Element>(
        of sample: HKSeriesSample,
        format: RegisteredRecordingFormat,
        elements: some AsyncSequence<Element, any Error> & Sendable,
        relativePath: String,
        maximumByteCount: Int,
        fields: @Sendable (Element) -> [RecordingCSVWriter.Field]
    ) async throws -> Self {
        guard isRelativeAttachmentPath(relativePath) else {
            throw RecordingError.invalidRelativePath
        }
        guard sample.count >= 1 else {
            throw HealthKitConversionError.ValueFailure.emptyRecordingSeries
        }
        var writer = try RecordingCSVFileWriter(format: format, maximumByteCount: maximumByteCount)
        var count = 0
        for try await element in elements {
            guard count < sample.count else {
                throw RecordingError.incompleteSeries
            }
            try writer.append(fields(element))
            count += 1
        }
        guard count == sample.count else {
            throw RecordingError.incompleteSeries
        }
        let file = try writer.finish()
        return Self(file: file, relativePath: relativePath, format: format, sample: sample)
    }
}

#endif
