//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The closely related public summary input records stay together so the structured producer facade
// is readable in one place.
// swiftlint:disable file_types_order

public import Foundation
public import GroveFHIRContract


/// A content-free SensorKit messages-usage interval summary: counts only, never content or identities.
public struct SensorKitMessagesUsageRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let timestamp: Date
    public let durationSeconds: Double
    public let totalIncomingMessages: Int
    public let totalOutgoingMessages: Int
    public let totalUniqueContacts: Int
    public let nativeRecording: SensorKitNativeRecording?

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        timestamp: Date,
        durationSeconds: Double,
        totalIncomingMessages: Int,
        totalOutgoingMessages: Int,
        totalUniqueContacts: Int,
        nativeRecording: SensorKitNativeRecording? = nil
    ) {
        self.sourceRecordID = sourceRecordID
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalIncomingMessages = totalIncomingMessages
        self.totalOutgoingMessages = totalOutgoingMessages
        self.totalUniqueContacts = totalUniqueContacts
        self.nativeRecording = nativeRecording
    }
}


/// A content-free SensorKit phone-usage interval summary: the total call duration plus counts, never identities.
public struct SensorKitPhoneUsageRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let timestamp: Date
    public let durationSeconds: Double
    public let totalIncomingCalls: Int
    public let totalOutgoingCalls: Int
    public let totalPhoneCallDurationSeconds: Double
    public let totalUniqueContacts: Int
    public let nativeRecording: SensorKitNativeRecording?

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        timestamp: Date,
        durationSeconds: Double,
        totalIncomingCalls: Int,
        totalOutgoingCalls: Int,
        totalPhoneCallDurationSeconds: Double,
        totalUniqueContacts: Int,
        nativeRecording: SensorKitNativeRecording? = nil
    ) {
        self.sourceRecordID = sourceRecordID
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalIncomingCalls = totalIncomingCalls
        self.totalOutgoingCalls = totalOutgoingCalls
        self.totalPhoneCallDurationSeconds = totalPhoneCallDurationSeconds
        self.totalUniqueContacts = totalUniqueContacts
        self.nativeRecording = nativeRecording
    }
}


/// A content-free SensorKit keyboard-metrics interval summary. The summary is lossy, so the
/// exact native recording is mandatory; no typed content, emoji identity, or sentiment is represented.
public struct SensorKitKeyboardMetricsRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let timestamp: Date
    public let durationSeconds: Double
    public let totalTypingDurationSeconds: Double
    public let totalWords: Int
    public let totalAlteredWords: Int
    public let totalTaps: Int
    public let totalDeletes: Int
    public let totalEmojis: Int
    public let totalAutocorrections: Int
    public let totalPauses: Int
    public let totalTypingEpisodes: Int
    public let typingSpeed: Double
    public let nativeRecording: SensorKitNativeRecording

    public init(
        sourceRecordID: SensorKitSourceRecordID,
        timestamp: Date,
        durationSeconds: Double,
        totalTypingDurationSeconds: Double,
        totalWords: Int,
        totalAlteredWords: Int,
        totalTaps: Int,
        totalDeletes: Int,
        totalEmojis: Int,
        totalAutocorrections: Int,
        totalPauses: Int,
        totalTypingEpisodes: Int,
        typingSpeed: Double,
        nativeRecording: SensorKitNativeRecording
    ) {
        self.sourceRecordID = sourceRecordID
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalTypingDurationSeconds = totalTypingDurationSeconds
        self.totalWords = totalWords
        self.totalAlteredWords = totalAlteredWords
        self.totalTaps = totalTaps
        self.totalDeletes = totalDeletes
        self.totalEmojis = totalEmojis
        self.totalAutocorrections = totalAutocorrections
        self.totalPauses = totalPauses
        self.totalTypingEpisodes = totalTypingEpisodes
        self.typingSpeed = typingSpeed
        self.nativeRecording = nativeRecording
    }
}


/// A SensorKit sleep session interval assertion; the source publishes only the session bounds.
public struct SensorKitSleepSessionRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let session: DateInterval

    public init(sourceRecordID: SensorKitSourceRecordID, session: DateInterval) {
        self.sourceRecordID = sourceRecordID
        self.session = session
    }
}


/// A coverage summary of one SensorKit accelerometer batch; the exact CSV recording carries the signal.
public struct SensorKitAccelerometerRecord: Sendable {
    /// What an accelerometer recording's rows state, read in one pass over them.
    struct Summary: Sendable {
        let coverage: DateInterval
        let sampleCount: Int
        let batchCount: Int

        /// Requires every row to carry a timestamp, x, y and z, an unsigned batch identifier and a device.
        init(_ reader: RecordingCSVReader) throws {
            try self.init { try reader.rows.forEach($0) }
        }

        init(_ recording: SensorKitNativeRecording) throws {
            try self.init(readRows: recording.readRows)
        }

        private init(readRows: (_ onRow: (RecordingCSVReader.Row) throws -> Void) throws -> Void) throws {
            var earliest = Double.infinity
            var latest = -Double.infinity
            var batches = RecordingBatchCounter()
            var sampleCount = 0
            try readRows { row in
                let timestamp = try row.requiredNumber("timestamp")
                _ = try row.requiredNumber("x")
                _ = try row.requiredNumber("y")
                _ = try row.requiredNumber("z")
                guard let identifier = row["identifier"].flatMap(UInt64.init) else {
                    throw RecordingCSVReader.RowValueError.malformedInteger(
                        column: "identifier",
                        value: row["identifier"] ?? ""
                    )
                }
                guard let device = row["device"], !device.isEmpty else {
                    throw RecordingCSVReader.RowValueError.absent("device")
                }
                earliest = min(earliest, timestamp)
                latest = max(latest, timestamp)
                try batches.add(device: device, identifier: identifier)
                sampleCount += 1
            }
            guard sampleCount > 0 else { throw SensorKitRecordError.emptySamples }
            self.coverage = DateInterval(
                start: Date(timeIntervalSince1970: earliest),
                end: Date(timeIntervalSince1970: latest)
            )
            self.sampleCount = sampleCount
            self.batchCount = batches.count
        }
    }

    public let sourceRecordID: SensorKitSourceRecordID
    public let coverage: DateInterval
    public let sampleCount: Int
    public let batchCount: Int
    public let nativeRecording: SensorKitNativeRecording

    /// Creates the summary by parsing the exact registered recording.
    ///
    /// Counts and coverage are deliberately not caller inputs: the attached payload is the sole
    /// authority for every summary fact projected into FHIR.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        nativeRecording: SensorKitNativeRecording
    ) throws {
        guard nativeRecording.format == .triaxialAccelerationSamples else {
            throw SensorKitRecordError.invalidRecordingFormat
        }
        self.init(sourceRecordID: sourceRecordID, nativeRecording: nativeRecording, summary: try Summary(nativeRecording))
    }

    /// `summary` is what the rows of `nativeRecording`, an accelerometer recording, state, read by a caller that
    /// already parsed its bytes.
    init(sourceRecordID: SensorKitSourceRecordID, nativeRecording: SensorKitNativeRecording, summary: Summary) {
        self.sourceRecordID = sourceRecordID
        self.coverage = summary.coverage
        self.sampleCount = summary.sampleCount
        self.batchCount = summary.batchCount
        self.nativeRecording = nativeRecording
    }
}


/// A coverage summary of one SensorKit wrist-temperature session; the tabular recording carries
/// the samples.
///
/// The session is a wrist skin measurement taken over a sleep interval. It is deliberately not a
/// body temperature or a basal body temperature, and Grove binds it to neither: the summary
/// counts what the recording holds and names the algorithm that produced it.
public struct SensorKitWristTemperatureRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let coverage: DateInterval
    public let sampleCount: Int
    /// The `SRWristTemperatureSession.version` that produced the session.
    public let algorithmVersion: String
    public let nativeRecording: SensorKitNativeRecording

    /// Creates the summary by parsing the exact registered recording.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        algorithmVersion: String,
        nativeRecording: SensorKitNativeRecording
    ) throws {
        guard nativeRecording.format == .wristTemperatureSamples else {
            throw SensorKitRecordError.invalidRecordingFormat
        }
        var earliest = Double.infinity
        var latest = -Double.infinity
        var sampleCount = 0
        try nativeRecording.readRows { row in
            _ = try row.requiredNumber("value")
            _ = try row.requiredNumber("errorEstimate")
            let timestamp = try row.requiredNumber("timestamp")
            earliest = min(earliest, timestamp)
            latest = max(latest, timestamp)
            sampleCount += 1
        }
        guard sampleCount > 0 else { throw SensorKitRecordError.emptySamples }
        self.sourceRecordID = sourceRecordID
        self.coverage = DateInterval(start: Date(timeIntervalSince1970: earliest), end: Date(timeIntervalSince1970: latest))
        self.sampleCount = sampleCount
        self.algorithmVersion = algorithmVersion
        self.nativeRecording = nativeRecording
    }
}


/// A coverage summary of one SensorKit photoplethysmogram batch; the exact binary recording carries the signal.
public struct SensorKitPPGRecord: Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let coverage: DateInterval
    public let recordCount: Int
    public let opticalSampleCount: Int
    public let accelerometerSampleCount: Int
    public let nativeRecording: SensorKitNativeRecording

    /// Creates the summary by strictly decoding the exact registered recording.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        nativeRecording: SensorKitNativeRecording
    ) throws {
        try self.init(sourceRecordID: sourceRecordID, nativeRecording: nativeRecording, decoded: nil)
    }

    /// `decoded` is the strict decode of `nativeRecording`'s bytes when the caller already made it.
    init(
        sourceRecordID: SensorKitSourceRecordID,
        nativeRecording: SensorKitNativeRecording,
        decoded: SensorKitPPGRecording?
    ) throws {
        guard nativeRecording.format == .photoplethysmogramSamples else {
            throw SensorKitRecordError.invalidRecordingFormat
        }
        let recording = try decoded ?? SensorKitPPGRecording(data: nativeRecording.decodedPayload())
        guard let summary = recording.summary else {
            throw SensorKitRecordError.emptySamples
        }
        self.sourceRecordID = sourceRecordID
        self.coverage = summary.coverage
        self.recordCount = summary.recordCount
        self.opticalSampleCount = summary.opticalSampleCount
        self.accelerometerSampleCount = summary.accelerometerSampleCount
        self.nativeRecording = nativeRecording
    }
}
