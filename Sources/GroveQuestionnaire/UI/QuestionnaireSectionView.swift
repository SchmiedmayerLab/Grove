//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Accessibility
private import GroveViews
import SwiftUI


/// Displays a section of tasks within a questionnaire, as a single page on the navigation stack.
@available(iOS 18, macOS 15, watchOS 11, *)
struct QuestionnaireSectionView<Header: View>: View {
    private enum Context {
        case regular(questionnaire: Questionnaire)
        case answerNestedQuestions(
            parentTask: Questionnaire.Task,
            selectedOptionTitle: String,
            sections: [Questionnaire.Section]
        )

        var allSections: [Questionnaire.Section] {
            switch self {
            case .regular(let questionnaire):
                questionnaire.sections
            case .answerNestedQuestions(parentTask: _, selectedOptionTitle: _, let sections):
                sections
            }
        }
    }

    @Environment(ManagedNavigationStack.Path.self) private var navigationPath
    @Environment(QuestionnaireResponses.self) private var responses
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let header: Header
    private let context: Context
    private let completionStepConfig: CompletionStepConfig
    private let questionProgressConfig: QuestionProgressConfig
    private let completionAction: CompletionAction
    private let section: Questionnaire.Section
    private let resultHandler: @MainActor (QuestionnaireSheet.Result) async throws -> Void

    @State private var indicateBlockingTasks = false
    @State private var viewState: ViewState = .idle
    @State private var failedAttempts = 0
    /// The question the page has been asked to bring back into view.
    @State private var taskToRevisit: Questionnaire.Task.ID?
    @AccessibilityFocusState private var focusedTask: Questionnaire.Task.ID?

    var body: some View {
        @Bindable var responses = responses
        let runs = TaskRun.runs(of: renderedTasks)
        let positions = questionPositions
        ScrollViewReader { scrollViewProxy in
            Form {
                header
                // One card per question: two questions sharing a card read as one.
                // FHIR questionnaire-hidden: hidden tasks carry values but are never rendered.
                ForEach(runs) { run in
                    let caption = TaskRun.Caption(
                        intro: run.id == runs.first?.id ? introText : nil,
                        groups: run.groupHeadings(otherThan: barTitle)
                    )
                    ForEach(run.tasks) { task in
                        cardSection(
                            for: task,
                            response: $responses.responses[task.id],
                            at: positions[task.id],
                            headedBy: task.id == run.tasks[0].id ? caption : nil
                        )
                    }
                }
                // disallow mutating responses while an action is being performed
                .disabled(viewState == .processing)

                actionSection
            }
            // Conditional and follow-up questions come and go as answers change; letting SwiftUI
            // animate the rows themselves keeps the arrival visible without any state of our own.
            .animation(reduceMotion ? nil : .default, value: runs.flatMap { $0.tasks.map(\.id) })
            .onChange(of: taskToRevisit) { _, task in
                revisit(task, using: scrollViewProxy)
            }
            // Scoped to the content: applied to the whole screen it also claimed the toolbar,
            // so two elements answered to one identifier.
            .accessibilityIdentifier("GroveQuestionnaireSection")
            #if os(iOS)
            // Questions sit closer together: the card edges already separate them, so the
            // form's default gap only pushes the page longer.
            .listSectionSpacing(.compact)
            #endif
            .toolbar {
                ToolbarItem(placement: QuestionnaireExitButton.placement) {
                    QuestionnaireExitButton(stakes: exitStakes, isProcessing: viewState == .processing) { outcome in
                        handOff(outcome == .submit ? .completed(responses) : .cancelled)
                    }
                }
            }
        }
        .viewStateAlert(state: $viewState)
        .navigationTitle(titleConfig)
        #if os(iOS)
        // A large bar shows fewer characters than an inline one, which once made it the wrong
        // choice. It is the right one now that the bar carries only names — a short name written
        // for constrained space, or the instrument's own short title — and a name still says which
        // page you are on when the bar abbreviates it. The text it might have cut is on the page.
        .navigationBarTitleDisplayMode(.large)
        #endif
        // disallow navigating around while an action is being performed;
        // SDC entryMode `sequential` forbids revisiting earlier answers entirely.
        .navigationBarBackButtonHidden(viewState == .processing || isSequentialEntry)
        // SwiftUI offers no hook for "the user attempted to dismiss", so an untouched questionnaire
        // can be flicked away, and once there is something to lose the swipe gives way to Close.
        .interactiveDismissDisabled(responses.hasAnyResponses(in: context.allSections))
    }

    /// The page's action, as the form's last row.
    private var actionSection: some View {
        SwiftUI.Section {
            primaryAction
                .formActionRow()
        }
    }

    private var isSequentialEntry: Bool {
        switch context {
        case .regular(let questionnaire):
            questionnaire.metadata.entryMode == .sequential
        case .answerNestedQuestions:
            false
        }
    }

    /// The section's own text, which always reaches the page, or the short name standing in for
    /// a text it was never given.
    ///
    /// The fallback matters on the one page where a sole group's short name takes the bar: the
    /// section's own short name is then not in the bar either, and without this the name the
    /// author wrote would appear nowhere.
    private var introText: String? {
        guard section.title.isEmpty else {
            return section.title
        }
        guard let shortTitle = section.shortTitle, !shortTitle.isEmpty, shortTitle != barTitle else {
            return nil
        }
        return shortTitle
    }

    /// The name in the navigation bar: the most specific short name the page was given, and the
    /// instrument's own name where it was given none.
    ///
    /// Only an authored `shortText` names a bar. It was written for a display too narrow for the
    /// text it stands for, so it is the one thing a bar can cut without losing anything — every
    /// authored `text` reaches the page instead. A group lends its name only when it is the only
    /// group on the page: a name in a bar has to describe everything under it, and with two
    /// groups neither one does.
    private var barTitle: String? {
        guard case let .regular(questionnaire) = context else {
            return nil
        }
        let shortNames = [soleVisibleGroup?.shortTitle, section.shortTitle].compactMap { $0 }
        return shortNames.first { !$0.isEmpty } ?? questionnaire.metadata.title
    }

    private var titleConfig: ViewTitleConfig? {
        guard case let .regular(questionnaire) = context, let barTitle else {
            return nil
        }
        let instrumentName = questionnaire.metadata.title
        return ViewTitleConfig(title: barTitle, subtitle: barTitle == instrumentName ? nil : instrumentName)
    }

    /// The group every rendered task belongs to, when they all share exactly one.
    private var soleVisibleGroup: Questionnaire.Task.Group? {
        var group: Questionnaire.Task.Group?
        for task in renderedTasks {
            guard let innermost = task.groupPath.last, innermost == (group ?? innermost) else {
                return nil
            }
            group = innermost
        }
        return group
    }

    /// The tasks this page shows, in order.
    ///
    /// Filtering here rather than inside each task is what lets an all-hidden group vanish
    /// along with its heading, instead of leaving a heading with nothing under it.
    private var renderedTasks: [Questionnaire.Task] {
        section.tasks.filter { responses.renders($0) }
    }

    private init(
        context: Context,
        section: Questionnaire.Section,
        completionStepConfig: CompletionStepConfig,
        questionProgressConfig: QuestionProgressConfig,
        completionAction: CompletionAction,
        resultHandler: @escaping @MainActor (QuestionnaireSheet.Result) async throws -> Void,
        header: Header
    ) {
        self.context = context
        self.section = section
        self.completionStepConfig = completionStepConfig
        self.questionProgressConfig = questionProgressConfig
        self.completionAction = completionAction
        self.resultHandler = resultHandler
        self.header = header
    }

    init(
        questionnaire: Questionnaire,
        section: Questionnaire.Section,
        completionStepConfig: CompletionStepConfig,
        questionProgressConfig: QuestionProgressConfig,
        completionAction: CompletionAction,
        resultHandler: @escaping @MainActor (QuestionnaireSheet.Result) async throws -> Void,
        @ViewBuilder header: @MainActor () -> Header = { EmptyView() }
    ) {
        self.init(
            context: .regular(questionnaire: questionnaire),
            section: section,
            completionStepConfig: completionStepConfig,
            questionProgressConfig: questionProgressConfig,
            completionAction: completionAction,
            resultHandler: resultHandler,
            header: header()
        )
    }

    /// Creates a ``QuestionnaireSectionView`` suitable for answering nested questions.
    ///
    /// - parameter parentTask: The ``Questionnaire/Task`` within which the nested questions reside.
    /// - parameter selectedOptionTitle: The user-displayed title of the option in the `parentTask`, in response to which the nested questions are being asked.
    /// - parameter tasks: The nested tasks.
    /// - parameter completionStepConfig: Controls if there should be a completion step once all nested questions have been completed, and what this step should look like.
    /// - parameter resultHandler: Called when the user taps the primary action after all nested questions have been answered.
    /// - parameter header: An optional header view that is displayed at the top of the `Form`, above the first task.
    init(
        nestedQuestionsFor parentTask: Questionnaire.Task,
        selectedOptionTitle: String,
        tasks: [Questionnaire.Task],
        completionStepConfig: CompletionStepConfig,
        resultHandler: @escaping @MainActor (QuestionnaireSheet.Result) async throws -> Void,
        @ViewBuilder header: @MainActor () -> Header = { EmptyView() }
    ) {
        let section = Questionnaire.Section(id: "", tasks: tasks)
        self.init(
            context: .answerNestedQuestions(parentTask: parentTask, selectedOptionTitle: selectedOptionTitle, sections: [section]),
            section: section,
            completionStepConfig: completionStepConfig,
            // A handful of follow-ups is not a journey worth counting through.
            questionProgressConfig: .disable,
            // Nothing is submitted here; the participant is returning to the parent question.
            completionAction: .done,
            resultHandler: resultHandler,
            header: header()
        )
    }

    /// Brings a question back into view, which every scroll the page makes goes through.
    ///
    /// `scrollTo` only takes effect from inside a view update, and what decides where to scroll —
    /// answering a question, or tapping the action — runs outside one.
    private func revisit(_ task: Questionnaire.Task.ID?, using scrollViewProxy: ScrollViewProxy) {
        guard let task else {
            return
        }
        withAnimation(reduceMotion ? nil : SelectionFeedback.scroll) {
            scrollViewProxy.scrollTo(task, anchor: .top)
        }
        taskToRevisit = nil
    }

    /// One question's card, under the caption the page opens above it.
    ///
    /// The caption is the `Section`'s header rather than a card of its own: a header sits outside
    /// the card as a light line that wraps for a long stem and stays small for a name, where a
    /// card of the same text reads as another question.
    @ViewBuilder
    private func cardSection(
        for task: Questionnaire.Task,
        response: Binding<QuestionnaireResponses.Response>,
        at position: (index: Int, total: Int)?,
        headedBy caption: TaskRun.Caption?
    ) -> some View {
        if let caption, !caption.isEmpty {
            SwiftUI.Section {
                card(for: task, response: response, at: position)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    if let intro = caption.intro {
                        Text(markdown: intro)
                            .accessibilityIdentifier("SectionIntro")
                    }
                    ForEach(caption.groups, id: \.self) { group in
                        Text(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            SwiftUI.Section {
                card(for: task, response: response, at: position)
            }
        }
    }

    /// One question, as the sole row of its own card.
    private func card(
        for task: Questionnaire.Task,
        response: Binding<QuestionnaireResponses.Response>,
        at position: (index: Int, total: Int)?
    ) -> some View {
        TaskView(
            task: task,
            response: response,
            position: position.map { QuestionPosition(index: $0.index, total: $0.total) }
        ) {
            if indicateBlockingTasks && responses.isMissingResponse(for: task) {
                missingResponseMark
            }
        }
        // FHIR item.readOnly: the value is displayed but not editable.
        .disabled(task.isReadOnly)
        .id(task.id)
        .accessibilityFocused($focusedTask, equals: task.id)
        .blockingCardHighlight(indicateBlockingTasks && responses.isBlockingCompletion(task))
        .environment(\.scrollToNextTask) {
            taskToRevisit = section.nextEnabledTask(after: task, using: responses)?.id
        }
    }
}


// MARK: The Primary Action

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireSectionView {
    private var isLastSection: Bool {
        responses.nextRenderedSection(after: section, in: context.allSections) == nil
    }

    private var primaryActionTitle: LocalizedStringResource {
        guard isLastSection else {
            return LocalizedStringResource("Continue", bundle: .module)
        }
        switch completionAction {
        case .done:
            return LocalizedStringResource("Done", bundle: .module)
        case .submit:
            return viewState == .processing
                ? LocalizedStringResource("Submitting…", bundle: .module)
                : LocalizedStringResource("Submit", bundle: .module)
        }
    }

    private var missingResponseMark: some View {
        QuestionMessage(Text("Answer this question to continue", bundle: .module))
    }

    /// Where a question sits in the run, when the questionnaire asks for it to be shown.
    ///
    /// It belongs above the question it counts rather than beside the action: at the foot of the
    /// page it is out of sight until the end, and it reads as a total rather than a position.
    private var questionPositions: [Questionnaire.Task.ID: (index: Int, total: Int)] {
        switch questionProgressConfig {
        case .disable:
            [:]
        case .enable:
            responses.questionPositions(in: context.allSections)
        }
    }

    /// The one prominent control on the page, its last row.
    ///
    /// It stays enabled and fully tinted even when the section is incomplete: a section can run
    /// several screens long, so the question that blocks it is usually off-screen, and a dimmed
    /// button there can say nothing about what it is waiting for. Tapping it answers the tap.
    private var primaryAction: some View {
        AsyncButton(state: $viewState) {
            try await advance()
        } label: {
            Text(primaryActionTitle)
                .bold()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyleGlassProminent()
        .accessibilityIdentifier("PrimaryAction")
        .accessibilityValue(responses.isComplete(in: section)
            ? Text("Ready", bundle: .module)
            : Text("Incomplete", bundle: .module))
        .accessibilityHint(Text("Checks your answers before continuing.", bundle: .module))
        .sensoryFeedback(.warning, trigger: failedAttempts)
    }

    private func advance() async throws {
        let blockingTasks = responses.tasksPreventingCompletion(of: section)
        guard let problematicTask = blockingTasks.first else {
            try await proceed()
            return
        }
        failedAttempts += 1
        let announcement = String(localized: "\(blockingTasks.count) questions still need an answer", bundle: .module)
        AccessibilityNotification.Announcement(announcement).post()
        focusedTask = problematicTask.id
        // The marks resize every card the page has to travel past, and a list resizes a pass later
        // than it is asked to: a scroll in between is carried out in that one frame, dropping the
        // participant at the question rather than taking them there.
        withAnimation(reduceMotion ? nil : SelectionFeedback.scroll) {
            indicateBlockingTasks = true
        } completion: {
            taskToRevisit = problematicTask.id
        }
    }

    private func proceed() async throws {
        if let nextSection = responses.nextRenderedSection(after: section, in: context.allSections) {
            navigationPath.append {
                QuestionnaireSectionView(
                    context: context,
                    section: nextSection,
                    completionStepConfig: completionStepConfig,
                    questionProgressConfig: questionProgressConfig,
                    completionAction: completionAction,
                    resultHandler: resultHandler,
                    header: header
                )
            }
            indicateBlockingTasks = false
        } else {
            switch context {
            case .regular: // we're at root level, and we're done.
                switch completionStepConfig {
                case .disable:
                    try await resultHandler(.completed(responses))
                case .enable:
                    navigationPath.append {
                        CompletionPage(title: LocalizedStringResource("Questionnaire Complete", bundle: .module)) {
                            try await resultHandler(.completed(responses))
                        }
                    }
                }
            case .answerNestedQuestions:
                // we're done answering nested answers
                try await resultHandler(.completed(responses))
            }
        }
    }
}


// MARK: Leaving the Questionnaire

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireSectionView {
    /// What closing the questionnaire right now would cost the participant.
    private var exitStakes: QuestionnaireExitButton.Stakes {
        guard responses.hasAnyResponses(in: context.allSections) else {
            return .nothingToLose
        }
        switch context {
        case .answerNestedQuestions(parentTask: _, let selectedOptionTitle, sections: _):
            return .discardsFollowUps(optionTitle: selectedOptionTitle)
        case .regular:
            guard !responses.isCompleteFromHere(section, in: context.allSections) else {
                return .canSubmit
            }
            let progress = responses.answeredQuestions(in: context.allSections)
            return .losesAnswers(answered: progress.answered, total: progress.total)
        }
    }

    /// Hands the result to the app from outside a button that could await it.
    ///
    /// A confirmation dialog is gone the instant its button is tapped, taking any task the button
    /// owned with it, so the page keeps the work and reports through its own state instead — the
    /// participant sees the page go quiet, and an error keeps them here with their answers intact.
    private func handOff(_ result: QuestionnaireSheet.Result) {
        Task {
            viewState = .processing
            do {
                try await resultHandler(result)
                viewState = .idle
            } catch {
                viewState = .error(AnyLocalizedError(error: error))
            }
        }
    }
}
