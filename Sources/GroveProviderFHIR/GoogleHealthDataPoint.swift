//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Typed consumed fields of one Google Health API data point. Preserve the provider data-point identifier,
/// or supply a previously persisted import key when the API exposes no durable native identifier.
public struct GoogleHealthDataPoint: Sendable {
    public enum Value: Sendable {
        case steps(count: Int, interval: DateInterval)
        case distance(millimeters: Decimal, interval: DateInterval)
        case activeEnergy(kilocalories: Decimal, interval: DateInterval)
        case weight(grams: Decimal, timestamp: Date)
        case bodyFat(percentage: Decimal, timestamp: Date)
        case height(millimeters: Decimal, timestamp: Date)
        case vo2Max(value: Decimal, timestamp: Date)
        case dailyOxygenSaturation(averagePercentage: Decimal, day: ProviderCivilDay)
        case heartRateVariability(timestamp: Date, rmssdMilliseconds: Decimal?, sdnnMilliseconds: Decimal?)
        case dailyRestingHeartRate(beatsPerMinute: Decimal, day: ProviderCivilDay)
        case dailyRespiratoryRate(breathsPerMinute: Decimal, day: ProviderCivilDay)
        case bloodGlucose(milligramsPerDeciliter: Decimal, timestamp: Date)
        case coreBodyTemperature(celsius: Decimal, timestamp: Date)
        case floors(count: Int, interval: DateInterval)
        case basalEnergy(kilocalories: Decimal, interval: DateInterval)
        case sleep(interval: DateInterval, summary: SleepSummary)
        case exercise(interval: DateInterval, activity: ProviderWorkoutActivity? = nil)

        /// Exact-source alternatives preserve fractional timestamp precision.
        case exactSteps(count: Int, interval: ProviderInterval)
        case exactDistance(millimeters: Decimal, interval: ProviderInterval)
        case exactActiveEnergy(kilocalories: Decimal, interval: ProviderInterval)
        case exactWeight(grams: Decimal, timestamp: ProviderTimestamp)
        case exactBodyFat(percentage: Decimal, timestamp: ProviderTimestamp)
        case exactHeight(millimeters: Decimal, timestamp: ProviderTimestamp)
        case exactVo2Max(value: Decimal, timestamp: ProviderTimestamp)
        case exactHeartRateVariability(timestamp: ProviderTimestamp, rmssdMilliseconds: Decimal?, sdnnMilliseconds: Decimal?)
        case exactBloodGlucose(milligramsPerDeciliter: Decimal, timestamp: ProviderTimestamp)
        case exactCoreBodyTemperature(celsius: Decimal, timestamp: ProviderTimestamp)
        case exactFloors(count: Int, interval: ProviderInterval)
        case exactBasalEnergy(kilocalories: Decimal, interval: ProviderInterval)
        case exactSleep(interval: ProviderInterval, summary: SleepSummary)
        case exactExercise(interval: ProviderInterval, activity: ProviderWorkoutActivity? = nil)
    }

    public struct SleepSummary: Sendable {
        public var minutesAsleep: Int?
        public var deepMinutes: Int?
        public var remMinutes: Int?
        public var lightMinutes: Int?
        public var awakeMinutes: Int?

        public init() {}
    }

    public let id: String
    public let value: Value

    public init(id: String, value: Value) {
        self.id = id
        self.value = value
    }
}
