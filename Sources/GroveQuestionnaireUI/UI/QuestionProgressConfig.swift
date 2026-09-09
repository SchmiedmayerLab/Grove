//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Controls whether the ``QuestionnaireSheet`` tells the participant how far along they are.
///
/// The count is an estimate: conditions add and remove questions as answers change, so both
/// the position and the total move while the questionnaire is being answered. Instruments
/// short enough to take in at a glance read better without it, which is why it is off unless
/// asked for.
public enum QuestionProgressConfig: Sendable {
    /// No progress is shown.
    case disable
    /// A "Question X of Y" indicator is shown above the primary action.
    case enable
}
