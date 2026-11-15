//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The private Codable envelopes follow the public preparation facade in this platform bridge.
// swiftlint:disable file_types_order

#if os(iOS)
public import Foundation
import GroveFHIRContract
public import GroveSensorKit
public import SensorKit


extension SensorKitPreparedStructuredRecord {
    /// Prepares a keyboard-metrics report: its content-free summary and, as the mandatory native recording, every
    /// field of the report under the name of the `SRKeyboardMetrics` property it was read from.
    @available(iOS 18, *)
    public init(keyboardMetrics report: SRKeyboardMetrics.SafeRepresentation) throws {
        func count(_ key: SRKeyboardMetrics.SafeRepresentation.Count) throws -> Int {
            guard let value = report.counts[key] else {
                throw SensorKitRecordError.missingProviderValue("keyboardMetrics.\(key.rawValue)")
            }
            return value
        }
        let totalWords = try count(.totalWords)
        let totalAlteredWords = try count(.totalAlteredWords)
        let totalTaps = try count(.totalTaps)
        let totalDeletes = try count(.totalDeletes)
        let totalEmojis = try count(.totalEmojis)
        let totalAutocorrections = try count(.totalAutoCorrections)
        let totalPauses = try count(.totalPauses)
        let totalTypingEpisodes = try count(.totalTypingEpisodes)
        self.init(nativePayload: try Self.encodeJSON(KeyboardMetricsEvidence(report: report))) { sourceRecordID, nativeRecording in
            guard let nativeRecording else {
                throw SensorKitRecordError.missingProviderValue("keyboardMetrics.nativeRecording")
            }
            return .keyboardMetrics(SensorKitKeyboardMetricsRecord(
                sourceRecordID: sourceRecordID,
                timestamp: report.timestamp,
                durationSeconds: report.duration,
                totalTypingDurationSeconds: report.totalTypingDuration,
                totalWords: totalWords,
                totalAlteredWords: totalAlteredWords,
                totalTaps: totalTaps,
                totalDeletes: totalDeletes,
                totalEmojis: totalEmojis,
                totalAutocorrections: totalAutocorrections,
                totalPauses: totalPauses,
                totalTypingEpisodes: totalTypingEpisodes,
                typingSpeed: report.typingSpeed,
                nativeRecording: nativeRecording
            ))
        }
    }

    /// Prepares a face-metrics sample as a native recording of its session facts and expressions.
    ///
    /// `SRFaceMetrics.faceAnchor` is not part of the sample (see `SRFaceMetrics.SafeRepresentation`), so the recording
    /// does not carry it.
    @available(iOS 18, *)
    public init(faceMetrics sample: SRFaceMetrics.SafeRepresentation) throws {
        try self.init(
            raw: FaceMetricsEvidence(sample),
            sourceToken: "SRSensor.faceMetrics",
            field: "faceMetrics",
            timeRange: sample.timeRange
        )
    }

    /// Prepares a media event as a native recording of its media identifier and event type.
    @available(iOS 18, *)
    public init(mediaEvent event: SRMediaEvent.SafeRepresentation) throws {
        try self.init(
            raw: MediaEventEvidence(event),
            sourceToken: "SRSensor.mediaEvents",
            field: "mediaEvents",
            timeRange: event.timeRange
        )
    }

    /// Prepares a speech-metrics sample as a native recording of every field SensorKit delivered, including the text
    /// of a transcription.
    ///
    /// - parameter sensor: The sensor the sample was fetched from, `Sensor.siriSpeechMetrics` or
    ///     `Sensor.telephonySpeechMetrics`, which share the sample type.
    @available(iOS 18, *)
    public init(speechMetrics sample: SRSpeechMetrics.SafeRepresentation, sensor: Sensor<SRSpeechMetrics>) throws {
        guard let sourceToken = SensorKitCatalog.sourceToken(for: sensor.srSensor) else {
            throw SensorKitRecordError.sourceTypeNotAdmitted(sensor.id)
        }
        try self.init(
            raw: SpeechMetricsEvidence(sample),
            sourceToken: sourceToken,
            field: "speechMetrics",
            timeRange: sample.timeRange
        )
    }

    /// A raw-only source: one sample becomes one native recording covering the sample's time range.
    private init(raw evidence: some Encodable, sourceToken: String, field: String, timeRange: Range<Date>) throws {
        let effectivePeriod = DateInterval(start: timeRange.lowerBound, end: timeRange.upperBound)
        self.init(nativePayload: try Self.encodeJSON(evidence)) { sourceRecordID, nativeRecording in
            guard let nativeRecording else {
                throw SensorKitRecordError.missingProviderValue("\(field).nativeRecording")
            }
            return .raw(try SensorKitRawRecord(
                sourceRecordID: sourceRecordID,
                sourceToken: sourceToken,
                effectivePeriod: effectivePeriod,
                nativeRecording: nativeRecording
            ))
        }
    }
}


extension SensorKitPreparedStructuredFile {
    /// Stages the native evidence of `prepared` as a file, with the same bytes and retry evidence.
    ///
    /// For a preparation whose native evidence is small enough to encode in memory, such as a keyboard-metrics
    /// report, a face-metrics sample, a media event or a speech-metrics sample.
    ///
    /// - throws: `SensorKitRecordError.invalidRecordingFormat` when `prepared` carries no native evidence.
    public init(_ prepared: SensorKitPreparedStructuredRecord, maximumByteCount: Int) throws {
        guard let payload = prepared.nativePayload else {
            throw SensorKitRecordError.invalidRecordingFormat
        }
        let file = try RecordingFile.stage(
            maximumByteCount: min(maximumByteCount, RegisteredRecordingFormat.maximumDecodedPayloadByteCount)
        ) { append in
            try append(payload)
        }
        self.init(file: file, retryEvidenceSupplement: prepared.retryEvidenceSupplement) { sourceRecordID, nativeRecording in
            try prepared.sensorKitRecord(sourceRecordID: sourceRecordID, nativeRecording: nativeRecording)
        }
    }
}


/// The members of a keyboard-metrics report, each under the name of its `SRKeyboardMetrics` property.
@available(iOS 18, *)
private struct KeyboardMetricsEvidence: Encodable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ name: String) {
            stringValue = name
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            nil
        }
    }

    let report: SRKeyboardMetrics.SafeRepresentation

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        func encode<Name: RawRepresentable<String>>(_ table: [Name: some Encodable]) throws {
            for (name, value) in table {
                try container.encode(value, forKey: Key(name.rawValue))
            }
        }
        func byName<Name: RawRepresentable<String>, Value>(_ table: [Name: Value]) -> [String: Value] {
            Dictionary(uniqueKeysWithValues: table.map { ($0.key.rawValue, $0.value) })
        }
        try container.encode(report.timestamp, forKey: Key("timestamp"))
        try container.encode(report.duration, forKey: Key("duration"))
        try container.encode(report.keyboardIdentifier, forKey: Key("keyboardIdentifier"))
        try container.encode(report.version, forKey: Key("version"))
        try container.encode(report.width, forKey: Key("width"))
        try container.encode(report.height, forKey: Key("height"))
        try container.encode(report.inputModes, forKey: Key("inputModes"))
        try container.encode(report.sessionIdentifiers, forKey: Key("sessionIdentifiers"))
        try container.encode(report.totalPathTime, forKey: Key("totalPathTime"))
        try container.encode(report.totalPathLength, forKey: Key("totalPathLength"))
        try container.encode(report.totalTypingDuration, forKey: Key("totalTypingDuration"))
        try container.encode(report.typingSpeed, forKey: Key("typingSpeed"))
        try container.encode(report.pathTypingSpeed, forKey: Key("pathTypingSpeed"))
        try container.encode(report.pathErrorDistanceRatio, forKey: Key("pathErrorDistanceRatio"))
        try encode(report.counts)
        try encode(report.lengthDistributions)
        try encode(report.durationDistributions)
        try encode(report.positionalLengthDistributions)
        try encode(report.positionalDurationDistributions)
        try container.encode(byName(report.wordCountBySentiment), forKey: Key("wordCountBySentimentCategory"))
        try container.encode(byName(report.emojiCountBySentiment), forKey: Key("emojiCountBySentimentCategory"))
    }
}


@available(iOS 18, *)
private struct FaceMetricsEvidence: Encodable {
    struct Expression: Encodable {
        let identifier: String
        let value: Double

        init(_ expression: SRFaceMetrics.SafeRepresentation.Expression) {
            identifier = expression.identifier
            value = expression.value
        }
    }

    let timestamp: Date
    let version: String
    let sessionIdentifier: String
    let contextRawValue: UInt
    let wholeFaceExpressions: [Expression]
    let partialFaceExpressions: [Expression]

    init(_ sample: SRFaceMetrics.SafeRepresentation) {
        timestamp = sample.timestamp
        version = sample.version
        sessionIdentifier = sample.sessionIdentifier
        contextRawValue = sample.context.rawValue
        wholeFaceExpressions = sample.wholeFaceExpressions.map(Expression.init)
        partialFaceExpressions = sample.partialFaceExpressions.map(Expression.init)
    }
}


@available(iOS 18, *)
private struct MediaEventEvidence: Encodable {
    let timestamp: Date
    let mediaIdentifier: String
    let eventTypeRawValue: Int

    init(_ event: SRMediaEvent.SafeRepresentation) {
        timestamp = event.timestamp
        mediaIdentifier = event.mediaIdentifier
        eventTypeRawValue = event.eventType.rawValue
    }
}
#endif
