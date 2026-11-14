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
            return .instant(timestamp)
        case .exactWeight(_, let timestamp), .exactBodyFat(_, let timestamp), .exactHeight(_, let timestamp),
             .exactVo2Max(_, let timestamp), .exactBloodGlucose(_, let timestamp), .exactCoreBodyTemperature(_, let timestamp),
             .exactHeartRateVariability(let timestamp, _, _):
            return .exactInstant(timestamp)
        case .steps(_, let interval), .distance(_, let interval), .activeEnergy(_, let interval),
             .floors(_, let interval), .basalEnergy(_, let interval), .sleep(let interval, _), .exercise(let interval, _):
            return .interval(interval.start, interval.end)
        case .exactSteps(_, let interval), .exactDistance(_, let interval), .exactActiveEnergy(_, let interval),
             .exactFloors(_, let interval), .exactBasalEnergy(_, let interval), .exactSleep(let interval, _), .exactExercise(let interval, _):
            return .exactInterval(interval)
        case .dailyOxygenSaturation(_, let day), .dailyRestingHeartRate(_, let day), .dailyRespiratoryRate(_, let day):
            return .interval(day.interval.start, day.interval.end)
        }
    }
}


extension ProviderObservation.Effective {
    /// Sleep components must fit the source interval without losing fractional source precision.
    func contains(minutes: Int) -> Bool {
        switch self {
        case let .interval(start, end):
            return Double(minutes) <= end.timeIntervalSince(start) / 60
        case .exactInterval(let interval):
            return Decimal(minutes) * 60 <= interval.duration
        case .instant, .exactInstant:
            return false
        }
    }
}
