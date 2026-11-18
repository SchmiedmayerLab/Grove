//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension GoogleHealthDataPoint.Value {
    var effective: ProviderObservation.Effective {
        switch self {
        case .weight(_, let timestamp), .bodyFat(_, let timestamp), .height(_, let timestamp),
             .vo2Max(_, let timestamp), .bloodGlucose(_, let timestamp), .coreBodyTemperature(_, let timestamp),
             .heartRateVariability(let timestamp, _, _):
            .timestamp(timestamp)
        case .steps(_, let interval), .distance(_, let interval), .activeEnergy(_, let interval),
             .floors(_, let interval), .basalEnergy(_, let interval), .sleep(let interval, _), .exercise(let interval, _):
            .providerInterval(interval)
        case .dailyOxygenSaturation(_, let day), .dailyRestingHeartRate(_, let day), .dailyRespiratoryRate(_, let day):
            .interval(day.interval.start, day.interval.end)
        }
    }
}


extension ProviderObservation.Effective {
    /// Whether a duration of `minutes` fits within this interval, without losing the source's fractional precision.
    func contains(minutes: Int) -> Bool {
        switch self {
        case let .interval(start, end):
            Double(minutes) <= end.timeIntervalSince(start) / 60
        case .providerInterval(let interval):
            Decimal(minutes) * 60 <= interval.duration
        case .instant, .timestamp:
            false
        }
    }
}
