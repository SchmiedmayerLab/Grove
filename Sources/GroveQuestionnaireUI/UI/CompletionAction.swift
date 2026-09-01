//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// How the ``QuestionnaireSheet``'s final button describes what it does.
///
/// The wording turns on what happens to the responses, not on how the questionnaire is built:
/// if they are handed off and the participant cannot casually reopen and edit them, they are
/// being submitted; if the participant is editing their own record in place, they are done.
public enum CompletionAction: Sendable {
    /// The responses leave the participant's hands; the button reads "Submit".
    case submit
    /// The participant is editing a record they can reopen; the button reads "Done".
    case done
}
