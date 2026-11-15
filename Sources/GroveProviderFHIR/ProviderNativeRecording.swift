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
    public enum Source: String, CaseIterable, Sendable {
        case googleHeartRate = "google-health-api/heart-rate"
        case ouraHeartRate = "oura/heartrate"
        case withingsActivity = "withings/activityIntraday"
        case withingsSleep = "withings/sleepIntraday"
    }

    public enum ValidationError: Error, Equatable {
        case invalidTitle
        case invalidPath
        case invalidByteLimit
        case payloadTooLarge
        case invalidJSON
    }

    /// JSON grammar validation is bounded before reading. It does not sanitize or reinterpret vendor fields.
    public static let maximumJSONByteCount = 64 * 1024 * 1024

    public let id: String
    public let source: Source
    public let title: String
    public let file: RecordingFile
    public let attachmentPath: String
    public let interval: DateInterval?

    public init(
        id: String,
        source: Source,
        title: String,
        file: RecordingFile,
        attachmentPath: String,
        interval: DateInterval? = nil,
        maximumByteCount: Int = maximumJSONByteCount,
        admission: RecordingPayloadAdmission
    ) throws {
        guard !id.isEmpty else { throw ProviderConversionError.invalidNativeIdentifier }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.invalidTitle }
        guard RecordingFile.isRelativeAttachmentPath(attachmentPath) else { throw ValidationError.invalidPath }
        guard (1...Self.maximumJSONByteCount).contains(maximumByteCount) else { throw ValidationError.invalidByteLimit }
        guard file.byteCount <= maximumByteCount else { throw ValidationError.payloadTooLarge }
        if let interval, interval.duration <= 0 { throw ProviderConversionError.invalidInterval }
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
