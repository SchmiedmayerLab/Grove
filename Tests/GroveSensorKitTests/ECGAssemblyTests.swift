//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
@testable import GroveSensorKit
import SensorKit
import Testing


@Suite
struct ECGAssemblyTests {
    @Test
    @available(iOS 18, *)
    func splitCallbacksMatchWholeSessionAndRestartReplay() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append([groups[0]], at: 1).sessions.isEmpty)
        #expect(assembly.pendingTimestamps != nil)
        let active = groups[1]
        let fragments = active.readings.map {
            SensorKitECGSession.InputGroup(identifier: active.identifier, state: .active, guidance: active.guidance, readings: [$0])
        }
        for fragment in fragments { #expect(try assembly.append([fragment], at: 2).sessions.isEmpty) }
        #expect(assembly.pendingTimestamps != nil)
        let completed = try assembly.append([groups[2]], at: 3)
        #expect(completed.sessions == (try SensorKitECGSession.process(groups)))
        #expect(completed.skippedSessionCount == 0)
        #expect(assembly.pendingTimestamps == nil)
        let remaining = assembly.finishPending()
        #expect(remaining.sessions.isEmpty)
        var restarted = SensorKitECGAssembly()
        #expect(try restarted.append(groups, at: 3).sessions == completed.sessions)
    }

    @Test(arguments: ["frequency", "duplicate-date", "empty"])
    @available(iOS 18, *)
    func completeButUnusableSessionIsSkippedAndTheNextOneDelivered(field: String) throws {
        var unusable = ECGProcessingTests.groups(changing: field == "empty" ? "" : field).map { group in
            SensorKitECGSession.InputGroup(identifier: "unusable-session", state: group.state, guidance: group.guidance, readings: group.readings)
        }
        if field == "empty" {
            unusable[1] = .init(identifier: "unusable-session", state: .active, guidance: .guided, readings: [])
        }
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly()
        let skipped = try assembly.append(unusable, at: 1)
        #expect(skipped.sessions.isEmpty)
        #expect(skipped.skippedSessionCount == 1)
        #expect(assembly.pendingTimestamps == nil)
        #expect(try assembly.append(groups, at: 2).sessions == (try SensorKitECGSession.process(groups)))
    }

    @Test
    @available(iOS 18, *)
    func fragmentOfACompletedSessionIsSkipped() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append(groups, at: 1).sessions.count == 1)
        let late = try assembly.append([groups[1]], at: 2)
        #expect(late.sessions.isEmpty)
        #expect(late.skippedSessionCount == 1)
        #expect(assembly.pendingTimestamps == nil)
    }

    @Test
    @available(iOS 18, *)
    func unfinishedSessionsStateTheirFirstAndLatestTimestamps() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append([groups[0]], at: 5).sessions.isEmpty)
        #expect(try assembly.append([groups[1]], at: 6).sessions.isEmpty)
        let pending = try #require(assembly.pendingTimestamps)
        #expect(pending.earliest == 5)
        #expect(pending.latest == 6)
        // Data of the same session and a callback without groups end nothing.
        let sameSession = assembly.finishPending(supersededBy: [groups[1]])
        let withoutGroups = assembly.finishPending(supersededBy: [])
        #expect(sameSession.sessions.isEmpty && sameSession.skippedSessionCount == 0)
        #expect(withoutGroups.sessions.isEmpty && withoutGroups.skippedSessionCount == 0)
        #expect(assembly.pendingTimestamps != nil)
    }

    @Test
    @available(iOS 18, *)
    func dataOfAnotherSessionEndsTheUnfinishedOnes() throws {
        let groups = ECGProcessingTests.groups()
        let withoutEnd = Array(groups.prefix(2))
        let withoutVoltage = SensorKitECGSession.InputGroup(identifier: "other-session", state: .begin, guidance: .guided, readings: [])
        let later = groups.map { group in
            SensorKitECGSession.InputGroup(identifier: "later-session", state: group.state, guidance: group.guidance, readings: group.readings)
        }
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append(withoutEnd + [withoutVoltage], at: 1).sessions.isEmpty)
        let finished = assembly.finishPending(supersededBy: later)
        #expect(finished.sessions == SensorKitECGSession.processLeniently(withoutEnd))
        #expect(finished.sessions.map(\.sessionStates) == [[.begin, .active]])
        #expect(finished.skippedSessionCount == 1)
        #expect(assembly.pendingTimestamps == nil)
        #expect(try assembly.append(later, at: 2).sessions.count == 1)
        // A later fragment of a session that ended this way is skipped, like one of a completed session.
        let late = try assembly.append([groups[2]], at: 3)
        #expect(late.sessions.isEmpty)
        #expect(late.skippedSessionCount == 1)
        #expect(assembly.pendingTimestamps == nil)
    }

    @Test
    @available(iOS 18, *)
    func fragmentWithoutItsBeginStateNeitherStartsNorEndsASession() throws {
        let groups = ECGProcessingTests.groups()
        let fragment = SensorKitECGSession.InputGroup(
            identifier: "delivered-session", state: .active, guidance: .guided, readings: groups[1].readings
        )
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append([groups[0]], at: 1).sessions.isEmpty)
        // A fragment of a session the assembly doesn't know, such as one delivered before a batch boundary, can't
        // become a session without its begin state, so it is skipped and the unfinished session continues.
        #expect(assembly.finishPending(supersededBy: [fragment]).sessions.isEmpty)
        let skipped = try assembly.append([fragment], at: 2)
        #expect(skipped.sessions.isEmpty)
        #expect(skipped.skippedSessionCount == 1)
        #expect(assembly.pendingTimestamps?.earliest == 1)
        #expect(assembly.pendingTimestamps?.latest == 1)
        #expect(try assembly.append(Array(groups.dropFirst()), at: 3).sessions == SensorKitECGSession.process(groups))
    }

    @Test
    @available(iOS 18, *)
    func neverEndingSessionStopsAtAnExplicitCapacityWithoutDroppingFragments() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 2, maximumSessions: 128))
        #expect(try assembly.append([groups[0]], at: 1).sessions.isEmpty)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([groups[1]], at: 2) }
        // A refused callback adds nothing, so the session is still the one its first callback started.
        #expect(assembly.pendingTimestamps?.latest == 1)
    }

    @Test
    @available(iOS 18, *)
    func emptyFragmentsConsumeCapacityWithoutAdvancingACompletedBoundary() throws {
        let empty = SensorKitECGSession.InputGroup(identifier: "session", state: .begin, guidance: .guided, readings: [])
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 2, maximumSessions: 1))
        #expect(try assembly.append([empty, empty], at: 1).sessions.isEmpty)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([empty], at: 2) }
        #expect(assembly.pendingTimestamps != nil)
    }

    @Test
    @available(iOS 18, *)
    func sessionCountBoundIsAnExplicitFailure() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 1_000_000, maximumSessions: 1))
        #expect(try assembly.append(groups, at: 1).sessions.count == 1)
        let other = SensorKitECGSession.InputGroup(identifier: "other-session", state: .begin, guidance: .guided, readings: groups[0].readings)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([other], at: 2) }
        let forgotSessions = assembly.forgetFinishedSessions()
        #expect(forgotSessions)
        #expect(try assembly.append([other], at: 2).sessions.isEmpty)
        let forgotMoreSessions = assembly.forgetFinishedSessions()
        #expect(!forgotMoreSessions)
    }

    @Test
    @available(iOS 18, *)
    func skippedSessionsReleaseTheirEntries() throws {
        let abandoned = SensorKitECGSession.InputGroup(identifier: "abandoned-session", state: .begin, guidance: .guided, readings: [])
        let groups = ECGProcessingTests.groups()
        // One complete session takes four entries: its begin marker, two voltage samples and its end marker.
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 4, maximumSessions: 128))
        #expect(try assembly.append([abandoned], at: 1).sessions.isEmpty)
        let superseded = assembly.finishPending(supersededBy: groups)
        #expect(superseded.skippedSessionCount == 1)
        #expect(try assembly.append(groups, at: 2).sessions.count == 1)
    }
}
#endif
