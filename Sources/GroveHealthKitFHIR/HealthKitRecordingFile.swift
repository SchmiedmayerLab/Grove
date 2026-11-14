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


/// A complete HealthKit recording or original document staged in an immutable file.
/// Series writers stream their samples; clinical APIs already supply their payload as Data.
/// The temporary immutable file must be copied into durable queue storage before acknowledging collection.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitRecordingFile: Sendable {
    public enum RecordingError: Error, Equatable, Sendable {
        case invalidRelativePath
        case incompleteSeries
    }

    public let file: RecordingFile
    public let relativePath: String
    public let format: RegisteredRecordingFormat
    let sample: HKSample
    let attachmentTitle: String?
    let attachmentContentType: String?

    init(
        file: RecordingFile,
        relativePath: String,
        format: RegisteredRecordingFormat,
        sample: HKSample,
        attachmentTitle: String? = nil,
        attachmentContentType: String? = nil
    ) {
        self.file = file
        self.relativePath = relativePath
        self.format = format
        self.sample = sample
        self.attachmentTitle = attachmentTitle
        self.attachmentContentType = attachmentContentType
    }

    /// Pulls each fix into the registered location-track encoding and requires the complete native sample count.
    /// Cancellation, query errors, invalid rows and capacity failures throw without returning a successful prefix.
    nonisolated(nonsending) public static func workoutRoute(
        _ route: HKWorkoutRoute,
        locations: some AsyncSequence<CLLocation, any Error>,
        relativePath: String,
        maximumByteCount: Int
    ) async throws -> Self {
        try validate(path: relativePath, count: route.count)
        let format = RegisteredRecordingFormat.locationTrackSamples
        var writer = try RecordingCSVFileWriter(format: format, maximumByteCount: maximumByteCount)
        var count = 0
        for try await fix in locations {
            try Task.checkCancellation()
            guard count < route.count else { throw RecordingError.incompleteSeries }
            try writer.append(DocumentPlan.locationFields(fix))
            count += 1
        }
        guard count == route.count else { throw RecordingError.incompleteSeries }
        return try Self(file: writer.finish(), relativePath: relativePath, format: format, sample: route)
    }

    /// Pulls the complete beat series into its registered encoding without collecting the beats.
    nonisolated(nonsending) public static func heartbeatSeries(
        _ series: HKHeartbeatSeriesSample,
        beats: some AsyncSequence<HealthKitFHIRExporter.Record.Heartbeat, any Error>,
        relativePath: String,
        maximumByteCount: Int
    ) async throws -> Self {
        try validate(path: relativePath, count: series.count)
        let format = RegisteredRecordingFormat.beatIntervalSeries
        var writer = try RecordingCSVFileWriter(format: format, maximumByteCount: maximumByteCount)
        var count = 0
        let start = series.startDate.timeIntervalSince1970
        for try await beat in beats {
            try Task.checkCancellation()
            guard count < series.count else { throw RecordingError.incompleteSeries }
            try writer.append(DocumentPlan.heartbeatFields(beat, start: start))
            count += 1
        }
        guard count == series.count else { throw RecordingError.incompleteSeries }
        return try Self(file: writer.finish(), relativePath: relativePath, format: format, sample: series)
    }

    private static func validate(path: String, count: Int) throws {
        try Task.checkCancellation()
        guard RecordingFile.isRelativeAttachmentPath(path) else { throw RecordingError.invalidRelativePath }
        guard count > 0 else { throw HealthKitConversionError.ValueFailure.emptyRecordingSeries }
    }
}

#endif
