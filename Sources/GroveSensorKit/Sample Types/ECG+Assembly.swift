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
/// assembled (inconsistent facts, invalid timing, no voltage samples), a fragment of a session that already finished
/// and is not forgotten, and a fragment of a session that is not pending and whose begin state isn't in the
/// same callback, is skipped and counted instead of failing the fetch. That last fragment can't become a session,
/// since every session needs its begin state.
///
/// The sessions of one device are expected not to overlap in time, so an unfinished session ends when a callback
/// carries data of another session and none of its own: ``finishPending(supersededBy:)`` then assembles it as a
/// time-range fetch does. That decision depends only on the order of the callbacks. The caller decides what happens
/// to the sessions still unfinished when a fetch ends. A session is delivered once as long as its begin state doesn't
/// repeat: after the caller starts a new assembly, a repeated begin state starts the session anew.
///
/// The native timestamps are those of the fetch results.
@available(iOS 17.4, *)
struct SensorKitECGAssembly {
    /// The sessions one step finished, and how many sessions or late fragments it skipped.
    struct Output {
        var sessions: [SensorKitECGSession] = []
        var skippedSessionCount = 0
        /// Whether the callback carried data of an unfinished session or started one.
        var addedData = false
    }

    private struct Pending {
        var groups: [SensorKitECGSession.InputGroup] = []
        let firstTimestamp: Double
        var lastTimestamp: Double
        var entryCount = 0

        var hasEveryState: Bool {
            [.begin, .active, .end].allSatisfy { state in groups.contains { $0.state == state } }
        }

        mutating func append(_ group: SensorKitECGSession.InputGroup, at timestamp: Double) {
            groups.append(group)
            lastTimestamp = timestamp
            entryCount += SensorKitECGAssembly.entryCount(of: group)
        }
    }

    /// How long before the end of the data a fetch can read an unfinished session still waits for its remaining
    /// callbacks, in seconds.
    static let holdInterval: Double = 3600

    private let maximumEntries: Int
    private let maximumSessions: Int
    private var pending: [String: Pending] = [:]
    /// The sessions delivered or skipped so far.
    private var finished: Set<String> = []
    /// The entries of the unfinished and the delivered sessions.
    private var entryCount = 0

    /// The native timestamps of the earliest first callback and of the latest callback of the unfinished sessions.
    var pendingTimestamps: (earliest: Double, latest: Double)? {
        guard let earliest = pending.values.lazy.map(\.firstTimestamp).min(),
              let latest = pending.values.lazy.map(\.lastTimestamp).max() else {
            return nil
        }
        return (earliest, latest)
    }

    init(limits: SensorKitECGProcessingLimits = .init()) {
        self.maximumEntries = limits.maximumEntries
        self.maximumSessions = limits.maximumSessions
    }

    /// Adds the groups of one native callback at its native `timestamp`.
    ///
    /// - Throws: ``SensorKitECGSession/ProcessingError/assemblyCapacityExceeded`` when the callback doesn't fit the
    ///   limits together with the sessions retained so far. Nothing is added then, so the caller can make room and add
    ///   the callback again.
    mutating func append(_ groups: [SensorKitECGSession.InputGroup], at timestamp: Double) throws -> Output {
        var output = Output()
        var skipped: Set<String> = []
        var accepted: [SensorKitECGSession.InputGroup] = []
        for group in groups {
            if accepts(group, in: groups) {
                accepted.append(group)
            } else {
                skipped.insert(group.identifier)
            }
        }
        let newSessionCount = Set(accepted.lazy.map(\.identifier)).subtracting(pending.keys).count
        let addedEntryCount = accepted.reduce(0) { $0 + Self.entryCount(of: $1) }
        guard newSessionCount <= maximumSessions - pending.count - finished.count, addedEntryCount <= maximumEntries - entryCount else {
            throw SensorKitECGSession.ProcessingError.assemblyCapacityExceeded
        }
        entryCount += addedEntryCount
        output.addedData = !accepted.isEmpty
        for group in accepted {
            pending[group.identifier, default: Pending(firstTimestamp: timestamp, lastTimestamp: timestamp)].append(group, at: timestamp)
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
                entryCount -= entry.entryCount
            }
            pending.removeValue(forKey: identifier)
            finished.insert(identifier)
        }
        output.skippedSessionCount = skipped.count
        output.sessions.sort(by: SensorKitECGSession.precedes)
        return output
    }

    /// Ends the unfinished sessions that a callback with `groups` carries no data of, when it carries data of another
    /// session. Call it before ``append(_:at:)`` adds that callback.
    mutating func finishPending(supersededBy groups: [SensorKitECGSession.InputGroup]) -> Output {
        let current = Set(groups.filter { accepts($0, in: groups) }.map(\.identifier))
        return current.isEmpty ? Output() : finishPending(except: current)
    }

    /// Ends the unfinished sessions, except those named: each is assembled as a time-range fetch assembles it, so it is
    /// delivered without its end state, or skipped and counted without its begin state or voltage samples.
    mutating func finishPending(except current: Set<String> = []) -> Output {
        var output = Output()
        for identifier in pending.keys.sorted() where !current.contains(identifier) {
            guard let entry = pending.removeValue(forKey: identifier) else {
                continue
            }
            finished.insert(identifier)
            if let merged = try? Self.merged(entry.groups, identifier: identifier),
               let session = SensorKitECGSession.processLeniently(merged).first {
                output.sessions.append(session)
            } else {
                output.skippedSessionCount += 1
                entryCount -= entry.entryCount
            }
        }
        output.sessions.sort(by: SensorKitECGSession.precedes)
        return output
    }

    /// Forgets the sessions finished so far, so they no longer count against the session limit.
    ///
    /// A later fragment of a forgotten session is skipped unless its callback carries the session's begin state.
    ///
    /// - Returns: Whether there was a finished session to forget.
    mutating func forgetFinishedSessions() -> Bool {
        defer {
            finished.removeAll(keepingCapacity: true)
        }
        return !finished.isEmpty
    }

    /// Whether `group` of a callback with `groups` belongs to an unfinished session or starts one.
    private func accepts(_ group: SensorKitECGSession.InputGroup, in groups: [SensorKitECGSession.InputGroup]) -> Bool {
        guard !finished.contains(group.identifier), !group.identifier.isEmpty, group.identifier.utf8.count <= 4096 else {
            return false
        }
        return pending[group.identifier] != nil || groups.contains { $0.identifier == group.identifier && $0.state == .begin }
    }
}


@available(iOS 17.4, *)
extension SensorKitECGAssembly {
    /// The entries a group counts against the limits: its voltage samples, one for each reading without any, and one for
    /// a group without readings.
    fileprivate static func entryCount(of group: SensorKitECGSession.InputGroup) -> Int {
        max(1, group.readings.reduce(0) { $0 + max(1, $1.samples.count) })
    }

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
