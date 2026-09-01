//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension TaskView {
    struct ChoiceAnswering: View { // better name?!!
        /// Where the rules go in a list of options.
        enum Ruling {
            /// Between the options, the way a grouped list rules its rows.
            case betweenRows
            /// Above every option, for when something is already drawn above the first.
            case aboveEveryRow
            /// Nowhere: the options sit side by side rather than stacked.
            case none

            func rulesRow(at index: Int) -> Bool {
                switch self {
                case .betweenRows: index > 0
                case .aboveEveryRow: true
                case .none: false
                }
            }
        }

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let task: Questionnaire.Task
        let config: Questionnaire.Task.Kind.ChoiceConfig
        @Binding var response: QuestionnaireResponses.Response
        @State private var autocompleteFilter = ""

        var body: some View {
            switch config.presentation {
            case .dropDown where !config.allowsMultipleSelection && config.followUpTasks.isEmpty:
                dropDownPicker
            case .autocomplete:
                autocompleteFilterField
                optionRows(config.options.filter {
                    autocompleteFilter.isEmpty || $0.title.localizedCaseInsensitiveContains(autocompleteFilter)
                }, ruled: .aboveEveryRow)
            default:
                optionRows(config.options, ruled: .betweenRows)
            }
            if config.hasFreeTextOtherOption {
                otherOptionRow
            }
        }

        /// Whether anything is drawn above the free-text `Other` option, and so whether it needs
        /// a rule of its own to sit under.
        private var hasRowsAboveOtherOption: Bool {
            !config.options.isEmpty || config.presentation != .list
        }

        /// The `drop-down` itemControl: a compact menu for long single-select option lists.
        private var dropDownPicker: some View {
            Picker(selection: Binding<String?> {
                response.value.choiceValue.selectedOptions.first
            } set: { newValue in
                response = .init(value: .choice(.init(selectedOptions: newValue.map { [$0] } ?? [])))
            }) {
                Text("Select…", bundle: .module)
                    .tag(String?.none)
                ForEach(config.options) { option in
                    Text(option.title)
                        .tag(String?.some(option.id))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            .accessibilityLabel(task.title)
        }

        private var autocompleteFilterField: some View {
            TextField(text: $autocompleteFilter, prompt: Text("Search options…", bundle: .module)) {
                EmptyView()
            }
            #if os(iOS)
            .textFieldStyle(.roundedBorder)
            #endif
            .padding(.vertical, 8)
            .accessibilityLabel(Text("Search options…", bundle: .module))
        }

        private var otherOptionRow: some View {
                ChoiceRow(
                    id: "openChoice",
                    title: config.freeTextOtherOptionLabel ?? String(localized: "Other", bundle: .module),
                    subtitle: "",
                    isSelected: response.value.choiceValue.didSelectFreeTextOtherOption,
                    isSeparated: hasRowsAboveOtherOption
                ) {
                    // Never advances the page: answering this option means typing into the field it reveals.
                    SelectionFeedback.record(reduceMotion: reduceMotion, selectOtherOption, thenAdvance: nil)
                } accessoryIfSelected: {
                    TextField(text: $response.value.choiceValue.freeTextOtherResponse.withDefault(""), prompt: Text(verbatim: "…")) {
                        Text(verbatim: "")
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(Text("Other", bundle: .module))
                }
        }

        @ViewBuilder
        private func optionRows(
            _ options: [Questionnaire.Task.Kind.ChoiceConfig.Option],
            ruled: Ruling
        ) -> some View {
            // questionnaire-choiceOrientation: compact horizontal layout (e.g. Likert scales).
            if config.orientation == .horizontal {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        rows(options, ruled: .none)
                    }
                }
            } else {
                rows(options, ruled: ruled)
            }
        }

        private func rows(
            _ options: [Questionnaire.Task.Kind.ChoiceConfig.Option],
            ruled: Ruling
        ) -> some View {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Row(
                    task: task,
                    config: config,
                    option: option,
                    isSeparated: ruled.rulesRow(at: index),
                    response: $response
                )
                .sensoryFeedback(trigger: response.value.choiceValue.selectedOptions) { _, _ in
                    // we only want this applied to the first row; otherwise we get multiple feedbacks on each selection (one per option)
                    index == 0 ? .selection : nil
                }
            }
        }

        /// Toggles the free-text `Other` option, which in a single-choice question replaces the answer.
        private func selectOtherOption() {
            guard !config.allowsMultipleSelection else {
                response.value.choiceValue.didSelectFreeTextOtherOption.toggle()
                return
            }
            response.value.choiceValue = if response.value.choiceValue.didSelectFreeTextOtherOption {
                .init(selectedOptions: [])
            } else {
                .init(selectedOptions: [], freeTextOtherResponse: "")
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension TaskView.ChoiceAnswering {
    // This needs to be a separate view bc of the sheet presentation
    private struct Row: View {
        @Environment(QuestionnaireResponses.self) private var responses
        @Environment(\.scrollToNextTask) private var scrollToNextTask
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let task: Questionnaire.Task
        let config: Questionnaire.Task.Kind.ChoiceConfig
        let option: Questionnaire.Task.Kind.ChoiceConfig.Option
        let isSeparated: Bool
        @Binding var response: QuestionnaireResponses.Response
        @State private var isShowingFollowUpQuestionsSheet = false

        var body: some View {
            ChoiceRow(
                id: option.id,
                title: option.title,
                subtitle: option.subtitle,
                isSelected: response.value.choiceValue.didSelect(option.id),
                isSeparated: isSeparated
            ) {
                let wasSelected = response.value.choiceValue.didSelect(option.id)
                SelectionFeedback.record(
                    reduceMotion: reduceMotion,
                    { apply(wasSelected: wasSelected) },
                    // Deselecting leaves the participant where they are, so there is nothing to move on to.
                    thenAdvance: wasSelected ? nil : { continueAfterSelecting() }
                )
            }
            .sheet(isPresented: $isShowingFollowUpQuestionsSheet) {
                ManagedNavigationStack {
                    QuestionnaireSectionView(
                        nestedQuestionsFor: task,
                        selectedOptionTitle: option.title,
                        tasks: config.followUpTasks,
                        completionStepConfig: .disable
                    ) { result in
                        switch result {
                        case .completed:
                            isShowingFollowUpQuestionsSheet = false
                        case .cancelled:
                            isShowingFollowUpQuestionsSheet = false
                            // we need to un-select the option and clear out the nested responses
                            response.value.choiceValue.deselect(option.id)
                            response.nestedResponses[.choiceOption(option.id)] = nil
                        }
                    } header: {
                        VStack(alignment: .leading) {
                            Text("Follow-Up", bundle: .module)
                                .font(.headline)
                            Text(
                                "Please answer the follow-up questions below, for the **'\(option.title)'** option you just selected.",
                                bundle: .module
                            )
                            .font(.subheadline)
                        }
                    }
                    .navigationTitle(Text("Follow-Up: \(option.title)", bundle: .module))
                }
                .accessibilityIdentifier("GroveQuestionnaireNavStack")
                .interactiveDismissDisabled()
                .environment(
                    responses.view(
                        appending: QuestionnaireResponses.ResponsePath(taskId: task.id).appending(choiceOption: option.id)
                    )
                )
            }
        }

        /// Records the tap: a single-choice question keeps only the option just picked.
        private func apply(wasSelected: Bool) {
            guard config.allowsMultipleSelection else {
                response = .init(value: .choice(.init(selectedOptions: wasSelected ? [] : [option.id])))
                return
            }
            if wasSelected {
                response.value.choiceValue.deselect(option.id)
                response.nestedResponses[.choiceOption(option.id)] = nil
            } else {
                response.value.choiceValue.select(option.id, in: config)
            }
        }

        /// Asks the option's own questions, or moves on to the next one, now that the answer is confirmed.
        private func continueAfterSelecting() {
            // Read here rather than before the answer was applied: a nested task's condition has to be
            // evaluated against the selection it depends on.
            let innerResponses = responses.view(
                appending: QuestionnaireResponses.ResponsePath(taskId: task.id).appending(choiceOption: option.id)
            )
            if config.followUpTasks.contains(where: { innerResponses.shouldEnable(task: $0) }) {
                isShowingFollowUpQuestionsSheet = true
            } else if !config.allowsMultipleSelection {
                scrollToNextTask()
            }
        }
    }
}
