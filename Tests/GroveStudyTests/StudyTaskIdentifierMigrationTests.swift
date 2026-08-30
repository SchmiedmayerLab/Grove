//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)

// swiftlint:disable file_types_order
import Foundation
import Grove
import GroveHealthKit
import GroveLegacyIdentifiers
@_spi(APISupport)
@_spi(TestingSupport)
import GroveScheduler
@_spi(TestingSupport)
@testable import GroveStudy
@testable import GroveStudyDefinition
import GroveTesting
import SwiftData
import Testing


private actor MigrationTestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample>,
        ofType sampleType: SampleType<Sample>
    ) async -> HealthKitAnchorCommitAction? {
        nil
    }

    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject>,
        ofType sampleType: SampleType<Sample>
    ) async -> HealthKitAnchorCommitAction? {
        nil
    }
}


/// What a participant would lose if the rewrite went wrong.
private struct OutcomeFingerprint: Hashable {
    let id: UUID
    let occurrenceStart: Date
    let completionDate: Date
    let taskId: String
}


/// The task ids and category raw values are primary keys in the scheduler store, and every outcome a
/// participant has ever recorded hangs off a row keyed by them. These tests build a populated store
/// under the pre-Grove identifiers and assert the rewrite is total, atomic, and lossless.
/// A populated store in its pre-Grove shape, plus the outcomes a migration must not lose.
private struct LegacyStore {
    let scheduler: Scheduler
    let studyManager: StudyManager
    let outcomeIds: Set<UUID>
}


// Deliberately an extension on `StudyManagerTests` rather than a suite of its own. Both enroll into
// `StudyManager.studyBundlesDirectory` — a process-wide static that `removeOrphanedStudyBundles()`
// prunes — and `.serialized` only orders tests within a single suite. As two suites they ran
// concurrently and deleted each other's bundles.
extension StudyManagerTests {
    private static let articleComponentId = UUID()
    private static let walkTestComponentId = UUID()

    /// Built per test: an extension cannot carry a stored property or an initialiser.
    private static func makeMigrationBundle() throws -> StudyBundle {
        let definition = StudyDefinition(
            studyRevision: 0,
            metadata: .init(
                id: UUID(),
                title: .init(),
                explanationText: .init(),
                shortExplanationText: .init(),
                participationCriterion: true
            ),
            components: [
                .informational(.init(
                    id: Self.articleComponentId,
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md")
                )),
                .timedWalkingTest(.init(id: Self.walkTestComponentId, test: .sixMinuteWalkTest))
            ],
            componentSchedules: [
                .init(
                    id: UUID(),
                    componentId: Self.articleComponentId,
                    scheduleDefinition: .once(.event(.enrollment)),
                    completionPolicy: .afterStart,
                    notifications: .disabled
                ),
                .init(
                    id: UUID(),
                    componentId: Self.walkTestComponentId,
                    scheduleDefinition: .repeated(.daily(interval: 2, hour: 0, minute: 0)),
                    completionPolicy: .afterStart,
                    notifications: .disabled
                )
            ]
        )
        return try StudyBundle.writeToDisk(
            at: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .studyBundle),
            definition: definition,
            files: [
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"),
                    localization: .init(language: .english, region: .unitedStates),
                    contents: """
                        ---
                        title: Welcome
                        id: 4A6A052E-5FE6-4FFA-92D5-DA605E12E97E
                        ---
                        """
                )
            ]
        )
    }

    /// Rewrites a populated store backwards into the shape a pre-Grove install would have on disk.
    private func makeStoreLookLegacy(in scheduler: Scheduler) throws {
        for task in try scheduler.context.fetch(FetchDescriptor<GroveScheduler.Task>()) {
            if task.id.starts(with: StudyManager.studyComponentTaskIdPrefix) {
                let suffix = task.id.dropFirst(StudyManager.studyComponentTaskIdPrefix.count)
                task.unsafelyUpdateId(to: LegacyStudyTaskIdentifiers.componentTaskPrefix + suffix)
            }
            if let raw = task.category?.rawValue, raw != "questionnaire" {
                task.category = .custom(LegacyStudyTaskIdentifiers.categoryPrefix + raw)
            }
        }
        try scheduler.context.save()
    }

    private func allTasks(in scheduler: Scheduler) throws -> [GroveScheduler.Task] {
        try scheduler.context.fetch(FetchDescriptor<GroveScheduler.Task>())
    }

    private func fingerprints(in scheduler: Scheduler) throws -> Set<OutcomeFingerprint> {
        Set(try scheduler.queryAllOutcomes().map {
            OutcomeFingerprint(id: $0.id, occurrenceStart: $0.occurrence.start, completionDate: $0.completionDate, taskId: $0.task.id)
        })
    }

    /// Enrols, records outcomes, then puts the store back into its pre-Grove shape.
    private func makePopulatedLegacyStore() async throws -> LegacyStore {
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: MigrationTestStandard()) {
            scheduler
            studyManager
        }
        let calendar = Calendar.current
        let enrollmentDate = try #require(calendar.date(byAdding: .day, value: -10, to: calendar.startOfDay(for: .now)))
        try await studyManager.enroll(in: Self.makeMigrationBundle(), enrollmentDate: enrollmentDate)

        let range = enrollmentDate..<(try #require(calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: .now))))
        var outcomeIds: Set<UUID> = []
        for event in try scheduler.queryEvents(for: range) where !event.isCompleted {
            outcomeIds.insert(try event.complete(ignoreCompletionPolicy: true).id)
        }
        try scheduler.context.save()
        #expect(!outcomeIds.isEmpty)

        try makeStoreLookLegacy(in: scheduler)
        return LegacyStore(scheduler: scheduler, studyManager: studyManager, outcomeIds: outcomeIds)
    }

    @Test
    func rewritesEveryTaskIdAndCategory() async throws {
        let store = try await makePopulatedLegacyStore()
        let (scheduler, studyManager) = (store.scheduler, store.studyManager)
        let legacyCount = try allTasks(in: scheduler).count { $0.id.starts(with: LegacyStudyTaskIdentifiers.componentTaskPrefix) }
        #expect(legacyCount > 0)

        #expect(try studyManager.migrateLegacyTaskIdentifiers())

        for task in try allTasks(in: scheduler) {
            #expect(!task.id.starts(with: LegacyStudyTaskIdentifiers.componentTaskPrefix))
            #expect(task.id.starts(with: StudyManager.studyComponentTaskIdPrefix))
            #expect(!(task.category?.rawValue.starts(with: LegacyStudyTaskIdentifiers.categoryPrefix) ?? false))
        }
    }

    /// The whole reason this migration is transactional rather than a loop of saves.
    @Test
    func everyOutcomeSurvivesWithItsTaskStillAttached() async throws {
        let store = try await makePopulatedLegacyStore()
        let (scheduler, studyManager, outcomeIds) = (store.scheduler, store.studyManager, store.outcomeIds)
        let before = try fingerprints(in: scheduler)

        #expect(try studyManager.migrateLegacyTaskIdentifiers())

        let after = try fingerprints(in: scheduler)
        #expect(after.count == before.count)
        #expect(Set(after.map(\.id)) == outcomeIds)
        // Identity, timing and completion are untouched; only the task id is expected to differ.
        for outcome in after {
            let match = try #require(before.first { $0.id == outcome.id })
            #expect(outcome.occurrenceStart == match.occurrenceStart)
            #expect(outcome.completionDate == match.completionDate)
            #expect(outcome.taskId == StudyManager.studyComponentTaskIdPrefix + match.taskId.dropFirst(LegacyStudyTaskIdentifiers.componentTaskPrefix.count))
        }
    }

    @Test
    func isIdempotent() async throws {
        let store = try await makePopulatedLegacyStore()
        let (scheduler, studyManager) = (store.scheduler, store.studyManager)

        #expect(try studyManager.migrateLegacyTaskIdentifiers())
        let afterFirst = try fingerprints(in: scheduler)
        #expect(try studyManager.migrateLegacyTaskIdentifiers() == false)

        #expect(try fingerprints(in: scheduler) == afterFirst)
    }

    @Test
    func aStoreThatWasNeverLegacyIsUntouched() async throws {
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: MigrationTestStandard()) {
            scheduler
            studyManager
        }
        try await studyManager.enroll(in: Self.makeMigrationBundle())
        let before = try allTasks(in: scheduler).map(\.id).sorted()

        #expect(try studyManager.migrateLegacyTaskIdentifiers() == false)

        #expect(try allTasks(in: scheduler).map(\.id).sorted() == before)
    }

    /// `#Unique<Task>([\.nextVersion], [\.id, \.nextVersion])` resolves a save-time conflict by
    /// upserting, which would fold two chains — and their outcomes — into one. Abort instead.
    @Test
    func aCollisionAbortsAndLeavesTheLegacyRowsReadable() async throws {
        let store = try await makePopulatedLegacyStore()
        let (scheduler, studyManager, outcomeIds) = (store.scheduler, store.studyManager, store.outcomeIds)
        // Give one legacy row a migrated twin, the shape an interrupted earlier run would leave behind.
        let victim = try #require(try allTasks(in: scheduler).first { $0.id.starts(with: LegacyStudyTaskIdentifiers.componentTaskPrefix) })
        let collidingId = StudyManager.studyComponentTaskIdPrefix + victim.id.dropFirst(LegacyStudyTaskIdentifiers.componentTaskPrefix.count)
        _ = try scheduler.createOrUpdateTask(id: collidingId, title: "Twin", instructions: "", schedule: .once(at: .now))
        try scheduler.context.save()

        #expect(throws: (any Error).self) {
            try studyManager.migrateLegacyTaskIdentifiers()
        }

        // Rolled back whole: the legacy rows are still there, and no outcome was dropped.
        #expect(try allTasks(in: scheduler).contains { $0.id == victim.id })
        #expect(try Set(fingerprints(in: scheduler).map(\.id)) == outcomeIds)
    }

    /// The orphan sweep is a cascade delete. A legacy row can never match an enrollment, because
    /// `taskIdPrefix(forStudyId:)` only ever emits the current prefix — so sweeping it would take the
    /// participant's outcomes with it.
    @Test
    func theOrphanSweepNeverDeletesUnmigratedRows() async throws {
        let store = try await makePopulatedLegacyStore()
        let (scheduler, studyManager, outcomeIds) = (store.scheduler, store.studyManager, store.outcomeIds)

        try studyManager.removeOrphanedTasks()

        #expect(try allTasks(in: scheduler).contains { $0.id.starts(with: LegacyStudyTaskIdentifiers.componentTaskPrefix) })
        #expect(try Set(fingerprints(in: scheduler).map(\.id)) == outcomeIds)
    }

    /// The prefix carries no vendor name any more, so a bare `studyComponentTask.…` id that a
    /// consuming app minted itself must not be mistaken for ours and swept.
    @Test(arguments: [
        ("studyComponentTask.not-a-uuid.component", false),
        ("studyComponentTask.", false),
        ("com.example.studyComponentTask.\(UUID().uuidString)", false),
        ("studyComponentTask.\(UUID().uuidString).component.schedule", true)
    ])
    func onlyIdsCarryingAStudyUUIDCountAsOurs(id: String, isOurs: Bool) throws {
        let scheduler = Scheduler(persistence: .inMemory)
        withDependencyResolution(standard: MigrationTestStandard()) {
            scheduler
        }
        let task = try scheduler.createOrUpdateTask(id: id, title: "T", instructions: "", schedule: .once(at: .now)).task

        #expect(StudyManager.isStudyComponentTask(task) == isOurs)
    }

    /// `unenroll` is scoped to a single study id, so it may match the legacy prefix too. Without that,
    /// a participant who left a study after a failed migration would keep its tasks forever.
    @Test
    func unenrollingRemovesTasksLeftUnderTheLegacyPrefix() async throws {
        let store = try await makePopulatedLegacyStore()
        let (scheduler, studyManager) = (store.scheduler, store.studyManager)
        #expect(try allTasks(in: scheduler).contains { $0.id.starts(with: LegacyStudyTaskIdentifiers.componentTaskPrefix) })
        let enrollment = try #require(studyManager.studyEnrollments.first)

        try await studyManager.unenroll(from: enrollment)

        #expect(try allTasks(in: scheduler).isEmpty)
    }

    /// The bundles sweep deletes anything not matching an enrollment, and enrollment URLs carry the
    /// new extension — so a bundle whose extension rename failed can never match one. It must be
    /// skipped, not swept: deleting it destroys the study's content with no retry left.
    @Test
    func theBundleSweepSkipsChildrenTheRenameHasNotReached() async throws {
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: MigrationTestStandard()) {
            scheduler
            studyManager
        }
        let strayLegacy = StudyManager.studyBundlesDirectory
            .appendingPathComponent("\(UUID().uuidString).\(LegacyStorage.studyBundleFileExtension)")
        try FileManager.default.createDirectory(at: StudyManager.studyBundlesDirectory, withIntermediateDirectories: true)
        try "unrenamed bundle".write(to: strayLegacy, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: strayLegacy) }

        try studyManager.removeOrphanedStudyBundles()

        #expect(FileManager.default.fileExists(atPath: strayLegacy.path))
    }

    /// Consumers get the new raw values without touching their source, which is the point of routing
    /// everything through `Task.Category` statics rather than string literals.
    @Test
    func theCurrentCategoryValuesCarryNoVendorPrefix() {
        let categories: [GroveScheduler.Task.Category] = [.informational, .timedWalkingTest, .timedRunningTest]
        for category in categories {
            #expect(!category.rawValue.contains("."), "'\(category.rawValue)' still looks namespaced")
            #expect(!category.rawValue.lowercased().contains("spezi"))
            #expect(!category.rawValue.lowercased().contains("grove"))
        }
    }
}
// swiftlint:enable file_types_order

#endif
