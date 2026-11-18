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
        public let timestamp: Date
        public let duration: TimeInterval
        public let totalOutgoingMessages: Int
        public let totalIncomingMessages: Int
        public let totalUniqueContacts: Int
        public var timeRange: Range<Date> { timestamp..<timestamp }

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
        public let timestamp: Date
        public let duration: TimeInterval
        public let totalOutgoingCalls: Int
        public let totalIncomingCalls: Int
        public let totalUniqueContacts: Int
        public let totalPhoneCallDuration: TimeInterval
        public var timeRange: Range<Date> { timestamp..<timestamp }

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
