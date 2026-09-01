//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// The lines a ``QuestionnaireSheet`` adds to a question to say how it wants to be answered.
///
/// None is shown unless the sheet is asked:
///
/// ```swift
/// QuestionnaireSheet(questionnaire, hints: .all) { result in ... }
/// ```
public struct QuestionnaireHints: OptionSet, Sendable {
    /// "Select all that apply" under a question that takes several answers.
    public static let selectAllThatApply = Self(rawValue: 1 << 0)

    /// Every hint.
    public static let all: Self = [.selectAllThatApply]

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}


extension EnvironmentValues {
    @Entry var questionnaireHints: QuestionnaireHints = []
}
