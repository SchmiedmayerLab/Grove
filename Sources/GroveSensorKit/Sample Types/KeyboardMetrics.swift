//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SensorKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics: SensorKitSampleProtocol {
    /// Every public field of a keyboard-metrics report, copied on the SensorKit callback thread.
    ///
    /// The tables are keyed by the name of the `SRKeyboardMetrics` property each value was read from. Lengths are
    /// meters, durations are seconds, and every distribution keeps its sample values in the order SensorKit reports them.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// A scalar count the report states.
        public enum Count: String, CaseIterable, Hashable, Sendable {
            case totalWords
            case totalAlteredWords
            case totalTaps
            case totalDrags
            case totalDeletes
            case totalEmojis
            case totalPaths
            case totalAutoCorrections
            case totalSpaceCorrections
            case totalRetroCorrections
            case totalTranspositionCorrections
            case totalInsertKeyCorrections
            case totalSkipTouchCorrections
            case totalNearKeyCorrections
            case totalSubstitutionCorrections
            case totalHitTestCorrections
            case totalPauses
            case totalPathPauses
            case totalTypingEpisodes
        }

        /// A distribution of distances, in meters.
        public enum LengthDistribution: String, CaseIterable, Hashable, Sendable {
            case upErrorDistance
            case downErrorDistance
            case spaceUpErrorDistance
            case spaceDownErrorDistance
            case deleteUpErrorDistance
            case deleteDownErrorDistance
            case shortWordCharKeyUpErrorDistance
            case shortWordCharKeyDownErrorDistance
        }

        /// A distribution of durations, in seconds.
        public enum DurationDistribution: String, CaseIterable, Hashable, Sendable {
            case touchDownUp
            case spaceTouchDownUp
            case deleteTouchDownUp
            case shortWordCharKeyTouchDownUp
            case touchDownDown
            case touchUpDown
            case charKeyToPrediction
            case shortWordCharKeyToCharKey
            case charKeyToAnyTapKey
            case anyTapToCharKey
            case spaceToCharKey
            case charKeyToSpaceKey
            case spaceToDeleteKey
            case deleteToSpaceKey
            case spaceToSpaceKey
            case spaceToShiftKey
            case spaceToPlaneChangeKey
            case spaceToPredictionKey
            case deleteToCharKey
            case charKeyToDelete
            case deleteToDelete
            case deleteToShiftKey
            case deleteToPlaneChangeKey
            case anyTapToPlaneChangeKey
            case planeChangeToAnyTap
            case charKeyToPlaneChangeKey
            case planeChangeKeyToCharKey
            case deleteToPath
            case pathToDelete
            case spaceToPath
            case pathToSpace
            case pathToPath
        }

        /// One distance distribution per position in a long word, in meters.
        public enum PositionalLengthDistribution: String, CaseIterable, Hashable, Sendable {
            case longWordUpErrorDistance
            case longWordDownErrorDistance
        }

        /// One duration distribution per position in a long word or run of deletes, in seconds.
        public enum PositionalDurationDistribution: String, CaseIterable, Hashable, Sendable {
            case longWordTouchDownUp
            case longWordTouchDownDown
            case longWordTouchUpDown
            case deleteToDeletes
        }

        /// A sentiment category SensorKit counts words and emoji for.
        public enum Sentiment: String, CaseIterable, Hashable, Sendable {
            case absolutist
            case down
            case death
            case anxiety
            case anger
            case health
            case positive
            case sad
            case lowEnergy
            case confused
        }

        /// The point in time when the system recorded the report.
        public let timestamp: Date
        /// The length of time the report spans.
        public let duration: TimeInterval
        public let keyboardIdentifier: String
        /// The version of the metrics.
        public let version: String
        /// The keyboard's width, in meters.
        public let width: Double
        /// The keyboard's height, in meters.
        public let height: Double
        public let inputModes: [String]
        public let sessionIdentifiers: [String]
        public let counts: [Count: Int]
        public let totalPathTime: TimeInterval
        /// The total length of all paths, in meters.
        public let totalPathLength: Double
        public let totalTypingDuration: TimeInterval
        /// Characters per second.
        public let typingSpeed: Double
        /// QuickType words per minute.
        public let pathTypingSpeed: Double
        public let lengthDistributions: [LengthDistribution: [Double]]
        public let durationDistributions: [DurationDistribution: [Double]]
        public let positionalLengthDistributions: [PositionalLengthDistribution: [[Double]]]
        public let positionalDurationDistributions: [PositionalDurationDistribution: [[Double]]]
        public let pathErrorDistanceRatio: [Double]
        public let wordCountBySentiment: [Sentiment: Int]
        public let emojiCountBySentiment: [Sentiment: Int]

        /// The interval the report spans.
        public var timeRange: Range<Date> {
            timestamp..<(timestamp + max(0, duration))
        }

        /// Creates a keyboard-metrics report.
        public init(
            timestamp: Date,
            duration: TimeInterval,
            keyboardIdentifier: String,
            version: String,
            width: Double,
            height: Double,
            inputModes: [String] = [],
            sessionIdentifiers: [String] = [],
            counts: [Count: Int],
            totalPathTime: TimeInterval,
            totalPathLength: Double,
            totalTypingDuration: TimeInterval,
            typingSpeed: Double,
            pathTypingSpeed: Double,
            lengthDistributions: [LengthDistribution: [Double]] = [:],
            durationDistributions: [DurationDistribution: [Double]] = [:],
            positionalLengthDistributions: [PositionalLengthDistribution: [[Double]]] = [:],
            positionalDurationDistributions: [PositionalDurationDistribution: [[Double]]] = [:],
            pathErrorDistanceRatio: [Double] = [],
            wordCountBySentiment: [Sentiment: Int] = [:],
            emojiCountBySentiment: [Sentiment: Int] = [:]
        ) {
            self.timestamp = timestamp
            self.duration = duration
            self.keyboardIdentifier = keyboardIdentifier
            self.version = version
            self.width = width
            self.height = height
            self.inputModes = inputModes
            self.sessionIdentifiers = sessionIdentifiers
            self.counts = counts
            self.totalPathTime = totalPathTime
            self.totalPathLength = totalPathLength
            self.totalTypingDuration = totalTypingDuration
            self.typingSpeed = typingSpeed
            self.pathTypingSpeed = pathTypingSpeed
            self.lengthDistributions = lengthDistributions
            self.durationDistributions = durationDistributions
            self.positionalLengthDistributions = positionalLengthDistributions
            self.positionalDurationDistributions = positionalDurationDistributions
            self.pathErrorDistanceRatio = pathErrorDistanceRatio
            self.wordCountBySentiment = wordCountBySentiment
            self.emojiCountBySentiment = emojiCountBySentiment
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRKeyboardMetrics)>
    ) -> [SafeRepresentation] {
        samples.map { SafeRepresentation(timestamp: $0.timestamp, metrics: $0.sample) }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation {
    init(timestamp: Date, metrics: SRKeyboardMetrics) {
        func table<Key: CaseIterable & Hashable, Value>(_ value: (Key) -> Value) -> [Key: Value] {
            Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0, value($0)) })
        }
        func meters(_ metric: SRKeyboardMetrics.ProbabilityMetric<UnitLength>) -> [Double] {
            metric.distributionSampleValues.map { $0.converted(to: .meters).value }
        }
        func seconds(_ metric: SRKeyboardMetrics.ProbabilityMetric<UnitDuration>) -> [Double] {
            metric.distributionSampleValues.map { $0.converted(to: .seconds).value }
        }
        self.init(
            timestamp: timestamp,
            duration: metrics.duration,
            keyboardIdentifier: metrics.keyboardIdentifier,
            version: metrics.version,
            width: metrics.width.converted(to: .meters).value,
            height: metrics.height.converted(to: .meters).value,
            inputModes: metrics.inputModes,
            sessionIdentifiers: metrics.sessionIdentifiers,
            counts: table { metrics[keyPath: $0.keyPath] },
            totalPathTime: metrics.totalPathTime,
            totalPathLength: metrics.totalPathLength.converted(to: .meters).value,
            totalTypingDuration: metrics.totalTypingDuration,
            typingSpeed: metrics.typingSpeed,
            pathTypingSpeed: metrics.pathTypingSpeed,
            lengthDistributions: table { meters(metrics[keyPath: $0.keyPath]) },
            durationDistributions: table { seconds(metrics[keyPath: $0.keyPath]) },
            positionalLengthDistributions: table { metrics[keyPath: $0.keyPath].map(meters) },
            positionalDurationDistributions: table { metrics[keyPath: $0.keyPath].map(seconds) },
            pathErrorDistanceRatio: metrics.pathErrorDistanceRatio.map(\.doubleValue),
            wordCountBySentiment: table { metrics.wordCount(for: $0.category) },
            emojiCountBySentiment: table { metrics.emojiCount(for: $0.category) }
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation.Count {
    var keyPath: KeyPath<SRKeyboardMetrics, Int> {
        switch self {
        case .totalWords: \.totalWords
        case .totalAlteredWords: \.totalAlteredWords
        case .totalTaps: \.totalTaps
        case .totalDrags: \.totalDrags
        case .totalDeletes: \.totalDeletes
        case .totalEmojis: \.totalEmojis
        case .totalPaths: \.totalPaths
        case .totalAutoCorrections: \.totalAutoCorrections
        case .totalSpaceCorrections: \.totalSpaceCorrections
        case .totalRetroCorrections: \.totalRetroCorrections
        case .totalTranspositionCorrections: \.totalTranspositionCorrections
        case .totalInsertKeyCorrections: \.totalInsertKeyCorrections
        case .totalSkipTouchCorrections: \.totalSkipTouchCorrections
        case .totalNearKeyCorrections: \.totalNearKeyCorrections
        case .totalSubstitutionCorrections: \.totalSubstitutionCorrections
        case .totalHitTestCorrections: \.totalHitTestCorrections
        case .totalPauses: \.totalPauses
        case .totalPathPauses: \.totalPathPauses
        case .totalTypingEpisodes: \.totalTypingEpisodes
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation.LengthDistribution {
    var keyPath: KeyPath<SRKeyboardMetrics, SRKeyboardMetrics.ProbabilityMetric<UnitLength>> {
        switch self {
        case .upErrorDistance: \.upErrorDistance
        case .downErrorDistance: \.downErrorDistance
        case .spaceUpErrorDistance: \.spaceUpErrorDistance
        case .spaceDownErrorDistance: \.spaceDownErrorDistance
        case .deleteUpErrorDistance: \.deleteUpErrorDistance
        case .deleteDownErrorDistance: \.deleteDownErrorDistance
        case .shortWordCharKeyUpErrorDistance: \.shortWordCharKeyUpErrorDistance
        case .shortWordCharKeyDownErrorDistance: \.shortWordCharKeyDownErrorDistance
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation.DurationDistribution {
    var keyPath: KeyPath<SRKeyboardMetrics, SRKeyboardMetrics.ProbabilityMetric<UnitDuration>> {
        switch self {
        case .touchDownUp: \.touchDownUp
        case .spaceTouchDownUp: \.spaceTouchDownUp
        case .deleteTouchDownUp: \.deleteTouchDownUp
        case .shortWordCharKeyTouchDownUp: \.shortWordCharKeyTouchDownUp
        case .touchDownDown: \.touchDownDown
        case .touchUpDown: \.touchUpDown
        case .charKeyToPrediction: \.charKeyToPrediction
        case .shortWordCharKeyToCharKey: \.shortWordCharKeyToCharKey
        case .charKeyToAnyTapKey: \.charKeyToAnyTapKey
        case .anyTapToCharKey: \.anyTapToCharKey
        case .spaceToCharKey: \.spaceToCharKey
        case .charKeyToSpaceKey: \.charKeyToSpaceKey
        case .spaceToDeleteKey: \.spaceToDeleteKey
        case .deleteToSpaceKey: \.deleteToSpaceKey
        case .spaceToSpaceKey: \.spaceToSpaceKey
        case .spaceToShiftKey: \.spaceToShiftKey
        case .spaceToPlaneChangeKey: \.spaceToPlaneChangeKey
        case .spaceToPredictionKey: \.spaceToPredictionKey
        case .deleteToCharKey: \.deleteToCharKey
        case .charKeyToDelete: \.charKeyToDelete
        case .deleteToDelete: \.deleteToDelete
        case .deleteToShiftKey: \.deleteToShiftKey
        case .deleteToPlaneChangeKey: \.deleteToPlaneChangeKey
        case .anyTapToPlaneChangeKey: \.anyTapToPlaneChangeKey
        case .planeChangeToAnyTap: \.planeChangeToAnyTap
        case .charKeyToPlaneChangeKey: \.charKeyToPlaneChangeKey
        case .planeChangeKeyToCharKey: \.planeChangeKeyToCharKey
        case .deleteToPath: \.deleteToPath
        case .pathToDelete: \.pathToDelete
        case .spaceToPath: \.spaceToPath
        case .pathToSpace: \.pathToSpace
        case .pathToPath: \.pathToPath
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation.PositionalLengthDistribution {
    var keyPath: KeyPath<SRKeyboardMetrics, [SRKeyboardMetrics.ProbabilityMetric<UnitLength>]> {
        switch self {
        case .longWordUpErrorDistance: \.longWordUpErrorDistance
        case .longWordDownErrorDistance: \.longWordDownErrorDistance
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation.PositionalDurationDistribution {
    var keyPath: KeyPath<SRKeyboardMetrics, [SRKeyboardMetrics.ProbabilityMetric<UnitDuration>]> {
        switch self {
        case .longWordTouchDownUp: \.longWordTouchDownUp
        case .longWordTouchDownDown: \.longWordTouchDownDown
        case .longWordTouchUpDown: \.longWordTouchUpDown
        case .deleteToDeletes: \.deleteToDeletes
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SRKeyboardMetrics.SafeRepresentation.Sentiment {
    var category: SRKeyboardMetrics.SentimentCategory {
        switch self {
        case .absolutist: .absolutist
        case .down: .down
        case .death: .death
        case .anxiety: .anxiety
        case .anger: .anger
        case .health: .health
        case .positive: .positive
        case .sad: .sad
        case .lowEnergy: .lowEnergy
        case .confused: .confused
        }
    }
}
