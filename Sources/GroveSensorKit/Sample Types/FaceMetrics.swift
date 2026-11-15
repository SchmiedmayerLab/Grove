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
extension SRFaceMetrics: SensorKitSampleProtocol {
    /// The session facts and expressions of a face-metrics sample, copied on the SensorKit callback thread.
    ///
    /// - Important: `SRFaceMetrics.faceAnchor` is not copied. The property exists only in device builds, and its
    ///     `ARFaceAnchor` carries the face's complete geometry.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// One detected expression and its strength.
        public struct Expression: Hashable, Sendable {
            public let identifier: String
            public let value: Double

            /// Creates an expression.
            public init(identifier: String, value: Double) {
                self.identifier = identifier
                self.value = value
            }
        }

        /// The point in time when the system recorded the sample.
        public let timestamp: Date
        /// The version of the algorithm that produced the metrics.
        public let version: String
        public let sessionIdentifier: String
        public let context: SRFaceMetrics.Context
        public let wholeFaceExpressions: [Expression]
        public let partialFaceExpressions: [Expression]

        public var timeRange: Range<Date> { timestamp..<timestamp }

        /// Creates a face-metrics sample.
        public init(
            timestamp: Date,
            version: String,
            sessionIdentifier: String,
            context: SRFaceMetrics.Context,
            wholeFaceExpressions: [Expression],
            partialFaceExpressions: [Expression]
        ) {
            self.timestamp = timestamp
            self.version = version
            self.sessionIdentifier = sessionIdentifier
            self.context = context
            self.wholeFaceExpressions = wholeFaceExpressions
            self.partialFaceExpressions = partialFaceExpressions
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(timestamp)
            hasher.combine(version)
            hasher.combine(sessionIdentifier)
            hasher.combine(context.rawValue)
            hasher.combine(wholeFaceExpressions)
            hasher.combine(partialFaceExpressions)
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRFaceMetrics)>
    ) -> [SafeRepresentation] {
        samples.map { timestamp, sample in
            SafeRepresentation(
                timestamp: timestamp,
                version: sample.version,
                sessionIdentifier: sample.sessionIdentifier,
                context: sample.context,
                wholeFaceExpressions: sample.wholeFaceExpressions.map { .init(identifier: $0.identifier, value: $0.value) },
                partialFaceExpressions: sample.partialFaceExpressions.map { .init(identifier: $0.identifier, value: $0.value) }
            )
        }
    }
}
