//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SensorKit


/// Holds only immutable public ECG facts between native callbacks. No acquisition cursor can cross an unfinished session.
@available(iOS 17.4, *)
struct SensorKitECGAssembly {
    private let maximumVoltageSamples: Int
    private let maximumSessions: Int
    private var pending: [String: [SensorKitECGSession.InputGroup]] = [:]
    private var completed: Set<String> = []
    private var voltageSamples = 0

    var hasPendingSession: Bool { !pending.isEmpty }

    init(limits: SensorKitECGProcessingLimits = .init()) {
        self.maximumVoltageSamples = limits.maximumEntries
        self.maximumSessions = limits.maximumSessions
    }

    mutating func append(_ groups: [SensorKitECGSession.InputGroup]) throws -> [SensorKitECGSession] {
        var output: [SensorKitECGSession] = []
        for group in groups {
            guard !completed.contains(group.identifier) else { throw SensorKitECGSession.ProcessingError.inconsistentSession }
            guard !group.identifier.isEmpty, group.identifier.utf8.count <= 4096,
                  pending[group.identifier] != nil || pending.count + completed.count < maximumSessions else {
                throw SensorKitECGSession.ProcessingError.assemblyCapacityExceeded
            }
            let added = max(1, group.readings.reduce(0) { $0 + max(1, $1.samples.count) })
            guard added <= maximumVoltageSamples - voltageSamples else { throw SensorKitECGSession.ProcessingError.assemblyCapacityExceeded }
            voltageSamples += added
            pending[group.identifier, default: []].append(group)
        }
        for identifier in pending.keys.sorted() {
            guard let groups = pending[identifier],
                  groups.contains(where: { $0.state == .begin }), groups.contains(where: { $0.state == .active }),
                  groups.contains(where: { $0.state == .end }) else { continue }
            let merged = try Dictionary(grouping: groups, by: \.state).map { state, parts in
                guard let first = parts.first, parts.allSatisfy({ $0.guidance == first.guidance }) else {
                    throw SensorKitECGSession.ProcessingError.inconsistentSession
                }
                let readings = parts.flatMap(\.readings)
                return SensorKitECGSession.InputGroup(identifier: identifier, state: state, guidance: first.guidance, readings: readings)
            }
            output.append(contentsOf: try SensorKitECGSession.process(merged))
            pending.removeValue(forKey: identifier)
            completed.insert(identifier)
        }
        return output.sorted { ($0.startDate, $0.sessionIdentifier) < ($1.startDate, $1.sessionIdentifier) }
    }

    func finish() throws {
        guard pending.isEmpty else { throw SensorKitECGSession.ProcessingError.incompleteSession }
    }

    mutating func resetCompletedBoundary() {
        guard pending.isEmpty else {
            return
        }
        completed.removeAll(keepingCapacity: true)
        voltageSamples = 0
    }
}
