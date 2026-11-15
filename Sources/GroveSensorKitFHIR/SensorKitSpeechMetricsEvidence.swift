//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
import GroveSensorKit
import SensorKit


/// The native JSON of a speech-metrics sample: every member under the name of the SDK property it was read from.
/// An object SensorKit did not deliver is omitted.
@available(iOS 18, *)
struct SpeechMetricsEvidence: Encodable {
    typealias Sample = SRSpeechMetrics.SafeRepresentation

    struct AudioRange: Encodable {
        let start: TimeInterval
        let duration: TimeInterval

        init(_ range: Sample.AudioRange) {
            start = range.start
            duration = range.duration
        }
    }

    struct AudioLevel: Encodable {
        let timeRange: AudioRange
        let loudness: Double
    }

    struct SpeechExpression: Encodable {
        let version: String
        let timeRange: AudioRange
        let confidence: Double
        let mood: Double
        let valence: Double
        let activation: Double
        let dominance: Double
    }

    struct SoundClassification: Encodable {
        struct Classification: Encodable {
            let identifier: String
            let confidence: Double
        }

        let timeRange: AudioRange
        let classifications: [Classification]
    }

    struct AcousticFeature: Encodable {
        let acousticFeatureValuePerFrame: [Double]
        let frameDuration: TimeInterval

        init(_ feature: Sample.AcousticFeature) {
            acousticFeatureValuePerFrame = feature.acousticFeatureValuePerFrame
            frameDuration = feature.frameDuration
        }
    }

    struct VoiceAnalytics: Encodable {
        let jitter: AcousticFeature
        let shimmer: AcousticFeature
        let pitch: AcousticFeature
        let voicing: AcousticFeature
    }

    struct RecognitionMetadata: Encodable {
        let speakingRate: Double
        let averagePauseDuration: TimeInterval
        let speechStartTimestamp: TimeInterval
        let speechDuration: TimeInterval
        let voiceAnalytics: VoiceAnalytics?
    }

    struct Transcription: Encodable {
        struct Segment: Encodable {
            let substring: String
            let substringLocation: Int
            let substringLength: Int
            let timestamp: TimeInterval
            let duration: TimeInterval
            let confidence: Double
            let alternativeSubstrings: [String]
        }

        let formattedString: String
        let segments: [Segment]

        init(_ transcription: Sample.Transcription) {
            formattedString = transcription.formattedString
            segments = transcription.segments.map { segment in
                Segment(
                    substring: segment.substring,
                    substringLocation: segment.substringLocation,
                    substringLength: segment.substringLength,
                    timestamp: segment.timestamp,
                    duration: segment.duration,
                    confidence: segment.confidence,
                    alternativeSubstrings: segment.alternativeSubstrings
                )
            }
        }
    }

    struct SpeechRecognition: Encodable {
        let bestTranscription: Transcription
        let transcriptions: [Transcription]
        let isFinal: Bool
        let speechRecognitionMetadata: RecognitionMetadata?
    }

    let timestamp: Date
    let sessionIdentifier: String
    let sessionFlagsRawValue: UInt
    let speechTimestamp: Date
    let timeSinceAudioStart: TimeInterval
    let audioLevel: AudioLevel?
    let speechRecognition: SpeechRecognition?
    let soundClassification: SoundClassification?
    let speechExpression: SpeechExpression?

    init(_ sample: Sample) {
        timestamp = sample.timestamp
        sessionIdentifier = sample.sessionIdentifier
        sessionFlagsRawValue = sample.sessionFlags.rawValue
        speechTimestamp = sample.speechTimestamp
        timeSinceAudioStart = sample.timeSinceAudioStart
        audioLevel = sample.audioLevel.map { AudioLevel(timeRange: AudioRange($0.timeRange), loudness: $0.loudness) }
        speechRecognition = sample.speechRecognition.map { recognition in
            SpeechRecognition(
                bestTranscription: Transcription(recognition.bestTranscription),
                transcriptions: recognition.transcriptions.map(Transcription.init),
                isFinal: recognition.isFinal,
                speechRecognitionMetadata: recognition.metadata.map { metadata in
                    RecognitionMetadata(
                        speakingRate: metadata.speakingRate,
                        averagePauseDuration: metadata.averagePauseDuration,
                        speechStartTimestamp: metadata.speechStartTimestamp,
                        speechDuration: metadata.speechDuration,
                        voiceAnalytics: metadata.voiceAnalytics.map { analytics in
                            VoiceAnalytics(
                                jitter: AcousticFeature(analytics.jitter),
                                shimmer: AcousticFeature(analytics.shimmer),
                                pitch: AcousticFeature(analytics.pitch),
                                voicing: AcousticFeature(analytics.voicing)
                            )
                        }
                    )
                }
            )
        }
        soundClassification = sample.soundClassification.map { classification in
            SoundClassification(
                timeRange: AudioRange(classification.timeRange),
                classifications: classification.classifications.map {
                    SoundClassification.Classification(identifier: $0.identifier, confidence: $0.confidence)
                }
            )
        }
        speechExpression = sample.speechExpression.map { expression in
            SpeechExpression(
                version: expression.version,
                timeRange: AudioRange(expression.timeRange),
                confidence: expression.confidence,
                mood: expression.mood,
                valence: expression.valence,
                activation: expression.activation,
                dominance: expression.dominance
            )
        }
    }
}
#endif
