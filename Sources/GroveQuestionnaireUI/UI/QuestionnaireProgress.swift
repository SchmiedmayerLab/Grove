//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// How a ``QuestionnaireSheet`` tells the participant how far along they are.
///
/// Pass any combination; the sheet shows the bar unless asked otherwise, and an empty set shows nothing.
///
/// ```swift
/// QuestionnaireSheet(questionnaire, progress: [.bar, .questionNumbers]) { result in ... }
/// ```
public struct QuestionnaireProgress: OptionSet, Sendable {
    /// A bar under the navigation bar that fills as the pages pass.
    ///
    /// It counts answers and page turns, and keeps moving forward while the participant answers: a question a
    /// condition may still ask is counted until an answer settles it.
    public static let bar = Self(rawValue: 1 << 0)
    /// "Question X of Y" above every question, counted over the questions being asked.
    public static let questionNumbers = Self(rawValue: 1 << 1)

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
