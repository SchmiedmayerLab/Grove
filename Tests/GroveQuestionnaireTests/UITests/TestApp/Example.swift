//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import GroveQuestionnaire
import SwiftUI


/// One row of a catalog page: a questionnaire, and the settings the sheet answers it with.
struct Example: Identifiable {
    let title: String
    let questionnaire: Questionnaire
    let completionStepConfig: CompletionStepConfig
    let progress: QuestionnaireProgress
    let hints: QuestionnaireHints
    let completionAction: CompletionAction

    var id: String {
        title
    }

    init(
        _ questionnaire: Questionnaire,
        title: String? = nil,
        // The renderer's own default: an extra screen to dismiss is a cost, and the Completion
        // Flow examples are where it is meant to be looked at.
        completionStepConfig: CompletionStepConfig = .disable,
        progress: QuestionnaireProgress = .bar,
        // Every hint on, so the catalog shows what the sheet can say.
        hints: QuestionnaireHints = .all,
        completionAction: CompletionAction = .submit
    ) {
        self.title = title ?? questionnaire.metadata.title
        self.questionnaire = questionnaire
        self.completionStepConfig = completionStepConfig
        self.progress = progress
        self.hints = hints
        self.completionAction = completionAction
    }
}


/// A titled run of examples within a catalog page.
struct ExampleGroup: Identifiable {
    let title: String
    let examples: [Example]

    var id: String {
        title
    }

    init(_ title: String, _ examples: [Example]) {
        self.title = title
        self.examples = examples
    }
}


/// A catalog page: the examples of one authoring route, each opening straight into the renderer.
struct ExampleCatalog: View {
    let route: AuthoringRoute
    let groups: [ExampleGroup]

    @State private var running: Example?

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.examples) { example in
                        ExampleRow(example: example) {
                            running = example
                        }
                    }
                }
            }
        }
        .navigationTitle(route.title)
        .runsQuestionnaires($running)
    }
}


/// A row that opens its example in the renderer.
struct ExampleRow: View {
    let example: Example
    let start: () -> Void

    var body: some View {
        Button(example.title, action: start)
            .accessibilityIdentifier("Example:\(example.title)")
    }
}


extension View {
    /// Presents the selected example, and files whatever it collects in the responses store.
    func runsQuestionnaires(_ example: Binding<Example?>) -> some View {
        modifier(QuestionnaireRunner(example: example))
    }
}


private struct QuestionnaireRunner: ViewModifier {
    /// Stands in for whatever an app does with the answers and cannot always do.
    private struct SubmissionFailure: LocalizedError {
        var errorDescription: String? { "The answers could not be saved." }
    }

    @Environment(ResponsesStore.self) private var responsesStore
    @Environment(SheetSettings.self) private var settings

    @Binding var example: Example?

    /// Whether this launch fails every submission, so a test can see what a failed one looks like.
    private var failsSubmission: Bool {
        ProcessInfo.processInfo.arguments.contains("--failSubmission")
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $example) { running in
                QuestionnaireSheet(
                    running.questionnaire,
                    completionStepConfig: settings.completionStepConfig(for: running),
                    progress: settings.progress(for: running),
                    hints: settings.hints(for: running),
                    completionAction: settings.completionAction(for: running)
                ) { result in
                    if case .completed(let responses) = result {
                        // Throwing here is what a failed submit looks like: the renderer reports it
                        // and the participant keeps their answers, so the sheet stays open.
                        guard !failsSubmission else {
                            throw SubmissionFailure()
                        }
                        try responsesStore.record(responses, from: running.title)
                    }
                    example = nil
                }
            }
    }
}
