//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
public import Foundation
public import GroveFHIRContract
public import SensorKit


extension SensorKitTabularRecording {
    /// A complete registered tabular recording generated directly into an owned temporary file.
    ///
    /// Uses the same sample mappings and retry-evidence bytes as the Data representation, without
    /// materializing the sample sequence, all intervals, or the complete CSV. Synchronous disk work
    /// belongs on the caller's background executor. Copy into durable queue storage before acknowledging collection.
    public struct File: Sendable {
        /// The SensorKit source token of the recorded samples, such as `SRSensor.accelerometer`.
        public let sourceToken: String
        /// The tabular registry format the file is written in.
        public let format: RegisteredRecordingFormat
        /// The complete recording: the header row and one row per sample, in source order.
        public let file: RecordingFile
        /// The interval from the earliest sample start to the latest sample end.
        public let effectivePeriod: DateInterval
        private let projection: StructuredProjection
        private let retryEvidencePrefix: Data

        /// Encodes a homogeneous fetched sequence once, with an explicit total recording byte budget.
        ///
        /// - Parameters:
        ///   - samples: The fetched samples, in source order; at least one is required.
        ///   - deviceProductType: The product type of the device that recorded the samples.
        ///   - maximumByteCount: The most bytes of the complete recording, between 1 and `Int32.max`.
        public init<Samples: Sequence>(
            samples: Samples,
            deviceProductType: String,
            maximumByteCount: Int
        ) throws where Samples.Element: SensorKitTabularSample {
            var writer = try RecordingCSVFileWriter(format: Samples.Element.groveRecordingFormat, maximumByteCount: maximumByteCount)
            var coverage = Coverage()
            for sample in samples {
                try writer.append(sample.groveRecordingFields(deviceProductType: deviceProductType))
                coverage.include(sample.timeRange)
            }
            self.effectivePeriod = try coverage.period()
            self.sourceToken = Samples.Element.groveSourceToken
            self.format = Samples.Element.groveRecordingFormat
            self.file = try writer.finish()
            self.projection = format == .triaxialAccelerationSamples ? .accelerometer : .none
            self.retryEvidencePrefix = Data()
        }

        /// Encodes a wrist-temperature session, retaining its algorithm version in the retry evidence.
        ///
        /// - Parameters:
        ///   - session: The session; it must contain at least one temperature.
        ///   - maximumByteCount: The most bytes of the complete recording, between 1 and `Int32.max`.
        @available(iOS 17, *)
        public init(wristTemperature session: SRWristTemperatureSession, maximumByteCount: Int) throws {
            var writer = try RecordingCSVFileWriter(format: .wristTemperatureSamples, maximumByteCount: maximumByteCount)
            var coverage = Coverage()
            for sample in session.temperatures {
                try writer.append(SensorKitTabularRecording.wristTemperatureFields(sample))
                coverage.include(sample.timestamp..<sample.timestamp)
            }
            self.effectivePeriod = try coverage.period()
            self.sourceToken = SensorKitTabularRecording.wristTemperatureSourceToken
            self.format = .wristTemperatureSamples
            self.file = try writer.finish()
            self.projection = .wristTemperature(algorithmVersion: session.version)
            self.retryEvidencePrefix = SensorKitTabularRecording.wristTemperatureEvidencePrefix(version: session.version)
        }

        /// Supplies exactly the Data representation's retry evidence, in source order, without collecting it.
        /// The consumer controls retention. A thrown error or cancellation stops delivery without modifying the file.
        public func readRetryEvidenceChunks(_ consume: (Data) throws -> Void) throws {
            try Task.checkCancellation()
            if !retryEvidencePrefix.isEmpty { try consume(retryEvidencePrefix) }
            try file.readChunks(consume)
        }

        /// Builds the same structured summary or raw document, referencing the file at an archive-relative path.
        /// File failures and a ``SensorKitSummaryError`` propagate; they must not be treated as clinical record refusals.
        ///
        /// The file was validated while it was written, so the recording is not parsed again to check it; an
        /// accelerometer summary reads it once for its facts.
        ///
        /// - Parameters:
        ///   - sourceRecordID: The identity of the source batch.
        ///   - title: The attachment title.
        ///   - sidecarPath: The archive-relative path the file is stored at.
        ///   - admission: The caller's authorization to attach the raw recording.
        public func sensorKitRecord(
            sourceRecordID: SensorKitSourceRecordID,
            title: String,
            sidecarPath: String,
            admission: RecordingPayloadAdmission
        ) throws -> SensorKitRecord {
            // The file writer already validated the exact registered grammar, so the override skips a second
            // parse. Summary constructors read the immutable file for clinical facts and enforce every
            // required-value check.
            let native = try SensorKitNativeRecording(
                title: title,
                format: format,
                payload: .file(path: sidecarPath, contents: file),
                admission: admission
            ) { _ in }
            return try projection.record(
                sourceRecordID: sourceRecordID,
                nativeRecording: native,
                sourceToken: sourceToken,
                effectivePeriod: effectivePeriod
            )
        }
    }
}


extension SensorKitTabularRecording.File {
    private struct Coverage {
        private var start: Date?
        private var end: Date?

        mutating func include(_ interval: Range<Date>) {
            start = min(start ?? interval.lowerBound, interval.lowerBound)
            end = max(end ?? interval.upperBound, interval.upperBound)
        }

        func period() throws -> DateInterval {
            guard let start, let end else { throw SensorKitRecordError.emptySamples }
            return DateInterval(start: start, end: end)
        }
    }
}
#endif
