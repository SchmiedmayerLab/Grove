//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// How far through the run the participant is, in steps: every question is one, and so is every turn of a page.
struct ProgressCount: Hashable, Sendable {
    /// The steps behind the participant: the pages passed, their questions, and the answers given since.
    let completed: Int
    /// The steps still ahead: the questions to answer, and the pages still to reach.
    let remaining: Int

    /// Done over done plus remaining; a run with nothing left is complete.
    var fraction: Double {
        let total = completed + remaining
        return total == 0 ? 1 : Double(completed) / Double(total)
    }
}


/// Completeness and progress across several sections, which the exit flow needs in order to
/// decide whether closing loses anything, and whether it can offer to submit instead.
@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// Whether closing now would discard something the participant entered.
    ///
    /// A seeded ``Questionnaire/Task/initialValue`` does not count: nobody has touched it yet,
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

    /// Where the participant is in the run, counted so the bar keeps moving forward.
    ///
    /// Pages passed and their questions are done, answered or left. Ahead lie the pages that may still come
    /// and every question asked or not yet ruled out: one whose condition reads an unanswered question stays
    /// in the count until an answer settles it.
    func progress(at section: Questionnaire.Section, in sections: [Questionnaire.Section]) -> ProgressCount {
        guard let index = sections.firstIndex(where: { $0.id == section.id }) else {
            return ProgressCount(completed: 0, remaining: 1)
        }
        var completed = sections[..<index].reduce(0) { steps, page in
            steps + (rendersContent(in: page) ? 1 : 0) + page.tasks.count { isQuestion($0) }
        }
        var remaining = sections[(index + 1)...].count { mayRenderContent(in: $0) }
        for task in sections[index...].lazy.flatMap(\.tasks) where mayBeAsked(task) {
            // Answered the way the page accepts it: an "Other" without its text is no step yet.
            if isQuestion(task) && hasResponse(for: task) && validateResponse(for: task).isOk {
                completed += 1
            } else {
                remaining += 1
            }
        }
        return ProgressCount(completed: completed, remaining: remaining)
    }

    /// Whether the section shows something now, or still might once more has been answered.
    private func mayRenderContent(in section: Questionnaire.Section) -> Bool {
        section.tasks.contains { !$0.isHidden && (renders($0) || !isEnablementSettled(for: $0)) }
    }

    /// Whether the task is asked now, or still might be once more has been answered.
    private func mayBeAsked(_ task: Questionnaire.Task) -> Bool {
        !task.isHidden && asks(task) && (shouldEnable(task: task) || !isEnablementSettled(for: task))
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
        !task.isHidden && shouldEnable(task: task) && asks(task)
    }

    /// Whether the task is the kind that asks for something, wherever it is shown.
    private func asks(_ task: Questionnaire.Task) -> Bool {
        switch task.kind.variant {
        case .instructional:
            false
        case .boolean, .choice, .freeText, .dateTime, .numeric, .fileAttachment, .custom:
            true
        }
    }
}
