//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Typed fields from one Oura document. An absent field is not a zero measurement.
public enum OuraRecord: Sendable {
    case dailyActivity(OuraActivityRecord)
    case sleep(OuraSleepRecord)
    case dailyOxygenSaturation(id: String, day: ProviderCivilDay, average: Decimal?)
    case workout(id: String, start: Date, end: Date, activity: ProviderWorkoutActivity? = nil)
    case vo2Max(id: String, timestamp: Date, value: Decimal?)
    case exactVO2Max(id: String, timestamp: ProviderTimestamp, value: Decimal?)
    case exactWorkout(id: String, interval: ProviderInterval, activity: ProviderWorkoutActivity? = nil)
    case cardiovascularAge(id: String, day: ProviderCivilDay, years: Int?)
    case readiness(id: String, day: ProviderCivilDay, score: Int?)
}
