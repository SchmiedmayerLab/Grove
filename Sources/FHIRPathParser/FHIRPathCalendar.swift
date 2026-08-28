//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Calendar policy used by FHIRPath temporal operations.
///
/// FHIR dates use the proleptic Gregorian calendar. Evaluation must not vary with the
/// device's preferred calendar, locale, or current time zone, so every operation starts
/// from this fixed calendar and applies only an explicit source/evaluation zone.
enum FHIRPathCalendar {
    static let utc: TimeZone = {
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("Foundation must provide a zero-offset time zone.")
        }
        return timeZone
    }()

    static func gregorian(timeZone: TimeZone = utc) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}
