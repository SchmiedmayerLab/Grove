//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// One Withings summary. Supply a previously persisted import key when the API exposes no stable native identifier.
public enum WithingsSummary: Sendable {
    /// A daily activity summary.
    case activity(id: String, day: ProviderCivilDay, values: Activity)
    /// A sleep summary over its session.
    case sleep(id: String, interval: DateInterval, values: Sleep)
    /// A workout and its activity, if the source evidences one.
    case workout(id: String, interval: DateInterval, activity: ProviderWorkoutActivity? = nil)

    /// The fields of a daily activity summary. An absent field is not zero.
    public struct Activity: Sendable {
        /// The step count.
        public var steps: Int?
        /// The distance, in meters.
        public var distance: Decimal?
        /// The active energy, in kilocalories.
        public var calories: Decimal?

        /// Creates a summary without fields.
        public init() {}
    }

    /// The fields of a sleep summary. An absent field is not zero.
    public struct Sleep: Sendable {
        /// The deep sleep duration, in seconds.
        public var deepSleepDuration: Int?
        /// The REM sleep duration, in seconds.
        public var remSleepDuration: Int?
        /// The light sleep duration, in seconds.
        public var lightSleepDuration: Int?
        /// The time awake, in seconds.
        public var wakeupDuration: Int?
        /// The average heart rate, in beats per minute.
        public var averageHeartRate: Decimal?
        /// The average respiratory rate, in breaths per minute.
        public var averageRespiratoryRate: Decimal?

        /// Creates a summary without fields.
        public init() {}
    }
}
