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
        @Environment(\.scrollToNextTask) private var scrollToNextTask

        let task: Questionnaire.Task
        let config: Questionnaire.Task.Kind.ChoiceConfig
        @Binding var response: QuestionnaireResponses.Response
        @State private var autocompleteFilter = ""
        @FocusState private var isOtherFieldFocused: Bool

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
        ///
        /// A picker inside a menu, so the list marks the choice, under a pill of our own: the menu style's
        /// button is a line of tinted text, where every other answer that opens on tap is a pill.
        private var dropDownPicker: some View {
            let selected = response.value.choiceValue.selectedOptions.first
            let selection = Binding<String?> {
                selected
            } set: { newValue in
                SelectionFeedback.record(
                    reduceMotion: reduceMotion,
                    { response = .init(value: .choice(.init(selectedOptions: newValue.map { [$0] } ?? []))) },
                    thenAdvance: newValue == nil ? nil : scrollToNextTask
                )
            }
            let selectedTitle = config.options.first { $0.id == selected }.map { Text($0.title) }
            return Menu {
                Picker(selection: selection) {
                    Text("Select…", bundle: .module)
                        .tag(String?.none)
                    ForEach(config.options) { option in
                        Text(option.title)
                            .tag(String?.some(option.id))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                AnswerPill(
                    text: selectedTitle ?? Text("Select…", bundle: .module),
                    isPlaceholder: selected == nil,
                    symbol: "chevron.up.chevron.down"
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(selectedTitle ?? Text("Select…", bundle: .module))
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
                    isSeparated: hasRowsAboveOtherOption,
                    mark: config.allowsMultipleSelection ? .multiple : .single
                ) {
                    // Never advances the page: answering this option means typing into the field it reveals.
                    SelectionFeedback.record(reduceMotion: reduceMotion, selectOtherOption, thenAdvance: nil)
                } accessoryIfSelected: {
                    TextField(text: otherText, prompt: Text("Your answer", bundle: .module)) {
                        Text(verbatim: "")
                    }
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($isOtherFieldFocused)
                    .accessibilityLabel(Text("Other", bundle: .module))
                }
        }

        /// The field's text, written only while "Other" is the answer: the field gives up its text as it
        /// leaves, and a write then would choose "Other" again over the option that replaced it.
        private var otherText: Binding<String> {
            Binding {
                response.value.choiceValue.freeTextOtherResponse ?? ""
            } set: { text in
                guard response.value.choiceValue.freeTextOtherResponse != nil else {
                    return
                }
                response.value.choiceValue.freeTextOtherResponse = text
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
            }
        }

        /// Toggles the free-text `Other` option, which in a single-choice question replaces the answer.
        private func selectOtherOption() {
            let wasSelected = response.value.choiceValue.didSelectFreeTextOtherOption
            if config.allowsMultipleSelection {
                response.value.choiceValue.didSelectFreeTextOtherOption.toggle()
            } else {
                response.value.choiceValue = wasSelected ? .init(selectedOptions: []) : .init(selectedOptions: [], freeTextOtherResponse: "")
            }
            // Choosing "Other" means typing, so the field takes the cursor as soon as it exists.
            if !wasSelected {
                Task { @MainActor in
                    isOtherFieldFocused = true
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
                isSeparated: isSeparated,
                mark: config.allowsMultipleSelection ? .multiple : .single
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
                        Text(
                            "Please answer the follow-up questions below, for the **'\(option.title)'** option you just selected.",
                            bundle: .module
                        )
                        .font(.subheadline)
                    }
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
