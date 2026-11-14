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
    case activity(id: String, day: ProviderCivilDay, values: Activity)
    case sleep(id: String, interval: DateInterval, values: Sleep)
    case workout(id: String, interval: DateInterval, activity: ProviderWorkoutActivity? = nil)

    public struct Activity: Sendable {
        public var steps: Int?
        public var distance: Decimal?
        public var calories: Decimal?

        public init() {}
    }

    public struct Sleep: Sendable {
        public var deepSleepDuration: Int?
        public var remSleepDuration: Int?
        public var lightSleepDuration: Int?
        public var wakeupDuration: Int?
        public var averageHeartRate: Decimal?
        public var averageRespiratoryRate: Decimal?

        public init() {}
    }
}
