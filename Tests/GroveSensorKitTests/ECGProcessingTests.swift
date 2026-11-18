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
struct ECGProcessingTests {
    @available(iOS 17.4, *)
    @Test(arguments: ["begin", "active", "end", "empty"])
    func incompleteSessionsRefuseTheCompleteCallback(missing: String) throws {
        let groups = Self.groups().filter { group in
            (missing != "begin" || group.state != .begin) && (missing != "active" || group.state != .active) && (missing != "end" || group.state != .end)
        }
        let input = missing == "empty" ? groups.map { group in
            SensorKitECGSession.InputGroup(
                identifier: group.identifier,
                state: group.state,
                guidance: group.guidance,
                readings: group.state == .active ? [] : group.readings
            )
        } : groups
        #expect(throws: SensorKitECGSession.ProcessingError.incompleteSession) { try SensorKitECGSession.process(input) }
    }

    @available(iOS 17.4, *)
    @Test(arguments: ["frequency", "lead", "duplicate-active"])
    func inconsistentSessionFactsAreExplicitErrors(field: String) throws {
        var groups = Self.groups(changing: field)
        if field == "duplicate-active" { groups.append(groups[1]) }
        #expect(throws: SensorKitECGSession.ProcessingError.inconsistentSession) { try SensorKitECGSession.process(groups) }
    }

    @available(iOS 17.4, *)
    @Test(arguments: ["duplicate-date", "before-begin", "nonfinite-frequency"])
    func invalidTimingCannotBecomeAnAcknowledgedSession(field: String) throws {
        #expect(throws: SensorKitECGSession.ProcessingError.invalidTiming) { try SensorKitECGSession.process(Self.groups(changing: field)) }
    }

    @available(iOS 17.4, *)
    @Test
    func outOfOrderReadingsKeepEverySampleInDeterministicOrder() throws {
        let first = try #require(SensorKitECGSession.process(Self.groups()).first)
        let reversed = Self.groups().reversed().map { group in
            SensorKitECGSession.InputGroup(
                identifier: group.identifier, state: group.state, guidance: group.guidance, readings: Array(group.readings.reversed())
            )
        }
        let replay = try #require(SensorKitECGSession.process(reversed).first)
        #expect(first == replay)
        #expect(first.batches.map(\.offset) == [0, 1])
        #expect(first.batches.map { $0.samples.count } == [1, 1])
    }
}


extension ECGProcessingTests {
    @available(iOS 17.4, *)
    static func groups(changing field: String = "") -> [SensorKitECGSession.InputGroup] {
        let start = Date(timeIntervalSince1970: 100)
        func reading(_ index: Int, active: Bool) -> SensorKitECGSession.InputReading {
            let frequency = field == "nonfinite-frequency" ? Double.infinity : field == "frequency" && index == 1 ? 256.0 : 512.0
            let offset = field == "duplicate-date" ? 0.0 : field == "before-begin" ? -1.0 : Double(index)
            return .init(
                date: active ? start.addingTimeInterval(offset) : start,
                frequency: Measurement(value: frequency, unit: .hertz),
                lead: field == "lead" && index == 1 ? .leftArmMinusRightArm : .rightArmMinusLeftArm,
                samples: active ? [.init(flags: [], voltage: Measurement(value: 1, unit: .microvolts))] : []
            )
        }
        return [
            .init(identifier: "synthetic-session", state: .begin, guidance: .guided, readings: [reading(0, active: false)]),
            .init(identifier: "synthetic-session", state: .active, guidance: .guided, readings: [reading(0, active: true), reading(1, active: true)]),
            .init(identifier: "synthetic-session", state: .end, guidance: .guided, readings: [])
        ]
    }
}
#endif
