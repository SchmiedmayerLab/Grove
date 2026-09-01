//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Whether the questionnaire numbers its questions.
@available(
    *,
    deprecated,
    message: "Pass a QuestionnaireProgress to the sheet instead: .enable is .questionNumbers, .disable keeps the bar off, no argument shows it."
)
public enum QuestionProgressConfig: Sendable {
    /// No progress is shown.
    case disable
    /// A "Question X of Y" indicator is shown above every question.
    case enable

    var progress: QuestionnaireProgress {
        switch self {
        case .disable: []
        case .enable: .questionNumbers
        }
    }
}
