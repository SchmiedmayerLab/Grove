//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

public import Foundation
public import GroveFoundation
public import SensorKit


@available(iOS 26, *)
extension SRSleepSession: SensorKitSampleProtocol {
    /// Exact public session facts, including the native identifier independently of query coordinates.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        public let timestamp: Date
        public let startDate: Date
        public let duration: TimeInterval
        public let identifier: String

        /// The SensorKit delivery timestamp controls the acquisition cursor; session bounds are separate facts.
        public var timeRange: Range<Date> { timestamp..<timestamp }

        public init(timestamp: Date, startDate: Date, duration: TimeInterval, identifier: String) {
            self.timestamp = timestamp
            self.startDate = startDate
            self.duration = duration
            self.identifier = identifier
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRSleepSession)>
    ) -> [SafeRepresentation] {
        samples.map { timestamp, sample in
            SafeRepresentation(timestamp: timestamp, startDate: sample.startDate, duration: sample.duration, identifier: sample.identifier)
        }
    }
}


@available(iOS 26, *)
extension Sensor where Sample == SRSleepSession {
    /// Sleep sessions recorded by SensorKit, including each session's native identifier.
    @inlinable public static var sleepSessions: Sensor<SRSleepSession> {
        Sensor(
            srSensor: .sleepSessions,
            displayName: "Sleep Sessions",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

#endif
