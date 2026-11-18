//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The typed fields of one Google Health API data point that the guide admits.
///
/// Preserve the provider's data point identifier, or supply a previously persisted import key where the API exposes no
/// durable native identifier. Timestamps keep their exact source spelling and precision.
public struct GoogleHealthDataPoint: Sendable {
    /// The measured value of a data point, with its source time.
    public enum Value: Sendable {
        /// A step count over an interval.
        case steps(count: Int, interval: ProviderInterval)
        /// A distance in millimeters over an interval.
        case distance(millimeters: Decimal, interval: ProviderInterval)
        /// Active energy in kilocalories over an interval.
        case activeEnergy(kilocalories: Decimal, interval: ProviderInterval)
        /// A body weight in grams.
        case weight(grams: Decimal, timestamp: ProviderTimestamp)
        /// A body fat percentage.
        case bodyFat(percentage: Decimal, timestamp: ProviderTimestamp)
        /// A body height in millimeters.
        case height(millimeters: Decimal, timestamp: ProviderTimestamp)
        /// A VO2 max in milliliters per kilogram per minute.
        case vo2Max(value: Decimal, timestamp: ProviderTimestamp)
        /// A daily average oxygen saturation percentage.
        case dailyOxygenSaturation(averagePercentage: Decimal, day: ProviderCivilDay)
        /// Heart rate variability as RMSSD, SDNN or both, in milliseconds.
        case heartRateVariability(timestamp: ProviderTimestamp, rmssdMilliseconds: Decimal?, sdnnMilliseconds: Decimal?)
        /// A daily resting heart rate in beats per minute.
        case dailyRestingHeartRate(beatsPerMinute: Decimal, day: ProviderCivilDay)
        /// A daily respiratory rate in breaths per minute.
        case dailyRespiratoryRate(breathsPerMinute: Decimal, day: ProviderCivilDay)
        /// A blood glucose concentration in milligrams per deciliter.
        case bloodGlucose(milligramsPerDeciliter: Decimal, timestamp: ProviderTimestamp)
        /// A core body temperature in degrees Celsius.
        case coreBodyTemperature(celsius: Decimal, timestamp: ProviderTimestamp)
        /// A count of floors climbed over an interval.
        case floors(count: Int, interval: ProviderInterval)
        /// Basal energy in kilocalories over an interval.
        case basalEnergy(kilocalories: Decimal, interval: ProviderInterval)
        /// A sleep session and its stage durations.
        case sleep(interval: ProviderInterval, summary: SleepSummary)
        /// An exercise session and its activity, if the source evidences one.
        case exercise(interval: ProviderInterval, activity: ProviderWorkoutActivity? = nil)
    }

    /// The stage durations of a sleep session, in minutes. An absent duration is not zero.
    public struct SleepSummary: Sendable {
        /// The time asleep.
        public var minutesAsleep: Int?
        /// The time in deep sleep.
        public var deepMinutes: Int?
        /// The time in REM sleep.
        public var remMinutes: Int?
        /// The time in light sleep.
        public var lightMinutes: Int?
        /// The time awake.
        public var awakeMinutes: Int?

        /// Creates a summary without durations.
        public init() {}
    }

    /// The data point's identifier, or a persisted import key.
    public let id: String
    /// The data point's value.
    public let value: Value

    /// Creates a data point.
    public init(id: String, value: Value) {
        self.id = id
        self.value = value
    }
}
