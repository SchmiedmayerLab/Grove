//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers
@_spi(APISupport)
import GroveScheduler
import SwiftData


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    /// Whether a scheduler task is one this study manager created.
    ///
    /// The prefix no longer carries a vendor name, so the study id has to parse before the orphan
    /// sweep is allowed to delete a row a consuming app might have named `studyComponentTask.…` itself.
    static func isStudyComponentTask(_ task: GroveScheduler.Task) -> Bool {
        guard task.id.starts(with: studyComponentTaskIdPrefix) else {
            return false
        }
        let remainder = task.id.dropFirst(studyComponentTaskIdPrefix.count).prefix(36)
        return UUID(uuidString: String(remainder)) != nil
    }


    /// Rewrites the study-owned rows in the scheduler store to the current identifiers.
    ///
    /// Both the task ids and the category raw values lose the same vendor prefix, so this is one
    /// pass over one fetch. Returns whether anything changed.
    ///
    /// - Important: Runs inside a transaction. On any failure the store is rolled back and the legacy
    ///     rows stay readable, which is always preferable to a half-rewritten store.
    @MainActor
    @_spi(TestingSupport)
    public func migrateLegacyTaskIdentifiers() throws -> Bool {
        let context = try scheduler.context
        // Save first so a rollback can only ever discard this migration's own work.
        try context.save()
        do {
            let changed = try applyLegacyTaskIdentifierMigration(in: context)
            try context.save()
            return changed
        } catch {
            context.rollback()
            throw error
        }
    }

    // Must stay MainActor-isolated and synchronous. An `await` anywhere in here lets another main-actor
    // hop observe — or save — the half-rewritten store, which is the atomicity we depend on.
    @MainActor
    private func applyLegacyTaskIdentifierMigration(in context: ModelContext) throws -> Bool {
        let taskPrefix = LegacyStudyTaskIdentifiers.componentTaskPrefix
        let categoryPrefix = LegacyStudyTaskIdentifiers.categoryPrefix
        let newPrefix = Self.studyComponentTaskIdPrefix

        // One fetch of every version of every task. Categories are filtered in memory because
        // `Task.categoryValue` is private and cannot appear in a `#Predicate`.
        let allTasks = try context.fetch(FetchDescriptor<GroveScheduler.Task>())
        let staleIds = allTasks.filter { $0.id.starts(with: taskPrefix) }
        let staleCategories = allTasks.filter { $0.category?.rawValue.starts(with: categoryPrefix) ?? false }
        guard !staleIds.isEmpty || !staleCategories.isEmpty else {
            return false
        }
        LegacyIdentifierReport.encountered(taskPrefix, in: "GroveStudy")

        // `#Unique<Task>([\.nextVersion], [\.id, \.nextVersion])` resolves a conflict at save time by
        // *upserting*, which would silently fold two task chains — and their outcomes — into one.
        let alreadyMigrated = Set(allTasks.lazy.filter { $0.id.starts(with: newPrefix) }.map(\.id))
        for task in staleIds where alreadyMigrated.contains(newPrefix + task.id.dropFirst(taskPrefix.count)) {
            throw MigrationError(
                message: "Both a legacy and a migrated row exist for '\(task.id)'",
                file: #file,
                line: #line
            )
        }

        for task in staleIds {
            task.unsafelyUpdateId(to: newPrefix + task.id.dropFirst(taskPrefix.count))
        }
        for task in staleCategories {
            guard let raw = task.category?.rawValue else {
                continue
            }
            task.category = .custom(String(raw.dropFirst(categoryPrefix.count)))
        }
        logger.notice("Migrated \(staleIds.count) study task id(s) and \(staleCategories.count) category value(s).")
        return true
    }
}
