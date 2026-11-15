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
extension SRMediaEvent: SensorKitSampleProtocol {
    /// Every public field of a media event, copied on the SensorKit callback thread.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the system recorded the event.
        public let timestamp: Date
        /// The identifier SensorKit assigns to the media, which pairs an on-screen event with its off-screen event.
        public let mediaIdentifier: String
        public let eventType: SRMediaEventType

        public var timeRange: Range<Date> { timestamp..<timestamp }

        /// Creates a media event.
        public init(timestamp: Date, mediaIdentifier: String, eventType: SRMediaEventType) {
            self.timestamp = timestamp
            self.mediaIdentifier = mediaIdentifier
            self.eventType = eventType
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRMediaEvent)>
    ) -> [SafeRepresentation] {
        samples.map { SafeRepresentation(timestamp: $0.timestamp, mediaIdentifier: $0.sample.mediaIdentifier, eventType: $0.sample.eventType) }
    }
}
