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
        #expect(try assembly.append([groups[0]]).isEmpty)
        #expect(assembly.hasPendingSession)
        let active = groups[1]
        let fragments = active.readings.map {
            SensorKitECGSession.InputGroup(identifier: active.identifier, state: .active, guidance: active.guidance, readings: [$0])
        }
        for fragment in fragments { #expect(try assembly.append([fragment]).isEmpty) }
        #expect(throws: SensorKitECGSession.ProcessingError.incompleteSession) { try assembly.finish() }
        let completed = try assembly.append([groups[2]])
        #expect(completed == (try SensorKitECGSession.process(groups)))
        #expect(!assembly.hasPendingSession)
        try assembly.finish()
        var restarted = SensorKitECGAssembly()
        #expect(try restarted.append(groups) == completed)
    }

    @Test
    @available(iOS 18, *)
    func anotherIncompleteSessionPreventsAnAcknowledgedBoundary() throws {
        let groups = ECGProcessingTests.groups()
        let pending = SensorKitECGSession.InputGroup(identifier: "other-session", state: .begin, guidance: .guided, readings: groups[0].readings)
        var assembly = SensorKitECGAssembly()
        #expect(try assembly.append(groups + [pending]).count == 1)
        #expect(assembly.hasPendingSession)
        #expect(throws: SensorKitECGSession.ProcessingError.incompleteSession) { try assembly.finish() }
    }

    @Test
    @available(iOS 18, *)
    func neverEndingSessionStopsAtAnExplicitCapacityWithoutDroppingFragments() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 2, maximumSessions: 128))
        #expect(try assembly.append([groups[0]]).isEmpty)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([groups[1]]) }
        #expect(assembly.hasPendingSession)
        #expect(throws: SensorKitECGSession.ProcessingError.incompleteSession) { try assembly.finish() }
    }

    @Test
    @available(iOS 18, *)
    func emptyFragmentsConsumeCapacityWithoutAdvancingACompletedBoundary() throws {
        let empty = SensorKitECGSession.InputGroup(identifier: "session", state: .begin, guidance: .guided, readings: [])
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 2, maximumSessions: 1))
        #expect(try assembly.append([empty, empty]).isEmpty)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([empty]) }
        #expect(assembly.hasPendingSession)
        #expect(throws: SensorKitECGSession.ProcessingError.incompleteSession) { try assembly.finish() }
    }

    @Test
    @available(iOS 18, *)
    func sessionCountBoundAndPostCompletionFragmentsAreExplicitFailures() throws {
        let groups = ECGProcessingTests.groups()
        var assembly = SensorKitECGAssembly(limits: try .init(maximumEntries: 1_000_000, maximumSessions: 1))
        #expect(try assembly.append(groups).count == 1)
        #expect(throws: SensorKitECGSession.ProcessingError.inconsistentSession) { try assembly.append([groups[1]]) }
        let other = SensorKitECGSession.InputGroup(identifier: "other-session", state: .begin, guidance: .guided, readings: groups[0].readings)
        #expect(throws: SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) { try assembly.append([other]) }
        assembly.resetCompletedBoundary()
        #expect(try assembly.append([other]).isEmpty)
    }
}
#endif
