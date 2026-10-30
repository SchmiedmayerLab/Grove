//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The calendar every FHIRPath temporal operation uses.
///
/// FHIR dates are proleptic Gregorian, so evaluation must not follow the device's calendar, locale or zone:
/// every operation starts from this calendar and applies only a zone the source or the caller states.
enum FHIRPathCalendar {
    static let utc: TimeZone = {
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("Foundation must provide a zero-offset time zone.")
        }
        return timeZone
    }()

    static func gregorian(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}
