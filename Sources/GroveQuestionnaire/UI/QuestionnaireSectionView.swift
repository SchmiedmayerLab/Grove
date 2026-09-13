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
    enum Context {
        case regular(questionnaire: Questionnaire)
        case answerNestedQuestions(
            parentTask: Questionnaire.Task,
            selectedOptionTitle: String,
            sections: [Questionnaire.Section]
        )

        var allSections: [Questionnaire.Section] {
            switch self {
            case .regular(let questionnaire): questionnaire.sections
            case .answerNestedQuestions(parentTask: _, selectedOptionTitle: _, let sections): sections
            }
        }
    }

    /// The room between two cards. Half of it is kept above the content, so a card scrolled to the top stops
    /// halfway into the gap it shares with the one before rather than against the navigation bar.
    private static var cardGap: CGFloat { 16 }

    @Environment(ManagedNavigationStack.Path.self) private var navigationPath
    @Environment(QuestionnaireResponses.self) private var responses
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let header: Header
    let context: Context
    private let completionStepConfig: CompletionStepConfig
    private let progress: QuestionnaireProgress
    private let completionAction: CompletionAction
    let section: Questionnaire.Section
    private let resultHandler: @MainActor (QuestionnaireSheet.Result) async throws -> Void

    @State private var indicateBlockingTasks = false
    @State private var viewState: ViewState = .idle
    @State private var failedAttempts = 0
    /// The question the page has been asked to bring back into view.
    @State private var taskToRevisit: Questionnaire.Task.ID?
    @AccessibilityFocusState private var focusedTask: Questionnaire.Task.ID?

    var body: some View {
        let runs = TaskRun.runs(of: renderedTasks)
        // Without a name to head the page, an empty section would still hold its room above the cards; a header
        // written for the page is taken to show something.
        let showsTitleSection = !progress.contains(.bar) || Header.self != EmptyView.self
        ScrollViewReader { scrollViewProxy in
            Form {
                if showsTitleSection {
                    titleSection
                }
                cards(in: runs)
                    // disallow mutating responses while an action is being performed
                    .disabled(viewState == .processing)
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
            .listSectionSpacing(Self.cardGap)
            #endif
            .dismissesKeyboardLikeAForm()
            .contentMargins(.top, Self.cardGap / 2, for: .scrollContent)
            .modifier(PageNaming(title: pageTitle, subtitle: pageSubtitle, inBar: progress.contains(.bar)))
            .modifier(PageProgressReporting(fraction: pageFraction))
            .floatingActions { primaryAction }
            .toolbar {
                ToolbarItem(placement: QuestionnaireExitButton.placement) {
                    QuestionnaireExitButton(stakes: exitStakes, isProcessing: viewState == .processing) { outcome in
                        handOff(outcome == .submit ? .completed(responses) : .cancelled)
                    }
                }
            }
        }
        .viewStateAlert(state: $viewState)
        // disallow navigating around while an action is being performed;
        // SDC entryMode `sequential` forbids revisiting earlier answers entirely.
        .navigationBarBackButtonHidden(viewState == .processing || isSequentialEntry)
        // SwiftUI offers no hook for "the user attempted to dismiss", so an untouched questionnaire
        // can be flicked away, and once there is something to lose the swipe gives way to Close.
        .interactiveDismissDisabled(responses.hasAnyResponses(in: context.allSections))
    }

    private var isSequentialEntry: Bool {
        guard case .regular(let questionnaire) = context else {
            return false
        }
        return questionnaire.metadata.entryMode == .sequential
    }

    /// The tasks this page shows, in order.
    ///
    /// Filtering here rather than inside each task is what lets an all-hidden group vanish
    /// along with its heading, instead of leaving a heading with nothing under it.
    var renderedTasks: [Questionnaire.Task] {
        section.tasks.filter { responses.renders($0) }
    }

    private init(
        context: Context,
        section: Questionnaire.Section,
        completionStepConfig: CompletionStepConfig,
        progress: QuestionnaireProgress,
        completionAction: CompletionAction,
        resultHandler: @escaping @MainActor (QuestionnaireSheet.Result) async throws -> Void,
        header: Header
    ) {
        self.context = context
        self.section = section
        self.completionStepConfig = completionStepConfig
        self.progress = progress
        self.completionAction = completionAction
        self.resultHandler = resultHandler
        self.header = header
    }

    init(
        questionnaire: Questionnaire,
        section: Questionnaire.Section,
        completionStepConfig: CompletionStepConfig,
        progress: QuestionnaireProgress,
        completionAction: CompletionAction,
        resultHandler: @escaping @MainActor (QuestionnaireSheet.Result) async throws -> Void,
        @ViewBuilder header: @MainActor () -> Header = { EmptyView() }
    ) {
        self.init(
            context: .regular(questionnaire: questionnaire),
            section: section,
            completionStepConfig: completionStepConfig,
            progress: progress,
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
    /// - parameter header: An optional view shown under the page's title, above the first task.
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
            progress: [],
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

    /// What the run's first card is headed by: the section's own text on the first run, and the groups' names.
    private func caption(for run: TaskRun, in runs: [TaskRun]) -> TaskRun.Caption {
        TaskRun.Caption(
            intro: run.id == runs.first?.id ? introText : nil,
            groups: run.groupHeadings(otherThan: pageTitle)
        )
    }

    /// One card per question: two questions sharing a card read as one.
    ///
    /// FHIR questionnaire-hidden: hidden tasks carry values but are never rendered.
    private func cards(in runs: [TaskRun]) -> some View {
        @Bindable var responses = responses
        let positions = questionPositions
        return ForEach(runs) { run in
            let caption = caption(for: run, in: runs)
            ForEach(run.tasks) { task in
                cardSection(
                    for: task,
                    response: $responses.responses[task.id],
                    at: positions[task.id],
                    headedBy: task.id == run.tasks[0].id ? caption : nil
                )
            }
        }
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

    /// Why the question keeps the page from continuing, once the participant has tried to.
    private func blockingMessage(for task: Questionnaire.Task) -> Text? {
        guard indicateBlockingTasks else {
            return nil
        }
        if responses.isMissingResponse(for: task) {
            return Text("Answer this question to continue", bundle: .module)
        }
        if case .incomplete(let message) = responses.validateResponse(for: task) {
            return Text(message)
        }
        return nil
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
            position: position.map { QuestionPosition(index: $0.index, total: $0.total) },
            isBlocking: indicateBlockingTasks && responses.isBlockingCompletion(task),
            message: blockingMessage(for: task)
        )
        // FHIR item.readOnly: the value is displayed but not editable.
        .disabled(task.isReadOnly)
        .id(task.id)
        .accessibilityFocused($focusedTask, equals: task.id)
        .environment(\.scrollToNextTask) {
            taskToRevisit = section.nextEnabledTask(after: task, using: responses)?.id
        }
    }
}


// MARK: Heading the Page

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireSectionView {
    /// The page's name and whatever introduces it, heading the cards at their width.
    private var titleSection: some View {
        SwiftUI.Section {
        } header: {
            VStack(alignment: .leading, spacing: 8) {
                // With a progress bar the name lives in the navigation bar, where the bar hangs off it.
                if !pageTitle.isEmpty && !progress.contains(.bar) {
                    PageHeader(title: pageTitle, subtitle: pageSubtitle, subtitleRises: true, spacing: .compact)
                }
                header
            }
            // A header rather than a row: a row's rounded cell clips the first glyph of a title set into its corner.
            // Pulled up out of the room the form leaves above its first section, to where a large navigation title
            // sits, at the cards' outer edge, which is where a navigation title starts too.
            .textCase(nil)
            .foregroundStyle(.primary)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: -4, trailing: 0))
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
        guard let shortTitle = section.shortTitle, !shortTitle.isEmpty, shortTitle != pageTitle else {
            return nil
        }
        return shortTitle
    }
}


// MARK: The Primary Action

@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireSectionView {
    private var primaryActionTitle: LocalizedStringResource {
        guard responses.nextRenderedSection(after: section, in: context.allSections) == nil else {
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

    /// Where a question sits in the run, when asked for; above the question, where it reads as a position.
    private var questionPositions: [Questionnaire.Task.ID: (index: Int, total: Int)] {
        progress.contains(.questionNumbers) ? responses.questionPositions(in: context.allSections) : [:]
    }

    /// How far the run is, for the sheet's bar; a follow-up sheet does not report.
    private var pageFraction: Double? {
        guard case .regular = context, progress.contains(.bar) else {
            return nil
        }
        return responses.progress(at: section, in: context.allSections).fraction
    }

    /// The one prominent control on the page, floating over the foot of it.
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
        // No transaction: the cards grow on their own, a frame at a time. The scroll waits for them: a scroll
        // during the growth is carried out against the frames of that one moment.
        let growing = !indicateBlockingTasks && !reduceMotion
        indicateBlockingTasks = true
        Task {
            if growing {
                try? await Task.sleep(for: .milliseconds(350))
            }
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
                    progress: progress,
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
