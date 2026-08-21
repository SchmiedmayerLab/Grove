//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// Where a question sits in the run of questions being asked.
struct QuestionPosition: Hashable, Sendable {
    let index: Int
    let total: Int
}


@available(iOS 18, macOS 15, watchOS 11, *)
struct TaskView<Footer: View>: View {
    @Environment(QuestionnaireResponses.self) private var allResponses
    @Environment(\.scrollToNextTask) private var scrollToNextTask
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: Questionnaire.Task
    @Binding var response: QuestionnaireResponses.Response
    var position: QuestionPosition?
    @ViewBuilder let footer: @MainActor () -> Footer

    /// One question as one row, drawn as a list: the parts are separated by rules the way a
    /// grouped list separates its rows.
    ///
    /// The question cannot be a `Section` of real rows, because the section is decorated from
    /// outside — the blocking highlight is a `background`, and a `Section` is not a view that can
    /// carry one. Keeping the question a single row keeps those modifiers, and its accessibility
    /// container, working; the rules below restore the appearance a list is expected to have.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !displayTitle.isEmpty || !task.subtitle.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if let position {
                        Text("Question \(position.index) of \(position.total)", bundle: .module)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("QuestionProgress")
                    }
                    if !displayTitle.isEmpty {
                        Text(markdown: displayTitle)
                            .font(.headline)
                    }
                    if !task.subtitle.isEmpty {
                        Text(markdown: task.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 11)
                if hasContentBelowTitle {
                    Divider()
                }
            }
            mediaView
            mainContent
            supplementaryText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Task:\(task.id)")
    }

    /// Whether anything is drawn under the title.
    ///
    /// A section label is an instructional task with no text, which otherwise came out as a card
    /// holding a heading and a rule with nothing beneath it.
    private var hasContentBelowTitle: Bool {
        if task.media != nil || !task.footer.isEmpty {
            return true
        }
        if case .instructional(let text) = task.kind.variant {
            return !text.isEmpty
        }
        return true
    }

    @ViewBuilder private var supplementaryText: some View {
        if !task.footer.isEmpty {
            Text(markdown: task.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        footer()
        // A missing answer and an invalid one are the same thing to the participant —
        // this is what is blocking you — so they share a colour, and a glyph carries the
        // meaning for anyone who cannot see it.
        switch allResponses.validateResponse(for: task) {
        case .ok:
            EmptyView()
        case .invalid(let message):
            QuestionMessage(Text(message))
        }
    }

    /// The rendered title: question numbering (`item.prefix`) joined with the title, preferring
    /// the SDC `shortText` on watchOS and standing in with it where no title was authored.
    private var displayTitle: String {
        #if os(watchOS)
        let base = task.shortTitle ?? task.title
        #else
        let base = task.title.isEmpty ? (task.shortTitle ?? "") : task.title
        #endif
        return task.prefix.map { "\($0) \(base)" } ?? base
    }

    /// The task's SDC `itemMedia` image, when one is declared.
    @ViewBuilder private var mediaView: some View {
        if let media = task.media, media.contentType.hasPrefix("image/") {
            #if canImport(UIKit)
            if let image = UIImage(data: media.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.vertical, 8)
                    .accessibilityLabel(media.altText ?? "")
            }
            #elseif canImport(AppKit)
            if let image = NSImage(data: media.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.vertical, 8)
                    .accessibilityLabel(media.altText ?? "")
            }
            #endif
        }
    }

    @ViewBuilder private var mainContent: some View {
        switch task.kind.variant {
        case .instructional(let text):
            Instructions(text: text)
        case .choice(let config):
            ChoiceAnswering(task: task, config: config, response: $response)
        case .freeText(let config):
            FreeTextEntry(label: task.title, config: config, response: $response.value.stringValue.withDefault(""))
        case .dateTime(let config):
            DatePickerRow(label: task.title, config: config, response: $response.value.dateValue)
        case .numeric(let config):
            NumericInputRow(label: task.title, config: config, value: $response.value)
        case .boolean:
            yesNoRows
        case .fileAttachment(let config):
            FileAttachmentQuestionView(config: config, attachments: $response.value.attachmentsValue.withDefault([]))
        case let .custom(questionKind, config):
            questionKind.makeView(for: task, using: config, response: $response).intoAnyView()
        }
    }
    
    /// Yes and No as two rows of the question's card, ruled apart like any other option list.
    @ViewBuilder private var yesNoRows: some View {
        SimpleChoiceRow(
            id: "true",
            title: String(localized: "Yes", bundle: .module),
            subtitle: "",
            isSelected: selection(of: true)
        )
        SimpleChoiceRow(
            id: "false",
            title: String(localized: "No", bundle: .module),
            subtitle: "",
            isSelected: selection(of: false),
            isSeparated: true
        )
    }

    /// Picking an answer records it; picking it again clears the question.
    private func selection(of answer: Bool) -> Binding<Bool> {
        Binding {
            response.value.boolValue == answer
        } set: { isSelected in
            SelectionFeedback.record(
                reduceMotion: reduceMotion,
                { response.value.boolValue = isSelected ? answer : nil },
                thenAdvance: isSelected ? scrollToNextTask : nil
            )
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionKindDefinition {
    @MainActor
    @ViewBuilder
    fileprivate static func makeView(
        for task: Questionnaire.Task,
        using config: any QuestionKindConfig,
        response: Binding<QuestionnaireResponses.Response>
    ) -> some SwiftUI.View {
        if let config = config as? Config {
            self.makeView(for: task, using: config, response: response)
        } else {
            EmptyView()
        }
    }
}


extension View {
    func intoAnyView() -> AnyView {
        AnyView(self)
    }
}
