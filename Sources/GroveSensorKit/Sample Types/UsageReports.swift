//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SensorKit


extension SRMessagesUsageReport: SensorKitSampleProtocol {
    /// Every public field of a messages-usage report, copied on the SensorKit callback thread.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The time SensorKit states for the report.
        public let timestamp: Date
        /// The length of the reporting interval, in seconds.
        public let duration: TimeInterval
        /// The number of messages the person sent during the interval.
        public let totalOutgoingMessages: Int
        /// The number of messages the person received during the interval.
        public let totalIncomingMessages: Int
        /// The number of distinct contacts the person exchanged messages with during the interval.
        public let totalUniqueContacts: Int
        /// The report's ``timestamp``, as an empty range.
        public var timeRange: Range<Date> { timestamp..<timestamp }

        /// Creates a report from its fields.
        public init(timestamp: Date, duration: TimeInterval, totalOutgoingMessages: Int, totalIncomingMessages: Int, totalUniqueContacts: Int) {
            self.timestamp = timestamp
            self.duration = duration
            self.totalOutgoingMessages = totalOutgoingMessages
            self.totalIncomingMessages = totalIncomingMessages
            self.totalUniqueContacts = totalUniqueContacts
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRMessagesUsageReport)>
    ) -> [SafeRepresentation] {
        samples.map { timestamp, report in
            SafeRepresentation(
                timestamp: timestamp,
                duration: report.duration,
                totalOutgoingMessages: report.totalOutgoingMessages,
                totalIncomingMessages: report.totalIncomingMessages,
                totalUniqueContacts: report.totalUniqueContacts
            )
        }
    }
}


extension SRPhoneUsageReport: SensorKitSampleProtocol {
    /// Every public field of a phone-usage report, copied on the SensorKit callback thread.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The time SensorKit states for the report.
        public let timestamp: Date
        /// The length of the reporting interval, in seconds.
        public let duration: TimeInterval
        /// The number of calls the person placed during the interval.
        public let totalOutgoingCalls: Int
        /// The number of calls the person received during the interval.
        public let totalIncomingCalls: Int
        /// The number of distinct contacts the person called or was called by during the interval.
        public let totalUniqueContacts: Int
        /// The total length of the person's calls during the interval, in seconds.
        public let totalPhoneCallDuration: TimeInterval
        /// The report's ``timestamp``, as an empty range.
        public var timeRange: Range<Date> { timestamp..<timestamp }

        /// Creates a report from its fields.
        public init(
            timestamp: Date,
            duration: TimeInterval,
            totalOutgoingCalls: Int,
            totalIncomingCalls: Int,
            totalUniqueContacts: Int,
            totalPhoneCallDuration: TimeInterval
        ) {
            self.timestamp = timestamp
            self.duration = duration
            self.totalOutgoingCalls = totalOutgoingCalls
            self.totalIncomingCalls = totalIncomingCalls
            self.totalUniqueContacts = totalUniqueContacts
            self.totalPhoneCallDuration = totalPhoneCallDuration
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRPhoneUsageReport)>
    ) -> [SafeRepresentation] {
        samples.map { timestamp, report in
            SafeRepresentation(
                timestamp: timestamp,
                duration: report.duration,
                totalOutgoingCalls: report.totalOutgoingCalls,
                totalIncomingCalls: report.totalIncomingCalls,
                totalUniqueContacts: report.totalUniqueContacts,
                totalPhoneCallDuration: report.totalPhoneCallDuration
            )
        }
    }
}
