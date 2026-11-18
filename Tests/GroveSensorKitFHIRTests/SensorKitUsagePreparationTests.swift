//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

import Foundation
import GroveFHIRContract
import GroveSensorKit
import GroveSensorKitFHIR
import SensorKit
import Testing


struct SensorKitUsagePreparationTests {
    @Test
    func messagesRetainEveryPublicFieldAndStableRetryEvidence() throws {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = SRMessagesUsageReport.SafeRepresentation(
            timestamp: instant, duration: 60, totalOutgoingMessages: 3, totalIncomingMessages: 4, totalUniqueContacts: 5
        )
        let prepared = try SensorKitPreparedStructuredRecord(messagesUsage: sample)
        #expect(prepared.nativePayload == nil)
        #expect(try SensorKitPreparedStructuredRecord(messagesUsage: sample).retryEvidence == prepared.retryEvidence)
        let identity = SensorKitSourceRecordID(UUID())
        guard case .messagesUsage(let record) = try prepared.sensorKitRecord(sourceRecordID: identity) else {
            Issue.record("Expected messages usage record")
            return
        }
        #expect(record.sourceRecordID == identity)
        #expect(record.timestamp == instant)
        #expect(record.durationSeconds == 60)
        #expect(record.totalOutgoingMessages == 3)
        #expect(record.totalIncomingMessages == 4)
        #expect(record.totalUniqueContacts == 5)
        let changed = SRMessagesUsageReport.SafeRepresentation(
            timestamp: instant, duration: 60, totalOutgoingMessages: 3, totalIncomingMessages: 4, totalUniqueContacts: 6
        )
        #expect(try SensorKitPreparedStructuredRecord(messagesUsage: changed).retryEvidence != prepared.retryEvidence)
    }

    @Test
    func phoneDurationParticipatesInBothProjectionAndRetryEvidence() throws {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        func sample(duration: Double) -> SRPhoneUsageReport.SafeRepresentation {
            .init(
                timestamp: instant,
                duration: 60,
                totalOutgoingCalls: 1,
                totalIncomingCalls: 2,
                totalUniqueContacts: 3,
                totalPhoneCallDuration: duration
            )
        }
        let prepared = try SensorKitPreparedStructuredRecord(phoneUsage: sample(duration: 40))
        let changed = try SensorKitPreparedStructuredRecord(phoneUsage: sample(duration: 41))
        #expect(prepared.retryEvidence != changed.retryEvidence)
        #expect(prepared.nativePayload == nil)
        guard case .phoneUsage(let record) = try prepared.sensorKitRecord(sourceRecordID: .init(UUID())) else {
            Issue.record("Expected phone usage record")
            return
        }
        #expect(record.timestamp == instant)
        #expect(record.durationSeconds == 60)
        #expect(record.totalOutgoingCalls == 1)
        #expect(record.totalIncomingCalls == 2)
        #expect(record.totalUniqueContacts == 3)
        #expect(record.totalPhoneCallDurationSeconds == 40)
    }
}

#endif
