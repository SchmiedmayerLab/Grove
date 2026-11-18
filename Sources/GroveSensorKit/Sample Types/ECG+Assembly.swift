//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SensorKit


/// Holds only immutable public ECG facts between the native callbacks of one fetch.
///
/// A session is delivered once its begin, active and end states have arrived. A session that has them all but can't be
/// assembled (inconsistent facts, invalid timing, no voltage samples), and a fragment of a session that already
/// completed, is skipped and counted instead of failing the fetch. Only exceeding the ``SensorKitECGProcessingLimits``
/// fails it. When the fetch completes, ``finish()`` decides each unfinished session; see there.
///
/// The native timestamps are those of the fetch results; the sessions of one device don't overlap in time.
@available(iOS 17.4, *)
struct SensorKitECGAssembly {
    /// The sessions one native callback completed, and how many sessions or late fragments it skipped.
    struct Output {
        var sessions: [SensorKitECGSession] = []
        var skippedSessionCount = 0
    }

    /// How the fetch's unfinished sessions end.
    struct Completion {
        /// The unfinished sessions later native data followed, which can therefore never complete.
        var sessions: [SensorKitECGSession] = []
        /// The unfinished sessions later native data followed that can't be assembled even without an end state.
        var skippedSessionCount = 0
        /// The earliest native timestamp of an unfinished session the fetch saw no later data after. The delivered
        /// boundary must stay before it, so the next fetch reads that session whole.
        var heldFrom: Double?
    }

    private struct Pending {
        var groups: [SensorKitECGSession.InputGroup] = []
        let firstTimestamp: Double
        var lastTimestamp: Double

        var hasEveryState: Bool {
            [.begin, .active, .end].allSatisfy { state in groups.contains { $0.state == state } }
        }
    }

    private let maximumVoltageSamples: Int
    private let maximumSessions: Int
    private var pending: [String: Pending] = [:]
    private var completed: Set<String> = []
    private var voltageSamples = 0
    private var latestTimestamp: Double?

    var hasPendingSession: Bool { !pending.isEmpty }

    init(limits: SensorKitECGProcessingLimits = .init()) {
        self.maximumVoltageSamples = limits.maximumEntries
        self.maximumSessions = limits.maximumSessions
    }

    /// Adds the groups of one native callback at its native `timestamp`.
    ///
    /// - Throws: ``SensorKitECGSession/ProcessingError/assemblyCapacityExceeded`` when the retained sessions or entries
    ///   exceed the limits; the fetch fails and keeps its cursor, so a retry with larger limits can assemble them.
    mutating func append(_ groups: [SensorKitECGSession.InputGroup], at timestamp: Double) throws -> Output {
        latestTimestamp = max(latestTimestamp ?? timestamp, timestamp)
        var output = Output()
        var skipped: Set<String> = []
        for group in groups {
            guard !completed.contains(group.identifier), !group.identifier.isEmpty, group.identifier.utf8.count <= 4096 else {
                skipped.insert(group.identifier)
                continue
            }
            guard pending[group.identifier] != nil || pending.count + completed.count < maximumSessions else {
                throw SensorKitECGSession.ProcessingError.assemblyCapacityExceeded
            }
            let added = max(1, group.readings.reduce(0) { $0 + max(1, $1.samples.count) })
            guard added <= maximumVoltageSamples - voltageSamples else { throw SensorKitECGSession.ProcessingError.assemblyCapacityExceeded }
            voltageSamples += added
            pending[group.identifier, default: Pending(firstTimestamp: timestamp, lastTimestamp: timestamp)].groups.append(group)
            pending[group.identifier]?.lastTimestamp = timestamp
        }
        for identifier in pending.keys.sorted() {
            guard let entry = pending[identifier], entry.hasEveryState else {
                continue
            }
            if let merged = try? Self.merged(entry.groups, identifier: identifier),
               let sessions = try? SensorKitECGSession.process(merged) {
                output.sessions += sessions
            } else {
                skipped.insert(identifier)
            }
            pending.removeValue(forKey: identifier)
            completed.insert(identifier)
        }
        output.skippedSessionCount = skipped.count
        output.sessions.sort(by: SensorKitECGSession.precedes)
        return output
    }

    /// Ends the unfinished sessions when the fetch completes, so none of them fails the fetch.
    ///
    /// An unfinished session that later native data followed can never complete: it is assembled as a time-range fetch
    /// assembles it, so it is delivered without its end state, or skipped and counted without its begin state or
    /// voltage samples. An unfinished session the fetch saw no later data after may still complete, for example when
    /// the fetch ended inside it: it is not delivered, and ``Completion/heldFrom`` keeps the delivered boundary before
    /// it, so the next fetch reads it whole.
    mutating func finish() -> Completion {
        var completion = Completion()
        for (identifier, entry) in pending {
            if let latestTimestamp, entry.lastTimestamp < latestTimestamp {
                if let merged = try? Self.merged(entry.groups, identifier: identifier),
                   let session = SensorKitECGSession.processLeniently(merged).first {
                    completion.sessions.append(session)
                } else {
                    completion.skippedSessionCount += 1
                }
                completed.insert(identifier)
            } else {
                completion.heldFrom = min(completion.heldFrom ?? entry.firstTimestamp, entry.firstTimestamp)
            }
        }
        pending.removeAll()
        completion.sessions.sort(by: SensorKitECGSession.precedes)
        return completion
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
