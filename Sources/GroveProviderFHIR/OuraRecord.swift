//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The typed fields of one Oura document. An absent field is not a zero measurement.
public enum OuraRecord: Sendable {
    /// A daily activity document.
    case dailyActivity(OuraActivityRecord)
    /// A sleep document.
    case sleep(OuraSleepRecord)
    /// A daily oxygen saturation document and its average percentage.
    case dailyOxygenSaturation(id: String, day: ProviderCivilDay, average: Decimal?)
    /// A workout and its activity, if the source evidences one.
    case workout(id: String, interval: ProviderInterval, activity: ProviderWorkoutActivity? = nil)
    /// A VO2 max document and its value.
    case vo2Max(id: String, timestamp: ProviderTimestamp, value: Decimal?)
    /// A daily cardiovascular age document and its age in years.
    case cardiovascularAge(id: String, day: ProviderCivilDay, years: Int?)
    /// A daily readiness document and its score.
    case readiness(id: String, day: ProviderCivilDay, score: Int?)
}
