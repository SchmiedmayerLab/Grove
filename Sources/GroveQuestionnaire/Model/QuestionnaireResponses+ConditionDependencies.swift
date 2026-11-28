//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The dependencies between the enablement of tasks and groups, as the pair rules derive them to find cycles.
@available(iOS 18, macOS 15, watchOS 11, *)
enum ConditionDependencies {
    typealias Comparison = (operator: Questionnaire.Condition.ComparisonOperator, value: Questionnaire.Condition.Value)

    enum Node: Hashable {
        case task(Questionnaire.Task.ID)
        case group(Questionnaire.Task.Group.ID)
    }

    private struct Frame {
        let node: Node
        let successors: [Node]
        var next = 0
    }

    /// The tasks and groups whose enablement depends on itself, through the tasks their conditions reference,
    /// the groups enclosing a task, and the choice task a follow-up task belongs to.
    ///
    /// As in the pair rules, a condition that cannot be evaluated, such as one with a value of a type the
    /// referenced question's answers do not have, never closes a cycle.
    static func cyclicNodes(of tasks: [Questionnaire.Task]) -> Set<Node> {
        var tasksById: [Questionnaire.Task.ID: Questionnaire.Task] = [:]
        var pending = tasks.map { (task: $0, enclosing: Node?.none) }
        var all: [(task: Questionnaire.Task, enclosing: Node?)] = []
        while let entry = pending.popLast() {
            tasksById[entry.task.id] = entry.task
            all.append(entry)
            pending += entry.task.kind.followUpTasks.map { ($0, Node.task(entry.task.id)) }
        }
        func evaluableReferences(in condition: Questionnaire.Condition) -> [Node] {
            references(in: condition) { taskId, comparison in
                tasksById[taskId].map { isEvaluable(comparison, on: $0) } ?? false
            }.map(Node.task)
        }
        var dependencies: [Node: Set<Node>] = [:]
        for (task, enclosing) in all {
            var outer = enclosing
            for group in task.groupPath {
                dependencies[.group(group.id), default: []].formUnion(evaluableReferences(in: group.condition))
                if let outer {
                    dependencies[.group(group.id), default: []].insert(outer)
                }
                outer = .group(group.id)
            }
            dependencies[.task(task.id), default: []].formUnion(evaluableReferences(in: task.enabledCondition))
            if let outer {
                dependencies[.task(task.id), default: []].insert(outer)
            }
        }
        return stronglyConnected(dependencies)
    }

    /// Whether a reference to `task` can be evaluated: a value comparison needs a value and an operator the
    /// task's answers compare with, as in the pair rules. A custom kind compares every value itself.
    static func isEvaluable(_ comparison: Comparison?, on task: Questionnaire.Task) -> Bool {
        if case .custom = task.kind.variant {
            return true
        }
        guard let comparison else {
            return true
        }
        return ConditionAnswer.compares(comparison.value, withAnswersOf: task)
            && ConditionAnswer.compares(comparison.operator, with: comparison.value)
    }

    /// The task ids a condition references, of the comparisons `includes` accepts; `includes` receives the
    /// operator and value of a value comparison, and `nil` for `hasResponse` and `isMissingResponse`.
    static func references(
        in condition: Questionnaire.Condition,
        where includes: (Questionnaire.Task.ID, Comparison?) -> Bool = { _, _ in true }
    ) -> Set<Questionnaire.Task.ID> {
        var references: Set<Questionnaire.Task.ID> = []
        var pending = [condition]
        while let condition = pending.popLast() {
            switch condition {
            case .not(let inner):
                pending.append(inner)
            case .any(let inner), .all(let inner):
                pending += inner
            case .hasResponse(let taskId), .isMissingResponse(let taskId):
                if includes(taskId, nil) {
                    references.insert(taskId)
                }
            case let .responseValueComparison(taskId, `operator`, value):
                if includes(taskId, (`operator`, value)) {
                    references.insert(taskId)
                }
            case .expression:
                break
            }
        }
        return references
    }

    /// The nodes on a cycle: those in a strongly connected component of more than one node, or with an edge to
    /// themselves. Tarjan's algorithm, with an explicit stack.
    private static func stronglyConnected(_ edges: [Node: Set<Node>]) -> Set<Node> {
        var indices: [Node: Int] = [:]
        var lowLinks: [Node: Int] = [:]
        var stack: [Node] = []
        var onStack: Set<Node> = []
        var cyclic: Set<Node> = []
        for start in edges.keys where indices[start] == nil {
            var work: [Frame] = []
            func open(_ node: Node) {
                indices[node] = indices.count
                lowLinks[node] = indices[node]
                stack.append(node)
                onStack.insert(node)
                work.append(Frame(node: node, successors: Array(edges[node] ?? [])))
            }
            open(start)
            while !work.isEmpty {
                let frame = work[work.count - 1]
                let node = frame.node
                if frame.next < frame.successors.count {
                    work[work.count - 1].next += 1
                    let successor = frame.successors[frame.next]
                    if indices[successor] == nil {
                        open(successor)
                    } else if onStack.contains(successor) {
                        lowLinks[node] = min(lowLinks[node] ?? 0, indices[successor] ?? 0)
                    }
                    continue
                }
                work.removeLast()
                if let caller = work.last?.node {
                    lowLinks[caller] = min(lowLinks[caller] ?? 0, lowLinks[node] ?? 0)
                }
                guard lowLinks[node] == indices[node] else {
                    continue
                }
                var component: [Node] = []
                while let member = stack.popLast() {
                    onStack.remove(member)
                    component.append(member)
                    if member == node {
                        break
                    }
                }
                if component.count > 1 || edges[node]?.contains(node) == true {
                    cyclic.formUnion(component)
                }
            }
        }
        return cyclic
    }
}
