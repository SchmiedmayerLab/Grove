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
        #expect(assembly.hasPendingSession)
        let active = groups[1]
        let fragments = active.readings.map {
            SensorKitECGSession.InputGroup(identifier: active.identifier, state: .active, guidance: active.guidance, readings: [$0])
        }
        for fragment in fragments { #expect(try assembly.append([fragment], at: 2).sessions.isEmpty) }
        #expect(assembly.hasPendingSession)
        let completed = try assembly.append([groups[2]], at: 3)
        #expect(completed.sessions == (try SensorKitECGSession.process(groups)))
        #expect(completed.skippedSessionCount == 0)
        #expect(!assembly.hasPendingSession)
        #expect(assembly.finish().sessions.isEmpty)
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
        #expect(!assembly.hasPendingSession)
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
        #expect(!assembly.hasPendingSession)
    }

    @Test
    @available(iOS 18, *)
    func fetchEndHoldsTheLatestUnfinishedSession() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append([groups[0]], at: 5).sessions.isEmpty)
        #expect(try assembly.append([groups[1]], at: 6).sessions.isEmpty)
        let finished = assembly.finish()
        #expect(finished.sessions.isEmpty)
        #expect(finished.skippedSessionCount == 0)
        #expect(finished.heldFrom == 5)
        #expect(!assembly.hasPendingSession)
    }

    @Test
    @available(iOS 18, *)
    func fetchEndFinishesSessionsThatLaterDataFollowed() throws {
        let groups = ECGProcessingTests.groups()
        let withoutEnd = Array(groups.prefix(2))
        let withoutVoltage = SensorKitECGSession.InputGroup(identifier: "other-session", state: .begin, guidance: .guided, readings: [])
        let later = groups.map { group in
            SensorKitECGSession.InputGroup(identifier: "later-session", state: group.state, guidance: group.guidance, readings: group.readings)
        }
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append(withoutEnd + [withoutVoltage], at: 1).sessions.isEmpty)
        #expect(try assembly.append(later, at: 2).sessions.count == 1)
        let finished = assembly.finish()
        #expect(finished.sessions == SensorKitECGSession.processLeniently(withoutEnd))
        #expect(finished.sessions.map(\.sessionStates) == [[.begin, .active]])
        #expect(finished.skippedSessionCount == 1)
        #expect(finished.heldFrom == nil)
    }

    @Test
    @available(iOS 18, *)
    func neverEndingSessionStopsAtAnExplicitCapacityWithoutDroppingFragments() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 2, maximumSessions: 128))
        #expect(try assembly.append([groups[0]], at: 1).sessions.isEmpty)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([groups[1]], at: 2) }
        #expect(assembly.hasPendingSession)
    }

    @Test
    @available(iOS 18, *)
    func emptyFragmentsConsumeCapacityWithoutAdvancingACompletedBoundary() throws {
        let empty = SensorKitECGSession.InputGroup(identifier: "session", state: .begin, guidance: .guided, readings: [])
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 2, maximumSessions: 1))
        #expect(try assembly.append([empty, empty], at: 1).sessions.isEmpty)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([empty], at: 2) }
        #expect(assembly.hasPendingSession)
    }

    @Test
    @available(iOS 18, *)
    func sessionCountBoundIsAnExplicitFailure() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 1_000_000, maximumSessions: 1))
        #expect(try assembly.append(groups, at: 1).sessions.count == 1)
        let other = SensorKitECGSession.InputGroup(identifier: "other-session", state: .begin, guidance: .guided, readings: groups[0].readings)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([other], at: 2) }
        assembly.resetCompletedBoundary()
        #expect(try assembly.append([other], at: 2).sessions.isEmpty)
    }
}
#endif
