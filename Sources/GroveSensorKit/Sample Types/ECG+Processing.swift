//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SensorKit


@available(iOS 17.4, *)
extension SensorKitECGSession {
    struct InputReading: Hashable, Sendable {
        let date: Date
        let frequency: Measurement<UnitFrequency>
        let lead: SRElectrocardiogramSample.Lead
        let samples: [Batch.VoltageSample]
    }

    struct InputGroup: Sendable {
        let identifier: String
        let state: SRElectrocardiogramSession.State
        let guidance: SRElectrocardiogramSession.SessionGuidance
        let readings: [InputReading]
    }

    static func process(_ groups: [InputGroup]) throws -> [Self] {
        let sessions = try Dictionary(grouping: groups, by: \.identifier).map { identifier, groups in
            guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProcessingError.inconsistentSession }
            let beginnings = groups.filter { $0.state == .begin }
            let active = groups.filter { $0.state == .active }
            let endings = groups.filter { $0.state == .end }
            guard !beginnings.isEmpty, !active.isEmpty, !endings.isEmpty else { throw ProcessingError.incompleteSession }
            guard beginnings.count == 1, active.count == 1, endings.count == 1 else { throw ProcessingError.inconsistentSession }
            let readings = active[0].readings.sorted { $0.date < $1.date }
            guard let first = readings.first, !first.samples.isEmpty,
                  let start = beginnings[0].readings.map(\.date).min() else { throw ProcessingError.incompleteSession }
            guard groups.filter({ $0.state != .active }).allSatisfy({ $0.readings.allSatisfy { $0.samples.isEmpty } }),
                  readings.allSatisfy({ $0.frequency == first.frequency && $0.lead == first.lead && !$0.samples.isEmpty }) else {
                throw ProcessingError.inconsistentSession
            }
            let hertz = first.frequency.converted(to: .hertz).value
            guard start.timeIntervalSince1970.isFinite, hertz.isFinite, hertz > 0,
                  readings.allSatisfy({ $0.date.timeIntervalSince1970.isFinite && $0.date >= start }),
                  Set(readings.map(\.date)).count == readings.count else { throw ProcessingError.invalidTiming }
            return Self(
                startDate: start,
                sessionIdentifier: identifier,
                sessionStates: groups.map(\.state),
                frequency: first.frequency,
                lead: first.lead,
                guidance: active[0].guidance,
                batches: readings.map { Batch(offset: $0.date.timeIntervalSince(start), samples: $0.samples) }
            )
        }
        return sessions.sorted { ($0.startDate, $0.sessionIdentifier) < ($1.startDate, $1.sessionIdentifier) }
    }
}
