//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The nested value types mirror the SDK's object graph one to one, each beside its SDK copy.
// swiftlint:disable nesting

import CoreMedia
public import Foundation
public import SensorKit
import SoundAnalysis
import Speech


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSpeechMetrics: SensorKitSampleProtocol {
    /// Every public field of a speech-metrics sample, copied on the SensorKit callback thread.
    ///
    /// - Important: The sample holds whatever transcription SensorKit delivers, including its text.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// A range of the session's audio, in seconds from the start of the audio.
        public struct AudioRange: Hashable, Sendable {
            public let start: TimeInterval
            public let duration: TimeInterval

            /// Creates an audio range.
            public init(start: TimeInterval, duration: TimeInterval) {
                self.start = start
                self.duration = duration
            }
        }

        /// The loudness of a range of audio, in decibels.
        public struct AudioLevel: Hashable, Sendable {
            public let timeRange: AudioRange
            public let loudness: Double

            /// Creates an audio level.
            public init(timeRange: AudioRange, loudness: Double) {
                self.timeRange = timeRange
                self.loudness = loudness
            }
        }

        /// The emotional expression SensorKit derived from a range of audio.
        public struct SpeechExpression: Hashable, Sendable {
            public let version: String
            public let timeRange: AudioRange
            public let confidence: Double
            public let mood: Double
            public let valence: Double
            public let activation: Double
            public let dominance: Double

            /// Creates a speech expression.
            public init(
                version: String,
                timeRange: AudioRange,
                confidence: Double,
                mood: Double,
                valence: Double,
                activation: Double,
                dominance: Double
            ) {
                self.version = version
                self.timeRange = timeRange
                self.confidence = confidence
                self.mood = mood
                self.valence = valence
                self.activation = activation
                self.dominance = dominance
            }
        }

        /// The sounds SensorKit classified in a range of audio, in the order it reports them.
        public struct SoundClassification: Hashable, Sendable {
            /// One classification candidate.
            public struct Classification: Hashable, Sendable {
                public let identifier: String
                public let confidence: Double

                /// Creates a classification candidate.
                public init(identifier: String, confidence: Double) {
                    self.identifier = identifier
                    self.confidence = confidence
                }
            }

            public let timeRange: AudioRange
            public let classifications: [Classification]

            /// Creates a sound classification.
            public init(timeRange: AudioRange, classifications: [Classification]) {
                self.timeRange = timeRange
                self.classifications = classifications
            }
        }

        /// One acoustic feature, with a value per audio frame.
        public struct AcousticFeature: Hashable, Sendable {
            public let acousticFeatureValuePerFrame: [Double]
            public let frameDuration: TimeInterval

            /// Creates an acoustic feature.
            public init(acousticFeatureValuePerFrame: [Double], frameDuration: TimeInterval) {
                self.acousticFeatureValuePerFrame = acousticFeatureValuePerFrame
                self.frameDuration = frameDuration
            }
        }

        /// The vocal features of a recognized utterance.
        public struct VoiceAnalytics: Hashable, Sendable {
            public let jitter: AcousticFeature
            public let shimmer: AcousticFeature
            public let pitch: AcousticFeature
            public let voicing: AcousticFeature

            /// Creates voice analytics.
            public init(jitter: AcousticFeature, shimmer: AcousticFeature, pitch: AcousticFeature, voicing: AcousticFeature) {
                self.jitter = jitter
                self.shimmer = shimmer
                self.pitch = pitch
                self.voicing = voicing
            }
        }

        /// The timing and voice facts of a recognition result.
        public struct RecognitionMetadata: Hashable, Sendable {
            /// Words per minute.
            public let speakingRate: Double
            public let averagePauseDuration: TimeInterval
            public let speechStartTimestamp: TimeInterval
            public let speechDuration: TimeInterval
            public let voiceAnalytics: VoiceAnalytics?

            /// Creates recognition metadata.
            public init(
                speakingRate: Double,
                averagePauseDuration: TimeInterval,
                speechStartTimestamp: TimeInterval,
                speechDuration: TimeInterval,
                voiceAnalytics: VoiceAnalytics?
            ) {
                self.speakingRate = speakingRate
                self.averagePauseDuration = averagePauseDuration
                self.speechStartTimestamp = speechStartTimestamp
                self.speechDuration = speechDuration
                self.voiceAnalytics = voiceAnalytics
            }
        }

        /// One utterance of a transcription.
        public struct TranscriptionSegment: Hashable, Sendable {
            public let substring: String
            /// The UTF-16 offset of the utterance within the transcription's `formattedString`.
            public let substringLocation: Int
            /// The UTF-16 length of the utterance within the transcription's `formattedString`.
            public let substringLength: Int
            public let timestamp: TimeInterval
            public let duration: TimeInterval
            public let confidence: Double
            public let alternativeSubstrings: [String]

            /// Creates a transcription segment.
            public init(
                substring: String,
                substringLocation: Int,
                substringLength: Int,
                timestamp: TimeInterval,
                duration: TimeInterval,
                confidence: Double,
                alternativeSubstrings: [String]
            ) {
                self.substring = substring
                self.substringLocation = substringLocation
                self.substringLength = substringLength
                self.timestamp = timestamp
                self.duration = duration
                self.confidence = confidence
                self.alternativeSubstrings = alternativeSubstrings
            }
        }

        /// One transcription of the session's speech.
        public struct Transcription: Hashable, Sendable {
            public let formattedString: String
            public let segments: [TranscriptionSegment]

            /// Creates a transcription.
            public init(formattedString: String, segments: [TranscriptionSegment]) {
                self.formattedString = formattedString
                self.segments = segments
            }
        }

        /// What SensorKit recognized in the session's speech.
        public struct SpeechRecognition: Hashable, Sendable {
            public let bestTranscription: Transcription
            public let transcriptions: [Transcription]
            public let isFinal: Bool
            public let metadata: RecognitionMetadata?

            /// Creates a speech-recognition result.
            public init(bestTranscription: Transcription, transcriptions: [Transcription], isFinal: Bool, metadata: RecognitionMetadata?) {
                self.bestTranscription = bestTranscription
                self.transcriptions = transcriptions
                self.isFinal = isFinal
                self.metadata = metadata
            }
        }

        /// The point in time when the system recorded the sample.
        public let timestamp: Date
        /// The identifier of the audio session the sample belongs to.
        public let sessionIdentifier: String
        public let sessionFlags: SRSpeechMetrics.SessionFlags
        /// The date and time the sample states for its speech (`SRSpeechMetrics.timestamp`).
        public let speechTimestamp: Date
        /// The time between the start of the audio stream and the start of the speech-recognition request.
        public let timeSinceAudioStart: TimeInterval
        public let audioLevel: AudioLevel?
        public let speechRecognition: SpeechRecognition?
        public let soundClassification: SoundClassification?
        public let speechExpression: SpeechExpression?

        public var timeRange: Range<Date> { timestamp..<timestamp }

        /// Creates a speech-metrics sample.
        public init(
            timestamp: Date,
            sessionIdentifier: String,
            sessionFlags: SRSpeechMetrics.SessionFlags,
            speechTimestamp: Date,
            timeSinceAudioStart: TimeInterval,
            audioLevel: AudioLevel? = nil,
            speechRecognition: SpeechRecognition? = nil,
            soundClassification: SoundClassification? = nil,
            speechExpression: SpeechExpression? = nil
        ) {
            self.timestamp = timestamp
            self.sessionIdentifier = sessionIdentifier
            self.sessionFlags = sessionFlags
            self.speechTimestamp = speechTimestamp
            self.timeSinceAudioStart = timeSinceAudioStart
            self.audioLevel = audioLevel
            self.speechRecognition = speechRecognition
            self.soundClassification = soundClassification
            self.speechExpression = speechExpression
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(timestamp)
            hasher.combine(sessionIdentifier)
            hasher.combine(sessionFlags.rawValue)
            hasher.combine(speechTimestamp)
            hasher.combine(timeSinceAudioStart)
            hasher.combine(audioLevel)
            hasher.combine(speechRecognition)
            hasher.combine(soundClassification)
            hasher.combine(speechExpression)
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRSpeechMetrics)>
    ) -> [SafeRepresentation] {
        samples.map { timestamp, sample in
            SafeRepresentation(
                timestamp: timestamp,
                sessionIdentifier: sample.sessionIdentifier,
                sessionFlags: sample.sessionFlags,
                speechTimestamp: sample.timestamp,
                timeSinceAudioStart: sample.timeSinceAudioStart,
                audioLevel: sample.audioLevel.map { .init(timeRange: .init($0.timeRange), loudness: $0.loudness) },
                speechRecognition: sample.speechRecognition.map { .init($0) },
                soundClassification: sample.soundClassification.map { result in
                    .init(
                        timeRange: .init(result.timeRange),
                        classifications: result.classifications.map { .init(identifier: $0.identifier, confidence: $0.confidence) }
                    )
                },
                speechExpression: sample.speechExpression.map { expression in
                    .init(
                        version: expression.version,
                        timeRange: .init(expression.timeRange),
                        confidence: expression.confidence,
                        mood: expression.mood,
                        valence: expression.valence,
                        activation: expression.activation,
                        dominance: expression.dominance
                    )
                }
            )
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSpeechMetrics.SafeRepresentation.AudioRange {
    init(_ range: CMTimeRange) {
        self.init(start: range.start.seconds, duration: range.duration.seconds)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSpeechMetrics.SafeRepresentation.SpeechRecognition {
    init(_ result: SFSpeechRecognitionResult) {
        self.init(
            bestTranscription: .init(result.bestTranscription),
            transcriptions: result.transcriptions.map { .init($0) },
            isFinal: result.isFinal,
            metadata: result.speechRecognitionMetadata.map { metadata in
                .init(
                    speakingRate: metadata.speakingRate,
                    averagePauseDuration: metadata.averagePauseDuration,
                    speechStartTimestamp: metadata.speechStartTimestamp,
                    speechDuration: metadata.speechDuration,
                    voiceAnalytics: metadata.voiceAnalytics.map { analytics in
                        .init(
                            jitter: .init(analytics.jitter),
                            shimmer: .init(analytics.shimmer),
                            pitch: .init(analytics.pitch),
                            voicing: .init(analytics.voicing)
                        )
                    }
                )
            }
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSpeechMetrics.SafeRepresentation.Transcription {
    init(_ transcription: SFTranscription) {
        self.init(
            formattedString: transcription.formattedString,
            segments: transcription.segments.map { segment in
                .init(
                    substring: segment.substring,
                    substringLocation: segment.substringRange.location,
                    substringLength: segment.substringRange.length,
                    timestamp: segment.timestamp,
                    duration: segment.duration,
                    confidence: Double(segment.confidence),
                    alternativeSubstrings: segment.alternativeSubstrings
                )
            }
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSpeechMetrics.SafeRepresentation.AcousticFeature {
    init(_ feature: SFAcousticFeature) {
        self.init(
            acousticFeatureValuePerFrame: feature.acousticFeatureValuePerFrame,
            frameDuration: feature.frameDuration
        )
    }
}
