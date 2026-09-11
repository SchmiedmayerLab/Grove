//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import GroveViews
public import SwiftUI


/// Presents a ``Questionnaire`` for answering.
///
/// ![A questionnaire page with one question per card and a continue button.](Overview)
///
/// Unless externally provided, the sheet implicitly creates and owns a ``QuestionnaireResponses`` instance,
/// which, upon successful completion of the questionnaire, will be made available via the result handler.
///
/// The `QuestionnaireSheet` uses an internal `NavigationStack` to display the questionnaire's content;
/// each section in the input questionnaire is displayed as one page on the stack. A page's action floats
/// over the foot of its questions, and the navigation bar names the page: inline, with the progress bar hanging
/// off it, or rising into the bar as the page scrolls when there is none.
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
    private let progress: QuestionnaireProgress
    private let progressRange: ClosedRange<Double>
    private let hints: QuestionnaireHints
    private let completionAction: CompletionAction
    private let resultHandler: @MainActor (Result) async throws -> Void

    @State private var responses: QuestionnaireResponses
    @State private var progressState = QuestionnaireProgressState()

    @_documentation(visibility: internal)
    public var body: some View {
        ManagedNavigationStack {
            if let section = firstSection {
                QuestionnaireSectionView(
                    questionnaire: questionnaire,
                    section: section,
                    completionStepConfig: completionStepConfig,
                    progress: progress,
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
        // The bar is the sheet's, not a page's: pages come and go beneath it while it eases to the next value.
        .overlay(alignment: .top) {
            ZStack {
                // Not before the page has said where its content starts: the line would sit on the top edge for a frame.
                if let fraction = progressState.fraction, progressState.contentTop > 0 {
                    QuestionnaireProgressBar(fraction: progressRange.lowerBound + fraction * (progressRange.upperBound - progressRange.lowerBound))
                        .padding(.top, progressState.contentTop)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: progressState.fraction == nil)
            // From the stack's own top edge: the page measures its inset from there, status bar included when the
            // sheet covers the whole screen.
            .ignoresSafeArea(edges: .top)
        }
        .environment(progressState)
        .environment(\.questionnaireHints, hints)
        // The sheet knows the shape its content wants; asking every app to say so again only
        // gives them a way to get it wrong.
        .presentationSizing(.page)
        .environment(responses)
    }

    /// Creates a new `QuestionnaireSheet`
    ///
    /// - parameter questionnaire: The ``Questionnaire`` that should be answered.
    /// - parameter responses: The ``QuestionnaireResponses`` that should be used when answering the questionnaire.
    ///     If set to `nil`, a new, empty object will implicitly be created and used.
    ///     Use this parameter to display or edit existing, previously-collected responses.
    /// - parameter completionStepConfig: Whether the questionnaire sheet should present a completion page once the user has finished the questionnaire.
    ///     Most questionnaires do not need one, so there is none unless asked for.
    /// - parameter progress: How the sheet tells the participant how far along they are; the bar, unless asked otherwise.
    /// - parameter progressRange: The part of the bar this questionnaire fills, from where it starts to where it ends. The whole
    ///     bar, unless the questionnaire is one step of a longer flow: a questionnaire that is the second of four steps would
    ///     pass `0.25...0.5`, so the bar picks up where the flow left off and hands over where the next step begins.
    ///     Bounds outside `0...1` are clamped.
    /// - parameter hints: The lines added to a question to say how it wants to be answered; none, unless asked for.
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
        progress: QuestionnaireProgress = .bar,
        progressRange: ClosedRange<Double> = 0...1,
        hints: QuestionnaireHints = [],
        completionAction: CompletionAction = .submit,
        resultHandler: @escaping @MainActor (Result) async throws -> Void
    ) {
        let simplified = questionnaire.withConditionsSimplified()
        let responses = responses ?? QuestionnaireResponses(questionnaire: questionnaire)
        self.questionnaire = simplified
        self.firstSection = simplified.sections.first { responses.rendersContent(in: $0) }
        self.completionStepConfig = completionStepConfig
        self.progress = progress
        self.progressRange = progressRange
        self.hints = hints
        self.completionAction = completionAction
        self.responses = responses
        self.resultHandler = resultHandler
    }

    // swiftlint:disable function_default_parameter_at_end
    @available(*, deprecated, message: "Pass a QuestionnaireProgress as progress instead.")
    public init(
        _ questionnaire: Questionnaire,
        responses: QuestionnaireResponses? = nil,
        completionStepConfig: CompletionStepConfig = .disable,
        questionProgressConfig: QuestionProgressConfig,
        completionAction: CompletionAction = .submit,
        resultHandler: @escaping @MainActor (Result) async throws -> Void
    ) {
        self.init(
            questionnaire,
            responses: responses,
            completionStepConfig: completionStepConfig,
            progress: questionProgressConfig.progress,
            completionAction: completionAction,
            resultHandler: resultHandler
        )
    }
    // swiftlint:enable function_default_parameter_at_end
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
