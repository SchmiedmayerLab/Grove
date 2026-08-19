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
                    if config.allowsMultipleSelection {
                        response.value.choiceValue.didSelectFreeTextOtherOption.toggle()
                    } else {
                        let oldSelectionState = response.value.choiceValue.didSelectFreeTextOtherOption
                        if oldSelectionState {
                            // we just deselected this option
                            response.value.choiceValue = .init(selectedOptions: [])
                        } else {
                            // we just selected it
                            response.value.choiceValue = .init(selectedOptions: [], freeTextOtherResponse: "")
                        }
                    }
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
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension TaskView.ChoiceAnswering {
    // This needs to be a separate view bc of the sheet presentation
    private struct Row: View {
        @Environment(QuestionnaireResponses.self) private var responses
        @Environment(\.scrollToNextTask) private var scrollToNextTask
        
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
                let oldSelectionState = response.value.choiceValue.didSelect(option.id)
                if !config.allowsMultipleSelection {
                    if oldSelectionState {
                        // was selected before; we're now deselecting
                        response = .init(value: .choice(.init(selectedOptions: [])))
                    } else {
                        // was not selected before; we're now selecting
                        response = .init(value: .choice(.init(selectedOptions: [option.id])))
                    }
                } else {
                    if oldSelectionState {
                        response.value.choiceValue.deselect(option.id)
                        response.nestedResponses[.choiceOption(option.id)] = nil
                    } else {
                        response.value.choiceValue.select(option.id, in: config)
                    }
                }
                // we need this bc the condition of the nested task needs to be evaluated in the correct context.
                let innerResponses = responses.view(
                    appending: QuestionnaireResponses.ResponsePath(taskId: task.id).appending(choiceOption: option.id)
                )
                if !oldSelectionState, config.followUpTasks.contains(where: { innerResponses.shouldEnable(task: $0) }) {
                    // the option wasn't selected before, but is now, and also we have some follow up tasks.
                    isShowingFollowUpQuestionsSheet = true
                }
                if !isShowingFollowUpQuestionsSheet, !config.allowsMultipleSelection, !oldSelectionState {
                    // if we just selected an option in a single-choice question, and there are no follow-up questions, we scroll to the next task.
                    scrollToNextTask()
                }
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
    }
}
