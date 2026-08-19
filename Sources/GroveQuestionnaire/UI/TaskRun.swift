//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A consecutive run of tasks sharing an innermost group.
///
/// Identified by its first task rather than by its group: a section that starts and ends
/// outside a group produces two ungrouped runs, and identifying those by a nil group id
/// collides in `ForEach`, which renders the run twice.
@available(iOS 18, macOS 15, watchOS 11, *)
struct TaskRun: Identifiable {
    /// The caption above a card: the section's own text where the page begins, and a line for
    /// every enclosing group the run opens.
    struct Caption {
        let intro: String?
        let groups: [String]

        var isEmpty: Bool {
            intro == nil && groups.isEmpty
        }
    }

    /// The groups enclosing the run, outermost first.
    let groupPath: [Questionnaire.Task.Group]
    /// The levels of that path the preceding run was not already standing in, so a group
    /// enclosing several runs heads the page once instead of once per run.
    let openedGroups: [Questionnaire.Task.Group]
    var tasks: [Questionnaire.Task]

    var id: Questionnaire.Task.ID { tasks[0].id }

    /// Gathers `tasks` into runs sharing an innermost group, so a page holding more than one
    /// group can head each run.
    ///
    /// Each run also carries the enclosing groups it opens — its path minus the levels the run
    /// before it already stood in — so every named group of a nested hierarchy heads the
    /// questions it covers, and none of them repeats itself further down the page.
    static func runs(of tasks: [Questionnaire.Task]) -> [TaskRun] {
        tasks.reduce(into: []) { runs, task in
            if var last = runs.last, last.groupPath.last == task.groupPath.last {
                last.tasks.append(task)
                runs[runs.count - 1] = last
            } else {
                let shared = zip(runs.last?.groupPath ?? [], task.groupPath).prefix { $0.0 == $0.1 }.count
                runs.append(TaskRun(
                    groupPath: task.groupPath,
                    openedGroups: Array(task.groupPath.dropFirst(shared)),
                    tasks: [task]
                ))
            }
        }
    }

    /// The names of the groups the run opens, outermost first.
    ///
    /// A group is headed whenever it was named at all: by its text, or by the short name standing
    /// in for a text it was never given. Only the bar suppresses a name, and only when it is
    /// already carrying that exact string.
    func groupHeadings(otherThan barTitle: String?) -> [String] {
        openedGroups.compactMap { group in
            let heading = group.title.isEmpty ? (group.shortTitle ?? "") : group.title
            guard !heading.isEmpty, heading != barTitle else {
                return nil
            }
            return heading
        }
    }
}
