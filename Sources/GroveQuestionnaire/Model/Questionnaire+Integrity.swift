//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire {
    /// A structural problem that makes a questionnaire's identifiers ambiguous.
    public enum IntegrityError: Error, Hashable, CustomStringConvertible, Sendable {
        /// Two sections share an identifier.
        case duplicateSection(id: String)
        /// A group shares an identifier with another group or with a section.
        case duplicateGroup(id: String)
        /// A task shares an identifier with another task, a group, or a section.
        case duplicateTask(id: String)

        public var description: String {
            switch self {
            case .duplicateSection(let id):
                "Multiple sections for id '\(id)'"
            case .duplicateGroup(let id):
                "Multiple items for group id '\(id)'"
            case .duplicateTask(let id):
                "Multiple tasks for id '\(id)'"
            }
        }
    }

    /// Every task in the questionnaire, follow-ups included, in questionnaire order.
    var allTasks: [Task] {
        func tasks(of task: Task) -> [Task] {
            [task] + task.kind.followUpTasks.flatMap(tasks(of:))
        }
        return sections.flatMap { $0.tasks.flatMap(tasks(of:)) }
    }

    /// Every linkId the questionnaire contains: sections, groups, tasks and follow-up tasks.
    var allLinkIDs: Set<String> {
        var ids: Set<String> = []
        for section in sections {
            ids.insert(section.id)
            if let fhirGroupId = section.fhirGroupId {
                ids.insert(fhirGroupId)
            }
        }
        for task in allTasks {
            ids.insert(task.id)
            ids.formUnion(task.groupPath.map(\.id))
        }
        return ids
    }

    /// Sections, groups and tasks are addressed by linkId alike, so they share one namespace
    /// and a collision anywhere makes an identifier ambiguous.
    func validate() throws(IntegrityError) {
        var seen: Set<String> = []
        for section in sections {
            guard seen.insert(section.id).inserted else {
                throw .duplicateSection(id: section.id)
            }
        }
        let tasks = allTasks
        // Every task inside a group carries it on its path, so only a group's first sighting is new.
        var groups: Set<String> = []
        for group in tasks.lazy.flatMap(\.groupPath) where groups.insert(group.id).inserted {
            guard seen.insert(group.id).inserted else {
                throw .duplicateGroup(id: group.id)
            }
        }
        for task in tasks {
            guard seen.insert(task.id).inserted else {
                throw .duplicateTask(id: task.id)
            }
        }
    }
}
