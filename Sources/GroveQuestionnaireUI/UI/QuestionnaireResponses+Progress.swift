//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Completeness and progress across several sections, which the exit flow needs in order to
/// decide whether closing loses anything, and whether it can offer to submit instead.
@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// Whether closing now would discard something the participant entered.
    ///
    /// A seeded `Questionnaire/Task/initialValue` does not count: nobody has touched it yet,
    /// so there is nothing to lose and nothing to confirm.
    func hasAnyResponses(in sections: some Collection<Questionnaire.Section>) -> Bool {
        sections.contains { section in
            section.tasks.contains { task in
                let value = responses[task.id].value
                return value != .none && value != task.initialValue
            }
        }
    }

    /// How many of the questions currently being asked have an answer, and how many there are.
    func answeredQuestions(in sections: some Collection<Questionnaire.Section>) -> (answered: Int, total: Int) {
        var answered = 0
        var total = 0
        for task in sections.lazy.flatMap(\.tasks) where isQuestion(task) {
            total += 1
            if hasResponse(for: task) {
                answered += 1
            }
        }
        return (answered, total)
    }

    /// Where each question sits among the questions being asked, and how many there are.
    ///
    /// Counted over questions rather than over everything rendered, so instructions and section
    /// labels take no number, and over the whole questionnaire rather than the page, so the count
    /// keeps rising across sections. Built once per render: deciding whether a task is a question
    /// evaluates its condition, so asking per task would evaluate every condition once per task.
    func questionPositions(
        in sections: some Collection<Questionnaire.Section>
    ) -> [Questionnaire.Task.ID: (index: Int, total: Int)] {
        let questions = sections.flatMap(\.tasks).filter { isQuestion($0) }
        return Dictionary(
            uniqueKeysWithValues: questions.enumerated().map { ($1.id, ($0 + 1, questions.count)) }
        )
    }

    /// Whether the task would put anything on screen.
    ///
    /// A hidden or disabled task shows nothing, and neither does an instructional item left with
    /// no text: a spacer in the source questionnaire should not be given a card of its own.
    func renders(_ task: Questionnaire.Task) -> Bool {
        guard !task.isHidden, shouldEnable(task: task) else {
            return false
        }
        guard case .instructional(let text) = task.kind.variant else {
            return true
        }
        return !text.isEmpty || !task.title.isEmpty || !task.subtitle.isEmpty || !task.footer.isEmpty || task.media != nil
    }

    /// Whether the section would put anything on screen.
    func rendersContent(in section: Questionnaire.Section) -> Bool {
        section.tasks.contains { renders($0) }
    }

    /// The next section that would actually put something on screen.
    ///
    /// ``nextSection(after:in:)`` already passes over sections whose tasks are all disabled;
    /// a section left holding nothing but hidden tasks renders an empty page just the same,
    /// so it is passed over too.
    func nextRenderedSection(
        after section: Questionnaire.Section,
        in sections: some Collection<Questionnaire.Section>
    ) -> Questionnaire.Section? {
        var section = section
        while let next = nextSection(after: section, in: sections) {
            guard !rendersContent(in: next) else {
                return next
            }
            section = next
        }
        return nil
    }

    /// Whether this section and every section the participant would still be shown after it are complete.
    func isCompleteFromHere(_ section: Questionnaire.Section, in sections: some Collection<Questionnaire.Section>) -> Bool {
        var section = section
        while isComplete(in: section) {
            guard let next = nextRenderedSection(after: section, in: sections) else {
                return true
            }
            section = next
        }
        return false
    }

    /// Whether the task is what keeps its section from being finished.
    func isBlockingCompletion(_ task: Questionnaire.Task) -> Bool {
        guard !task.isHidden, shouldEnable(task: task) else {
            return false
        }
        return isMissingResponse(for: task) || !validateResponse(for: task).isOk
    }

    /// Every task in the section that currently keeps it from being complete.
    func tasksPreventingCompletion(of section: Questionnaire.Section) -> [Questionnaire.Task] {
        section.tasks.filter { isBlockingCompletion($0) }
    }

    /// Whether the task asks the participant for something, as opposed to telling them something.
    private func isQuestion(_ task: Questionnaire.Task) -> Bool {
        guard !task.isHidden, shouldEnable(task: task) else {
            return false
        }
        switch task.kind.variant {
        case .instructional:
            return false
        case .boolean, .choice, .freeText, .dateTime, .numeric, .fileAttachment, .custom:
            return true
        }
    }
}
