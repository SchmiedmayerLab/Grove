//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import CoreMotion
import Foundation
import GroveFHIRContract
import GroveSensorKit
import GroveSensorKitFHIR
import SensorKit
import Testing


@Suite
struct SensorKitNativeBridgeTests { // swiftlint:disable:this type_body_length
    private static let start = Date(timeIntervalSince1970: 1_800_000_000.125)
    private static let sourceID = SensorKitSourceRecordID(UUID())

    /// Samples whose spacing varies the way a device's clock does: no single period fits them.
    private static let jitteredRotation: [CMRecordedRotationRateData.SafeRepresentation] = [0, 0.019_98, 0.040_03, 0.060_01].enumerated().map {
        .init(timestamp: start.addingTimeInterval($0.element), rotationRate: CMRotationRate(x: 0.1 * Double($0.offset), y: -0.25, z: 1.5))
    }

    /// Every count, each with its one-based position in `Count.allCases` as its value.
    private static let allKeyboardCounts = Dictionary(
        uniqueKeysWithValues: SRKeyboardMetrics.SafeRepresentation.Count.allCases.enumerated().map { ($0.element, $0.offset + 1) }
    )

    private static func odometer(
        start: TimeInterval,
        end: TimeInterval,
        slope: Double? = 1.5,
        originDevice: CMOdometerOriginDevice = .local
    ) -> CMOdometerData.SafeRepresentation {
        .init(
            startDate: Self.start.addingTimeInterval(start),
            endDate: Self.start.addingTimeInterval(end),
            gpsDate: Self.start.addingTimeInterval(start + 0.5),
            speed: 1.25,
            speedAccuracy: 0.1,
            slope: slope,
            maxAbsSlope: slope.map { $0 + 1 },
            deltaDistance: 3.5,
            deltaDistanceAccuracy: 0.2,
            deltaAltitude: -0.75,
            verticalAccuracy: 4,
            originDevice: originDevice
        )
    }

    private static func keyboardMetrics(
        counts: [SRKeyboardMetrics.SafeRepresentation.Count: Int] = allKeyboardCounts,
        touchDownUp: [Double] = [0.08, 0.11]
    ) -> SRKeyboardMetrics.SafeRepresentation {
        SRKeyboardMetrics.SafeRepresentation(
            timestamp: start,
            duration: 3_600,
            keyboardIdentifier: "keyboard/1",
            version: "1.2",
            width: 0.07,
            height: 0.05,
            inputModes: ["en_US"],
            sessionIdentifiers: ["session/1"],
            counts: counts,
            totalPathTime: 2.5,
            totalPathLength: 0.4,
            totalTypingDuration: 125.5,
            typingSpeed: 3.5,
            pathTypingSpeed: 22,
            lengthDistributions: [.upErrorDistance: [0.001, 0.002]],
            durationDistributions: [.touchDownUp: touchDownUp],
            positionalLengthDistributions: [.longWordUpErrorDistance: [[0.001], [0.002, 0.003]]],
            positionalDurationDistributions: [.deleteToDeletes: [[0.2]]],
            pathErrorDistanceRatio: [0.5, 0.25],
            wordCountBySentiment: [.positive: 4, .sad: 1],
            emojiCountBySentiment: [.positive: 2]
        )
    }

    private static func speechMetrics() -> SRSpeechMetrics.SafeRepresentation {
        typealias Sample = SRSpeechMetrics.SafeRepresentation
        let feature = Sample.AcousticFeature(acousticFeatureValuePerFrame: [0.1, 0.2], frameDuration: 0.01)
        let transcription = Sample.Transcription(
            formattedString: "synthetic words",
            segments: [
                .init(
                    substring: "synthetic",
                    substringLocation: 0,
                    substringLength: 9,
                    timestamp: 0.5,
                    duration: 0.4,
                    confidence: 0.5,
                    alternativeSubstrings: ["synthesis"]
                )
            ]
        )
        return Sample(
            timestamp: start,
            sessionIdentifier: "audio/1",
            sessionFlags: .bypassVoiceProcessing,
            speechTimestamp: start.addingTimeInterval(-30),
            timeSinceAudioStart: 1.5,
            audioLevel: .init(timeRange: .init(start: 0, duration: 2), loudness: -32.5),
            speechRecognition: .init(
                bestTranscription: transcription,
                transcriptions: [transcription],
                isFinal: true,
                metadata: .init(
                    speakingRate: 140,
                    averagePauseDuration: 0.3,
                    speechStartTimestamp: 0.5,
                    speechDuration: 1.2,
                    voiceAnalytics: .init(jitter: feature, shimmer: feature, pitch: feature, voicing: feature)
                )
            ),
            soundClassification: .init(timeRange: .init(start: 0, duration: 1), classifications: [.init(identifier: "speech", confidence: 0.75)]),
            speechExpression: .init(
                version: "1",
                timeRange: .init(start: 0.5, duration: 1.2),
                confidence: 0.75,
                mood: 0.25,
                valence: -0.5,
                activation: 0.5,
                dominance: 0.125
            )
        )
    }

    private static func json(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The raw record a raw-only preparation yields with its native evidence attached inline.
    private static func rawRecord(_ prepared: SensorKitPreparedStructuredRecord) throws -> (record: SensorKitRecord, raw: SensorKitRawRecord) {
        let record = try prepared.sensorKitRecord(
            sourceRecordID: sourceID,
            title: "Synthetic",
            location: .inline,
            admission: .callerAuthorizedOpaquePayload
        )
        guard case .raw(let raw) = record else {
            throw CocoaError(.featureUnsupported)
        }
        return (record, raw)
    }

    @Test("A rotation-rate batch with jittered timestamps keeps each sample's own instant in its registered recording")
    func jitteredRotationRateBecomesAFaithfulRecording() async throws {
        let samples = Self.jitteredRotation
        let memory = try SensorKitTabularRecording(samples: samples, deviceProductType: "Watch7,1")
        let disk = try SensorKitTabularRecording.File(samples: samples, deviceProductType: "Watch7,1", maximumByteCount: 4_096)
        var bytes = Data()
        try disk.file.readChunks { bytes.append($0) }
        #expect(bytes == memory.data)
        #expect(memory.sourceToken == "SRSensor.rotationRate" && memory.format == .triaxialRotationSamples)
        #expect(memory.effectivePeriod == DateInterval(start: samples[0].timestamp, end: samples[3].timestamp))
        #expect(disk.effectivePeriod == memory.effectivePeriod)

        let rows = try RecordingCSVReader(memory.data, format: .triaxialRotationSamples).rows
        #expect(try rows.map { try $0.timestamp("timestamp") } == samples.map(\.timestamp))
        #expect(try rows.map { try $0.requiredNumber("x") } == samples.map(\.rotationRate.x))
        #expect(rows.allSatisfy { $0["device"] == "Watch7,1" })

        let record = try disk.sensorKitRecord(
            sourceRecordID: Self.sourceID,
            title: "Rotation Rate",
            sidecarPath: "recordings/rotation.csv",
            admission: .callerAuthorizedOpaquePayload
        )
        let graph = try await SensorKitExporterFixtures.graph(record)
        #expect(graph.observations.isEmpty)
        #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "triaxial-rotation-samples")
    }

    @Test("The sampled-data form of rotation rate still refuses a batch that proves no uniform period")
    func jitteredRotationRateIsNotSampledData() async throws {
        let record = SensorKitRotationRateRecord(sourceRecordID: Self.sourceID, samples: Self.jitteredRotation)
        await #expect(throws: SensorKitConversionError.invalidRecord(.nonUniformTiming(index: 2))) {
            try await SensorKitExporterFixtures.graph(.rotationRate(record))
        }
    }

    @Test("An odometer recording covers its rows' intervals and keeps an unavailable slope empty")
    func odometerRowsCoverTheirIntervals() async throws {
        let samples = [Self.odometer(start: 10, end: 20), Self.odometer(start: 0, end: 12, slope: nil, originDevice: .remote)]
        #expect(samples[0].timeRange == samples[0].startDate..<samples[0].endDate)
        let recording = try SensorKitTabularRecording.File(samples: samples, deviceProductType: "iPhone17,1", maximumByteCount: 4_096)
        #expect(recording.sourceToken == "SRSensor.odometer" && recording.format == .odometerSamples)
        #expect(recording.effectivePeriod == DateInterval(start: samples[1].startDate, end: samples[0].endDate))

        var bytes = Data()
        try recording.file.readChunks { bytes.append($0) }
        #expect(try SensorKitTabularRecording(samples: samples, deviceProductType: "iPhone17,1").data == bytes)
        let rows = try RecordingCSVReader(bytes, format: .odometerSamples).rows
        #expect(try rows.map { try $0.timestamp("start") } == samples.map(\.startDate))
        #expect(try rows.map { try $0.timestamp("end") } == samples.map(\.endDate))
        #expect(try rows.map { try $0.timestamp("gpsDate") } == samples.map(\.gpsDate))
        #expect(try rows[0].number("slope") == 1.5 && rows[0].number("maxAbsSlope") == 2.5)
        #expect(rows[1].isAbsent("slope") && rows[1].isAbsent("maxAbsSlope"))
        #expect(try rows[0].requiredNumber("deltaAltitude") == -0.75)
        #expect(rows.map { $0["originDevice"] } == ["local", "remote"])

        let record = try recording.sensorKitRecord(
            sourceRecordID: Self.sourceID,
            title: "Odometer",
            sidecarPath: "recordings/odometer.csv",
            admission: .callerAuthorizedOpaquePayload
        )
        let graph = try await SensorKitExporterFixtures.graph(record)
        #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "odometer-samples")
    }

    @Test("An odometer origin device this SDK does not name is refused")
    func unknownOdometerOriginDeviceIsRefused() throws {
        let origin = try #require(CMOdometerOriginDevice(rawValue: 99))
        let samples = [Self.odometer(start: 0, end: 1, originDevice: origin)]
        #expect(throws: (any Error).self) {
            try SensorKitTabularRecording.File(samples: samples, deviceProductType: "iPhone17,1", maximumByteCount: 4_096)
        }
        #expect(throws: (any Error).self) {
            try SensorKitTabularRecording(samples: samples, deviceProductType: "iPhone17,1")
        }
    }

    @Test("A keyboard-metrics report becomes its summary and a native recording of every field")
    @available(iOS 18, *)
    func keyboardMetricsOwnsItsNativeEncoding() async throws {
        let report = Self.keyboardMetrics()
        #expect(report.timeRange == Self.start..<Self.start.addingTimeInterval(3_600))
        let prepared = try SensorKitPreparedStructuredRecord(keyboardMetrics: report)
        #expect(prepared.retryEvidence == prepared.nativePayload)
        #expect(try SensorKitPreparedStructuredRecord(keyboardMetrics: report).retryEvidence == prepared.retryEvidence)
        #expect(try SensorKitPreparedStructuredRecord(keyboardMetrics: Self.keyboardMetrics(touchDownUp: [0.08])).retryEvidence != prepared.retryEvidence)

        let json = try Self.json(prepared.nativePayload)
        var expectedKeys: Set<String> = [
            "timestamp", "duration", "keyboardIdentifier", "version", "width", "height", "inputModes", "sessionIdentifiers",
            "totalPathTime", "totalPathLength", "totalTypingDuration", "typingSpeed", "pathTypingSpeed", "pathErrorDistanceRatio",
            "upErrorDistance", "touchDownUp", "longWordUpErrorDistance", "deleteToDeletes",
            "wordCountBySentimentCategory", "emojiCountBySentimentCategory"
        ]
        expectedKeys.formUnion(SRKeyboardMetrics.SafeRepresentation.Count.allCases.map(\.rawValue))
        #expect(Set(json.keys) == expectedKeys)
        #expect(json["timestamp"] as? Double == 1_800_000_000.125)
        #expect(json["totalWords"] as? Int == 1 && json["totalTypingEpisodes"] as? Int == 19)
        #expect(json["touchDownUp"] as? [Double] == [0.08, 0.11])
        #expect(json["longWordUpErrorDistance"] as? [[Double]] == [[0.001], [0.002, 0.003]])
        #expect(json["wordCountBySentimentCategory"] as? [String: Int] == ["positive": 4, "sad": 1])

        let record = try prepared.sensorKitRecord(
            sourceRecordID: Self.sourceID,
            title: "Keyboard Metrics",
            location: .sidecar(path: "recordings/keyboard.json"),
            admission: .callerAuthorizedOpaquePayload
        )
        guard case .keyboardMetrics(let summary) = record else {
            Issue.record("Expected a keyboard-metrics record")
            return
        }
        #expect(summary.timestamp == Self.start && summary.durationSeconds == 3_600)
        #expect(summary.totalTypingDurationSeconds == 125.5 && summary.typingSpeed == 3.5)
        #expect(summary.totalWords == 1 && summary.totalAlteredWords == 2 && summary.totalTaps == 3 && summary.totalDeletes == 5)
        #expect(summary.totalEmojis == 6 && summary.totalAutocorrections == 8 && summary.totalPauses == 17 && summary.totalTypingEpisodes == 19)
        let graph = try await SensorKitExporterFixtures.graph(record)
        #expect(graph.observations.count == 1)
        #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "native-recording")
    }

    @Test("A keyboard-metrics report without a count its summary states is refused")
    @available(iOS 18, *)
    func keyboardMetricsRequiresItsSummaryCounts() {
        #expect(throws: SensorKitRecordError.missingProviderValue("keyboardMetrics.totalWords")) {
            try SensorKitPreparedStructuredRecord(keyboardMetrics: Self.keyboardMetrics(counts: [.totalTaps: 1]))
        }
    }

    @Test("A prepared record's native evidence stages as a file with the same bytes, evidence and record")
    @available(iOS 18, *)
    func preparedEvidenceStagesAsAFile() async throws {
        let prepared = try SensorKitPreparedStructuredRecord(keyboardMetrics: Self.keyboardMetrics())
        let payload = try #require(prepared.nativePayload)
        let file = try SensorKitPreparedStructuredFile(prepared, maximumByteCount: payload.count)
        var evidence = Data()
        try file.readRetryEvidenceChunks { evidence.append($0) }
        #expect(evidence == prepared.retryEvidence && file.file.byteCount == payload.count)
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try SensorKitPreparedStructuredFile(prepared, maximumByteCount: payload.count - 1)
        }
        let path = "recordings/keyboard.json"
        let fileRecord = try file.sensorKitRecord(
            sourceRecordID: Self.sourceID, title: "Keyboard Metrics", sidecarPath: path, admission: .callerAuthorizedOpaquePayload
        )
        let dataRecord = try prepared.sensorKitRecord(
            sourceRecordID: Self.sourceID, title: "Keyboard Metrics", location: .sidecar(path: path), admission: .callerAuthorizedOpaquePayload
        )
        #expect(try await SensorKitExporterFixtures.record(fileRecord).json == SensorKitExporterFixtures.record(dataRecord).json)

        let visit = try SensorKitPreparedStructuredRecord(messagesUsage: .init(
            timestamp: Self.start, duration: 60, totalOutgoingMessages: 1, totalIncomingMessages: 1, totalUniqueContacts: 1
        ))
        #expect(throws: SensorKitRecordError.invalidRecordingFormat) {
            try SensorKitPreparedStructuredFile(visit, maximumByteCount: 1_024)
        }
    }

    @Test("A face-metrics sample becomes a native recording of its session facts and expressions")
    @available(iOS 18, *)
    func faceMetricsBecomesANativeRecording() async throws {
        let sample = SRFaceMetrics.SafeRepresentation(
            timestamp: Self.start,
            version: "2",
            sessionIdentifier: "face/1",
            context: [.deviceUnlock, .messagingAppUsage],
            wholeFaceExpressions: [.init(identifier: "smile", value: 0.75)],
            partialFaceExpressions: [.init(identifier: "browRaise", value: 0.25), .init(identifier: "jawOpen", value: 0)]
        )
        let prepared = try SensorKitPreparedStructuredRecord(faceMetrics: sample)
        let json = try Self.json(prepared.nativePayload)
        #expect(Set(json.keys) == ["timestamp", "version", "sessionIdentifier", "contextRawValue", "wholeFaceExpressions", "partialFaceExpressions"])
        #expect(json["contextRawValue"] as? Int == 3 && json["sessionIdentifier"] as? String == "face/1")
        #expect((json["partialFaceExpressions"] as? [[String: Any]])?.map { $0["identifier"] as? String } == ["browRaise", "jawOpen"])

        let (record, raw) = try Self.rawRecord(prepared)
        #expect(raw.sourceToken == "SRSensor.faceMetrics")
        #expect(raw.effectivePeriod == DateInterval(start: Self.start, duration: 0))
        let graph = try await SensorKitExporterFixtures.graph(record)
        #expect(graph.observations.isEmpty)
        #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "native-recording")
        #expect(throws: SensorKitRecordError.missingProviderValue("faceMetrics.nativeRecording")) {
            try prepared.sensorKitRecord(sourceRecordID: Self.sourceID)
        }
    }

    @Test("A media event becomes a native recording of its identifier and event type")
    @available(iOS 18, *)
    func mediaEventBecomesANativeRecording() async throws {
        let onScreen = SRMediaEvent.SafeRepresentation(timestamp: Self.start, mediaIdentifier: "media/1", eventType: .onScreen)
        let offScreen = SRMediaEvent.SafeRepresentation(timestamp: Self.start, mediaIdentifier: "media/1", eventType: .offScreen)
        let prepared = try SensorKitPreparedStructuredRecord(mediaEvent: onScreen)
        #expect(prepared.nativePayload == Data(#"{"eventTypeRawValue":1,"mediaIdentifier":"media/1","timestamp":1800000000.125}"#.utf8))
        #expect(try SensorKitPreparedStructuredRecord(mediaEvent: offScreen).retryEvidence != prepared.retryEvidence)

        let (record, raw) = try Self.rawRecord(prepared)
        #expect(raw.sourceToken == "SRSensor.mediaEvents")
        #expect(raw.effectivePeriod == DateInterval(start: Self.start, duration: 0))
        let graph = try await SensorKitExporterFixtures.graph(record)
        #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "native-recording")
    }

    @Test("A speech-metrics sample becomes a native recording under the source of the sensor it was fetched from")
    @available(iOS 18, *)
    func speechMetricsBecomesANativeRecording() async throws {
        let sample = Self.speechMetrics()
        let siri = try SensorKitPreparedStructuredRecord(speechMetrics: sample, sensor: .siriSpeechMetrics)
        let telephony = try SensorKitPreparedStructuredRecord(speechMetrics: sample, sensor: .telephonySpeechMetrics)
        #expect(siri.nativePayload == telephony.nativePayload)

        let json = try Self.json(siri.nativePayload)
        #expect(Set(json.keys) == [
            "timestamp", "sessionIdentifier", "sessionFlagsRawValue", "speechTimestamp", "timeSinceAudioStart",
            "audioLevel", "speechRecognition", "soundClassification", "speechExpression"
        ])
        #expect(json["speechTimestamp"] as? Double == 1_799_999_970.125 && json["sessionFlagsRawValue"] as? Int == 1)
        let recognition = try #require(json["speechRecognition"] as? [String: Any])
        #expect(Set(recognition.keys) == ["bestTranscription", "transcriptions", "isFinal", "speechRecognitionMetadata"])
        let segments = try #require((recognition["bestTranscription"] as? [String: Any])?["segments"] as? [[String: Any]])
        #expect(segments.first?["substring"] as? String == "synthetic" && segments.first?["substringLength"] as? Int == 9)
        let analytics = try #require((recognition["speechRecognitionMetadata"] as? [String: Any])?["voiceAnalytics"] as? [String: Any])
        #expect(Set(analytics.keys) == ["jitter", "shimmer", "pitch", "voicing"])
        #expect((json["speechExpression"] as? [String: Any])?["valence"] as? Double == -0.5)
        #expect(((json["audioLevel"] as? [String: Any])?["timeRange"] as? [String: Any])?["duration"] as? Double == 2)

        let bare = SRSpeechMetrics.SafeRepresentation(
            timestamp: Self.start, sessionIdentifier: "audio/2", sessionFlags: [], speechTimestamp: Self.start, timeSinceAudioStart: 0
        )
        let bareJSON = try Self.json(SensorKitPreparedStructuredRecord(speechMetrics: bare, sensor: .siriSpeechMetrics).nativePayload)
        #expect(Set(bareJSON.keys) == ["timestamp", "sessionIdentifier", "sessionFlagsRawValue", "speechTimestamp", "timeSinceAudioStart"])

        let (siriRecord, siriRaw) = try Self.rawRecord(siri)
        let (telephonyRecord, telephonyRaw) = try Self.rawRecord(telephony)
        #expect(siriRaw.sourceToken == "SRSensor.siriSpeechMetrics" && telephonyRaw.sourceToken == "SRSensor.telephonySpeechMetrics")
        #expect(siriRaw.effectivePeriod == DateInterval(start: Self.start, duration: 0))
        for record in [siriRecord, telephonyRecord] {
            let graph = try await SensorKitExporterFixtures.graph(record)
            #expect(graph.recordingDocument?.content.first?.format?.code?.value?.string == "native-recording")
        }
    }

    @Test("A non-finite value is refused rather than written into a native recording")
    @available(iOS 18, *)
    func nonFiniteNativeValuesAreRefused() {
        let sample = SRFaceMetrics.SafeRepresentation(
            timestamp: Self.start,
            version: "2",
            sessionIdentifier: "face/1",
            context: [],
            wholeFaceExpressions: [.init(identifier: "smile", value: .nan)],
            partialFaceExpressions: []
        )
        #expect(throws: (any Error).self) {
            try SensorKitPreparedStructuredRecord(faceMetrics: sample)
        }
    }
}
#endif
