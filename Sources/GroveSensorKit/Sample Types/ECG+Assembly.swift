//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SensorKit


/// Holds only immutable public ECG facts between native callbacks.
///
/// No batch is delivered while a session is unfinished; ``finish()`` ends every pending session when the fetch completes.
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
            output.append(contentsOf: try SensorKitECGSession.process(Self.merged(groups, identifier: identifier)))
            pending.removeValue(forKey: identifier)
            completed.insert(identifier)
        }
        return output.sorted { ($0.startDate, $0.sessionIdentifier) < ($1.startDate, $1.sessionIdentifier) }
    }

    /// Ends assembly when the fetch completes, so an unfinished session neither fails the fetch nor holds back later batches.
    ///
    /// Every pending session is assembled as a time-range fetch assembles it: one without its end state is returned,
    /// and one without its begin state or voltage samples, or with inconsistent facts, is skipped and counted.
    mutating func finish() -> (sessions: [SensorKitECGSession], skippedSessionCount: Int) {
        var sessions: [SensorKitECGSession] = []
        for (identifier, groups) in pending {
            if let merged = try? Self.merged(groups, identifier: identifier) {
                sessions += SensorKitECGSession.processLeniently(merged)
            }
            completed.insert(identifier)
        }
        let skippedSessionCount = pending.count - sessions.count
        pending.removeAll()
        return (sessions.sorted { ($0.startDate, $0.sessionIdentifier) < ($1.startDate, $1.sessionIdentifier) }, skippedSessionCount)
    }

    mutating func resetCompletedBoundary() {
        guard pending.isEmpty else {
            return
        }
        completed.removeAll(keepingCapacity: true)
        voltageSamples = 0
    }
}


@available(iOS 17.4, *)
extension SensorKitECGAssembly {
    fileprivate static func merged(
        _ groups: [SensorKitECGSession.InputGroup],
        identifier: String
    ) throws -> [SensorKitECGSession.InputGroup] {
        try Dictionary(grouping: groups, by: \.state).map { state, parts in
            guard let first = parts.first, parts.allSatisfy({ $0.guidance == first.guidance }) else {
                throw SensorKitECGSession.ProcessingError.inconsistentSession
            }
            return SensorKitECGSession.InputGroup(
                identifier: identifier, state: state, guidance: first.guidance, readings: parts.flatMap(\.readings)
            )
        }
    }
}
