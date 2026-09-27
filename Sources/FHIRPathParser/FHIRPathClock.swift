//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The instant and time zone that `now()`, `today()` and `timeOfDay()` read.
///
/// Evaluation never reads the device clock, zone or calendar: the caller states both here, so the same
/// expression over the same clock yields the same value on every device.
public struct FHIRPathClock: Hashable, Sendable {
    /// The instant `now()` denotes.
    public var instant: Date
    /// The zone `today()` and `timeOfDay()` are read in and `now()` states its offset in.
    public var timeZone: TimeZone

    public init(instant: Date, timeZone: TimeZone) {
        self.instant = instant
        self.timeZone = timeZone
    }
}


extension FHIRPathClock {
    /// The proleptic Gregorian calendar in the clock's zone.
    var calendar: Calendar {
        FHIRPathCalendar.gregorian(timeZone: timeZone)
    }
}
