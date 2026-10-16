//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The instant and zone a questionnaire's time functions, such as `today()` and `now()`, read.
///
/// Expressions never read the device's clock, zone or calendar on their own. While a participant answers, the
/// clock is ``live(in:)``: the wall clock, read once per state of the answers, so a page asked twice about the same
/// answers hears the same thing. A stored response is evaluated at the instant and offset it was authored in.
public struct QuestionnaireClock: Sendable {
    /// The zone `today()` and `timeOfDay()` are read in.
    package let timeZone: TimeZone
    private let read: @Sendable () -> Date

    /// A clock that reads its instant from `read`, for tests that need to see time move.
    package init(timeZone: TimeZone, reading read: @escaping @Sendable () -> Date) {
        self.timeZone = timeZone
        self.read = read
    }

    /// The wall clock in the participant's zone.
    public static func live(in timeZone: TimeZone) -> Self {
        Self(timeZone: timeZone) {
            Date()
        }
    }

    /// One instant for every evaluation.
    public static func fixed(at instant: Date, in timeZone: TimeZone) -> Self {
        Self(timeZone: timeZone) {
            instant
        }
    }

    /// The instant an evaluation starting now reads.
    package func instant() -> Date {
        read()
    }
}
