//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


/// Exact provider JSON in an immutable file, with a relative attachment locator owned by the upload queue.
/// The caller persists the file with the emitted record and may compress its transfer without changing source bytes.
public struct ProviderNativeRecording: Sendable {
    /// A native stream the guide admits as a recording.
    public enum Source: String, CaseIterable, Sendable {
        /// Google Health heart rate.
        case googleHeartRate = "google-health-api/heart-rate"
        /// Oura heart rate.
        case ouraHeartRate = "oura/heartrate"
        /// Withings intraday activity.
        case withingsActivity = "withings/activityIntraday"
        /// Withings intraday sleep.
        case withingsSleep = "withings/sleepIntraday"
    }

    /// The period a recording covers, as its provider states it.
    public enum Interval: Sendable, Hashable {
        /// A Withings period, from the provider's Unix timestamps.
        case dates(DateInterval)
        /// An Oura or Google Health period, keeping the provider's timestamp spelling, UTC offset and digits.
        case timestamps(ProviderInterval)
    }

    /// Why a native recording is invalid.
    public enum ValidationError: Error, Equatable, Sendable {
        /// The identifier is empty.
        case invalidIdentifier
        /// The title is blank.
        case invalidTitle
        /// The interval is empty, or it is not the representation its provider states: dates for Withings and
        /// timestamps for Oura and Google Health.
        case invalidInterval
        /// The attachment path is not a relative reference without empty or dot segments, a query, a fragment or a
        /// percent-encoded byte.
        case invalidPath
        /// The byte limit is outside 1 through ``ProviderNativeRecording/maximumJSONByteCount``.
        case invalidByteLimit
        /// The file exceeds the byte limit.
        case payloadTooLarge
        /// The file is not valid JSON.
        case invalidJSON
    }

    /// JSON grammar validation is bounded before reading. It does not sanitize or reinterpret vendor fields.
    public static let maximumJSONByteCount = 64 * 1024 * 1024

    /// The recording's native identifier, or a persisted import key.
    public let id: String
    /// The recording's stream.
    public let source: Source
    /// The attachment title.
    public let title: String
    /// The exact provider JSON.
    public let file: RecordingFile
    /// The relative path the attachment URL states.
    public let attachmentPath: String
    /// The period the recording covers, if known.
    public let interval: Interval?

    /// Creates a native recording, validating its JSON grammar within the byte limit.
    ///
    /// The caller asserts the payload's admission; Grove neither sanitizes nor reinterprets the provider's fields.
    ///
    /// - Parameters:
    ///   - id: The recording's native identifier, or a persisted import key.
    ///   - source: The recording's stream.
    ///   - title: The attachment title.
    ///   - file: The exact provider JSON.
    ///   - attachmentPath: The relative path the attachment URL states.
    ///   - interval: The period the recording covers, in the representation its provider states, if known.
    ///   - maximumByteCount: The most bytes the JSON may hold, between 1 and ``maximumJSONByteCount``.
    ///   - admission: The caller's authorization to attach the payload.
    /// - Throws: A ``ValidationError``, or `CancellationError` when the task is cancelled during validation.
    public init(
        id: String,
        source: Source,
        title: String,
        file: RecordingFile,
        attachmentPath: String,
        interval: Interval? = nil,
        maximumByteCount: Int = maximumJSONByteCount,
        admission: RecordingPayloadAdmission
    ) throws {
        guard !id.isEmpty else { throw ValidationError.invalidIdentifier }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.invalidTitle }
        guard isRelativeAttachmentPath(attachmentPath) else { throw ValidationError.invalidPath }
        guard (1...Self.maximumJSONByteCount).contains(maximumByteCount) else { throw ValidationError.invalidByteLimit }
        guard file.byteCount <= maximumByteCount else { throw ValidationError.payloadTooLarge }
        if let interval, !interval.isValid(for: source) {
            throw ValidationError.invalidInterval
        }
        do {
            var scanner = try StrictJSONScanner(file.decodedPayload(maximumByteCount: maximumByteCount))
            try scanner.validate()
        } catch {
            try Task.checkCancellation()
            throw ValidationError.invalidJSON
        }
        _ = admission
        self.id = id
        self.source = source
        self.title = title
        self.file = file
        self.attachmentPath = attachmentPath
        self.interval = interval
    }
}


extension ProviderNativeRecording.Interval {
    fileprivate func isValid(for source: ProviderNativeRecording.Source) -> Bool {
        switch (self, source) {
        case (.dates(let interval), .withingsActivity), (.dates(let interval), .withingsSleep): interval.duration > 0
        case (.timestamps, .ouraHeartRate), (.timestamps, .googleHeartRate): true
        case (.dates, _), (.timestamps, _): false
        }
    }
}
