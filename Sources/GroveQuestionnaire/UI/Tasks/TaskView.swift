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


/// How long the room for a message takes to open, and to close: a little longer than the answer's
/// confirmation, which fades the line and the mark meanwhile.
private let messageOpening: TimeInterval = 0.28
private let messageClosing: TimeInterval = 0.14


@available(iOS 18, macOS 15, watchOS 11, *)
struct TaskView: View {
    @Environment(QuestionnaireResponses.self) private var allResponses
    @Environment(\.scrollToNextTask) private var scrollToNextTask
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.questionnaireHints) private var hints

    /// The room the message takes, and the room it took: the card unfolds from the one to the other.
    @State private var messageHeight: CGFloat = 0
    @State private var previousMessageHeight: CGFloat = 0
    /// Bumped for each change of room, to run the unfolding once more.
    @State private var unfolding = 0
    /// The last message, kept on the card while it fades and the room closes over it.
    @State private var retainedMessage: Text?

    let task: Questionnaire.Task
    @Binding var response: QuestionnaireResponses.Response
    var position: QuestionPosition?
    /// Whether the question is what keeps the page from continuing, once the participant has tried to.
    var isBlocking = false
    /// What the page has to say about the answer, under the question.
    var message: Text?

    private var allowsSeveralAnswers: Bool {
        guard case .choice(let config) = task.kind.variant else {
            return false
        }
        return config.allowsMultipleSelection
    }

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
                heading
                    .padding(.top, 6)
                    .padding(.bottom, 11)
                if hasContentBelowTitle {
                    Divider()
                }
            }
            mediaView
            mainContent
            supplementaryText
            messages
        }
        // At its own height, held to the top of its row and clipped: a row the list resizes on its own clock
        // would otherwise centre or squeeze what it holds.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .blockingCardHighlight(isBlocking)
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let position {
                Text("Question \(position.index) of \(position.total)", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // The digits roll when an answer opens or closes questions elsewhere on the page.
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: position)
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
            if allowsSeveralAnswers && hints.contains(.selectAllThatApply) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .accessibilityHidden(true)
                    Text("Select all that apply", bundle: .module)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.05), in: .capsule)
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("SelectionHint")
            }
        }
    }

    @ViewBuilder private var supplementaryText: some View {
        if !task.footer.isEmpty {
            Text(markdown: task.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The message, unfolding from the foot of the card a frame at a time: in an animated transaction the list
    /// would resize the row around content laid out at its final size, and the question would walk down and back.
    private var messages: some View {
        let current = currentMessage
        let growing = messageHeight > previousMessageHeight
        // The line fades in once there is room for it; a card resized around the same line keeps it in view.
        let arriving = growing && previousMessageHeight == 0
        return KeyframeAnimator(initialValue: 0.0, trigger: unfolding) { progress in
            let showing = arriving ? UnitCurve.easeOut.value(at: max(progress - 0.6, 0) * 2.5) : 1
            SwiftUI.Group {
                // Gone once the room has closed over it, not before: the line fades meanwhile.
                if let retainedMessage, current != nil || messageHeight > 0 || progress < 1 {
                    QuestionMessage(retainedMessage)
                }
            }
            .opacity(current == nil ? 0 : showing)
            .offset(y: (1 - showing) * 4)
            // Going, the line fades at the pace an answer is confirmed, together with the mark.
            .animation(reduceMotion ? nil : SelectionFeedback.confirmation, value: current == nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: room(progress: progress), alignment: .top)
            .clipped()
        } keyframes: { _ in
            LinearKeyframe(1.0, duration: reduceMotion ? 0.01 : growing ? messageOpening : messageClosing)
        }
        .background(alignment: .top) {
            measure(current)
        }
        .onChange(of: current, initial: true) { _, current in
            if let current {
                retainedMessage = current
            }
        }
    }

    /// A missing answer and an invalid one are the same thing to the participant — this is what is blocking
    /// you — so the page's message and a rule's verdict share one line.
    private var currentMessage: Text? {
        if let message {
            return message
        }
        if case .invalid(let verdict) = allResponses.validateResponse(for: task) {
            return Text(verdict)
        }
        return nil
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

    /// The room the message asks for, measured off the card: the one on the card may be the one going.
    private func measure(_ current: Text?) -> some View {
        VStack(spacing: 0) {
            if let current {
                QuestionMessage(current)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            guard height != messageHeight else {
                return
            }
            previousMessageHeight = messageHeight
            messageHeight = height
            unfolding += 1
        }
    }

    /// The room on its way from the last height to the current one.
    private func room(progress: Double) -> CGFloat {
        previousMessageHeight + (messageHeight - previousMessageHeight) * UnitCurve.easeInOut.value(at: progress)
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
