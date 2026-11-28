//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// What the evaluation of enableWhen derives from the questionnaire and the stored responses.
@available(iOS 18, macOS 15, watchOS 11, *)
struct EnablementCache {
    /// The tasks and groups on a dependency cycle, which the questionnaire alone decides.
    var cyclic: Set<ConditionDependencies.Node>? // swiftlint:disable:this discouraged_optional_collection
    /// The placements for the containers conditions were evaluated in, valid for `revision`.
    var placements: [QuestionnaireResponses.ResponsesPath: EnablementPlacement] = [:]
    var revision: QuestionnaireResponses.Revision?
}


/// Every occurrence of the questionnaire's tasks in the response tree, in document order, as the pair rules place
/// the items of the exported response.
///
/// A task occurs once in every container it can appear in: a follow-up task once beneath every selected option
/// of its choice task, and once without answers while the choice task has no selection. A placement is made for
/// the container a condition is evaluated in, which also holds the container of an unselected option or an empty
/// container of a custom kind when a condition is evaluated there.
@available(iOS 18, macOS 15, watchOS 11, *)
struct EnablementPlacement {
    struct Occurrence {
        let task: Questionnaire.Task
        /// The path of the container that holds the task's response; `nil` for an occurrence without answers.
        let container: QuestionnaireResponses.ResponsesPath?
        /// The path of the container the task's expressions are evaluated in.
        let scope: QuestionnaireResponses.ResponsesPath
        /// The occurrence of the task this one follows up on.
        let parent: Int?
        /// Whether conditions can read the occurrence. The container of an unselected option, in which a
        /// condition can still be evaluated, is not part of the response.
        let isReadable: Bool
    }

    private struct Level {
        let tasks: [Questionnaire.Task]
        var next = 0
        let container: QuestionnaireResponses?
        let scope: QuestionnaireResponses
        let parent: Int?
        let isReadable: Bool
        /// The rest of the path to the observed container, when this level is on it.
        let path: [QuestionnaireResponses.ResponsePathComponent]? // swiftlint:disable:this discouraged_optional_collection
    }

    private(set) var occurrences: [Occurrence] = []
    /// The occurrences conditions can read, by task id, in document order.
    private(set) var readable: [Questionnaire.Task.ID: [Int]] = [:]
    /// The occurrences in the observed container, by task id.
    private(set) var observed: [Questionnaire.Task.ID: Int] = [:]

    /// Places the occurrences of `root`'s tasks, depth first, with an explicit stack.
    init(of root: QuestionnaireResponses, observing path: QuestionnaireResponses.ResponsesPath) {
        let tasks = root.questionnaire.sections.flatMap(\.tasks)
        var levels = [Level(tasks: tasks, container: root, scope: root, parent: nil, isReadable: true, path: Array(path))]
        while let level = levels.last {
            guard level.next < level.tasks.count else {
                levels.removeLast()
                continue
            }
            levels[levels.count - 1].next += 1
            let task = level.tasks[level.next]
            let index = occurrences.count
            occurrences.append(Occurrence(
                task: task,
                container: level.container?.pathFromRoot,
                scope: level.scope.pathFromRoot,
                parent: level.parent,
                isReadable: level.isReadable
            ))
            if level.isReadable {
                readable[task.id, default: []].append(index)
            }
            if level.path?.isEmpty == true {
                observed[task.id] = index
            }
            levels += Self.followUpLevels(of: task, at: index, in: level)
        }
    }

    /// The levels that hold the follow-up tasks of `task`, the occurrence `index` in `level`, in the order the
    /// stack takes them: the last container first, so that the first one is placed next.
    private static func followUpLevels(of task: Questionnaire.Task, at index: Int, in level: Level) -> [Level] {
        let followUps = task.kind.followUpTasks
        guard !followUps.isEmpty else {
            return []
        }
        // Beneath an occurrence without answers, or a task without a selection, the follow-up tasks occur once
        // without answers.
        let answerless = Level(
            tasks: followUps,
            container: nil,
            scope: level.container ?? level.scope,
            parent: index,
            isReadable: level.isReadable,
            path: nil
        )
        guard let container = level.container else {
            return [answerless]
        }
        var observedOption: Questionnaire.Task.Kind.ChoiceConfig.Option.ID?
        if let path = level.path, path.count >= 2, case .task(task.id) = path[0], case .choiceOption(let optionId) = path[1] {
            observedOption = optionId
        }
        let stored = QuestionnaireResponses.followUpContainers(of: task, in: container)
        var options = stored.map { (id: $0, isReadable: level.isReadable) }
        if let observedOption, !stored.contains(observedOption) {
            // A custom kind's container occurs also while it holds no responses; an unselected option does not.
            let isCustom = if case .custom = task.kind.variant { true } else { false }
            options.append((observedOption, level.isReadable && isCustom))
        }
        let positioned = options.compactMap { option in
            QuestionnaireResponses.followUpContainerIndex(of: option.id, of: task, in: container).map { (option, $0) }
        }
        let ordered = positioned.sorted { $0.1 < $1.1 }.map(\.0)
        let containers = ordered.reversed().map { option in
            let view = container.view(appending: QuestionnaireResponses.ResponsesPath().appending(taskId: task.id).appending(choiceOption: option.id))
            return Level(
                tasks: followUps,
                container: view,
                scope: view,
                parent: index,
                isReadable: option.isReadable,
                path: option.id == observedOption ? level.path.map { Array($0.dropFirst(2)) } : nil
            )
        }
        // Without a container that conditions can read, the occurrence without answers comes first.
        return ordered.isEmpty || (level.isReadable && !ordered.contains(where: \.isReadable)) ? containers + [answerless] : containers
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension QuestionnaireResponses {
    /// The tasks and groups whose enablement depends on itself, computed once for the questionnaire.
    var cyclicConditionNodes: Set<ConditionDependencies.Node> {
        let root = root
        if let cyclic = root.enablementCache.cyclic {
            return cyclic
        }
        let cyclic = ConditionDependencies.cyclicNodes(of: root.questionnaire.sections.flatMap(\.tasks))
        root.enablementCache.cyclic = cyclic
        return cyclic
    }

    /// The placement for conditions evaluated in this container, kept for as long as the responses stay the same.
    var enablementPlacement: EnablementPlacement {
        let root = root
        // Reading the responses lets an observing view re-render on any answer, also when the placement is kept.
        _ = root.responses
        if root.enablementCache.revision != root.revision {
            root.enablementCache.placements = [:]
            root.enablementCache.revision = root.revision
        }
        if let placement = root.enablementCache.placements[pathFromRoot] {
            return placement
        }
        let placement = EnablementPlacement(of: root, observing: pathFromRoot)
        root.enablementCache.placements[pathFromRoot] = placement
        return placement
    }
}
