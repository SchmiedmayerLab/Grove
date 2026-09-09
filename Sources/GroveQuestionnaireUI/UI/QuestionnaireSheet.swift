//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import GroveViews
public import SwiftUI


/// Presents a `Questionnaire` for answering.
///
/// Unless externally provided, the sheet implicitly creates and owns a `QuestionnaireResponses` instance,
/// which, upon successful completion of the questionnaire, will be made available via the result handler.
///
/// The `QuestionnaireSheet` uses an internal `NavigationStack` to display the questionnaire's content;
/// each section in the input questionnaire is displayed as one page on the stack.
///
/// - Note: The presenting parent view is responsible for dismissing the `QuestionnaireSheet` after the result handler has completed.
///
/// The following example shows how to present a questionnaire:
/// ```swift
/// struct AnswerQuestionnaire: View {
///     @State var activeQuestionnaire: Questionnaire?
///
///     var body: some View {
///         Button("Answer GAD-7") {
///             activeQuestionnaire = .gad7
///         }
///         .sheet(item: $activeQuestionnaire) { questionnaire in
///             QuestionnaireSheet(questionnaire) { result in
///                 switch result {
///                 case .completed(let responses):
///                     // ... save the response to your data store
///                     activeQuestionnaire = nil
///                 case .cancelled:
///                     break
///                 }
///             }
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct QuestionnaireSheet: View {
    private let questionnaire: Questionnaire
    /// The page the questionnaire opens on: a section whose questions are all hidden or disabled
    /// has nothing to show, and a page showing nothing is never the right first impression.
    ///
    /// Settled once, when the sheet is created, so that answering a question can never swap the
    /// page the navigation stack is rooted at out from under the participant.
    private let firstSection: Questionnaire.Section?
    private let completionStepConfig: CompletionStepConfig
    private let questionProgressConfig: QuestionProgressConfig
    private let completionAction: CompletionAction
    private let resultHandler: @MainActor (Result) async throws -> Void

    @State private var responses: QuestionnaireResponses

    @_documentation(visibility: internal)
    public var body: some View {
        ManagedNavigationStack {
            if let section = firstSection {
                QuestionnaireSectionView(
                    questionnaire: questionnaire,
                    section: section,
                    completionStepConfig: completionStepConfig,
                    questionProgressConfig: questionProgressConfig,
                    completionAction: completionAction
                ) { result in
                    responses.purgeResponsesToDisabledTasks()
                    try await resultHandler(result)
                }
            } else {
                ContentUnavailableView(
                    LocalizedStringResource("Questionnaire is Empty", bundle: .module),
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .accessibilityIdentifier("GroveQuestionnaireNavStack")
        // The sheet knows the shape its content wants; asking every app to say so again only
        // gives them a way to get it wrong.
        .presentationSizing(.page)
        .environment(responses)
    }

    /// Creates a new `QuestionnaireSheet`
    ///
    /// - parameter questionnaire: The `Questionnaire` that should be answered.
    /// - parameter responses: The `QuestionnaireResponses` that should be used when answering the questionnaire.
    ///     If set to `nil`, a new, empty object will implicitly be created and used.
    ///     Use this parameter to display or edit existing, previously-collected responses.
    /// - parameter completionStepConfig: Whether the questionnaire sheet should present a completion page once the user has finished the questionnaire.
    ///     Most questionnaires do not need one, so there is none unless asked for.
    /// - parameter questionProgressConfig: Whether the sheet tells the participant how far along they are.
    /// - parameter completionAction: How the final button describes itself. Responses that are handed off to the app are submitted;
    ///     use ``CompletionAction/done`` only if the participant is editing a record they can reopen.
    /// - parameter resultHandler: A closure that is invoked when the questionnaire is completed, or cancelled by the user.
    ///     The sheet dismisses itself once this closure has returned. It may take as long as it needs — the sheet shows that it is
    ///     working and refuses further input meanwhile — and an error it throws is reported to the participant, who stays in the
    ///     questionnaire with their answers so they can try again.
    public init(
        _ questionnaire: Questionnaire,
        responses: QuestionnaireResponses? = nil,
        completionStepConfig: CompletionStepConfig = .disable,
        questionProgressConfig: QuestionProgressConfig = .disable,
        completionAction: CompletionAction = .submit,
        resultHandler: @escaping @MainActor (Result) async throws -> Void
    ) {
        let simplified = questionnaire.withConditionsSimplified()
        let responses = responses ?? QuestionnaireResponses(questionnaire: questionnaire)
        self.questionnaire = simplified
        self.firstSection = simplified.sections.first { responses.rendersContent(in: $0) }
        self.completionStepConfig = completionStepConfig
        self.questionProgressConfig = questionProgressConfig
        self.completionAction = completionAction
        self.responses = responses
        self.resultHandler = resultHandler
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireSheet {
    /// The result of answering a questionnaire.
    public enum Result {
        /// The user successfully filled out the whole questionnaire.
        case completed(QuestionnaireResponses)
        /// The user cancelled the questionnaire.
        case cancelled
    }
}
