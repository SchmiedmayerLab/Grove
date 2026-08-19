//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable type_body_length multiline_function_chains file_types_order identifier_name file_length

#if canImport(Darwin)
import Foundation
import Grove
import GroveHealthKit
import GroveLocalization
@_spi(APISupport)
@_spi(TestingSupport)
import GroveScheduler
@_spi(TestingSupport)
@testable import GroveStudy
@testable import GroveStudyDefinition
import GroveTesting
import Testing


private actor TestStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {
        // ...
    }

    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {
        // ...
    }
}


extension Task.Context {
    @Property var dedupeTestMarker: String?
}


/// An identity-independent projection of an ``Event`` -- everything the app can actually observe about it.
/// Used to assert that a destructive migration leaves the observable event stream unchanged.
private struct EventSnapshot: Hashable {
    let taskId: String
    let occurrenceStart: Date
    let title: String
    let isCompleted: Bool
    let outcomeId: UUID?
    let componentId: UUID?
}


/// An identity-independent projection of an ``Outcome`` -- the user data a migration must never lose or mutate.
private struct OutcomeSnapshot: Hashable {
    let id: UUID
    let occurrenceStart: Date
    let completionDate: Date
    let taskId: String
}


@Suite(.serialized)
@MainActor
final class StudyManagerTests {
    private static let welcomeArticleComponentId = UUID()
    private static let sixMinuteWalkTestComponentId = UUID()
    private static let twelveMinuteRunTestComponentId = UUID()
    
    private let studyBundle: StudyBundle
    
    init() throws {
        let testStudy = StudyDefinition(
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
                    id: Self.welcomeArticleComponentId,
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md")
                )),
                .timedWalkingTest(.init(
                    id: Self.sixMinuteWalkTestComponentId,
                    test: .sixMinuteWalkTest
                )),
                .timedWalkingTest(.init(
                    id: Self.twelveMinuteRunTestComponentId,
                    test: .twelveMinuteRunTest
                ))
            ],
            componentSchedules: [
                .init(
                    id: UUID(),
                    componentId: Self.welcomeArticleComponentId,
                    scheduleDefinition: .once(.event(.enrollment)),
                    completionPolicy: .afterStart,
                    notifications: .disabled
                ),
                .init(
                    id: UUID(),
                    componentId: Self.sixMinuteWalkTestComponentId,
                    scheduleDefinition: .repeated(.daily(interval: 2, hour: 0, minute: 0)),
                    completionPolicy: .afterStart,
                    notifications: .disabled
                ),
                .init(
                    id: UUID(),
                    componentId: Self.twelveMinuteRunTestComponentId,
                    scheduleDefinition: .repeated(.daily(interval: 2, hour: 0, minute: 0), offset: .init(day: 1)),
                    completionPolicy: .afterStart,
                    notifications: .disabled
                )
            ]
        )
        let tmpUrl = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .studyBundle)
        studyBundle = try StudyBundle.writeToDisk(
            at: tmpUrl,
            definition: testStudy,
            files: [
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"),
                    localization: .init(language: .english, region: .unitedStates),
                    contents: """
                        ---
                        title: Welcome to our Study!
                        id: 4A6A052E-5FE6-4FFA-92D5-DA605E12E97E
                        ---
                        """
                ),
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .informationalArticle, filename: "a1", fileExtension: "md"),
                    localization: .init(language: .spanish, region: .unitedStates),
                    contents: """
                        ---
                        title: Bienvenido a nuestro estudio!
                        id: 4A6A052E-5FE6-4FFA-92D5-DA605E12E97E
                        ---
                        """
                )
            ]
        )
    }
    
    
    @Test
    func enrollment() async throws {
        let cal = Calendar.current
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        let next4Weeks = try cal.startOfDay(for: .now)..<#require(cal.date(byAdding: .weekOfYear, value: 4, to: cal.startOfDay(for: .now)))
        #expect(try scheduler.queryAllTasks().isEmpty)
        #expect(try scheduler.queryEvents(for: next4Weeks).isEmpty)
        
        try await studyManager.enroll(in: studyBundle)
        
        #expect(studyManager.studyEnrollments.count == 1)
        let enrollment = try #require(studyManager.studyEnrollments.first)
        #expect(enrollment.studyId == studyBundle.id)
        #expect(enrollment.studyId == studyBundle.studyDefinition.id)
        #expect(try #require(enrollment.studyBundle).studyDefinition == studyBundle.studyDefinition)
        
        #expect(try scheduler.queryAllTasks().count == 3)
        #expect(try scheduler.queryEvents(for: cal.rangeOfDay(for: .now)).mapIntoSet { String(localized: $0.task.title) } == [
            "Welcome to our Study!", "Six-Minute Walk Test"
        ])
        #expect(try scheduler.queryEvents(for: cal.startOfNextDay(for: .now)..<cal.startOfNextDay(for: cal.startOfNextDay(for: .now))).mapIntoSet {
            String(localized: $0.task.title)
        } == ["12-Minute Run Test"])
    }
    
    
    @Test
    func retroactiveEnrollment() async throws {
        let cal = Calendar.current
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        let next4Weeks = try cal.startOfDay(for: .now)..<#require(cal.date(byAdding: .weekOfYear, value: 4, to: cal.startOfDay(for: .now)))
        #expect(try scheduler.queryAllTasks().isEmpty)
        #expect(try scheduler.queryEvents(for: next4Weeks).isEmpty)
        
        try await studyManager.enroll(in: studyBundle, enrollmentDate: cal.startOfPrevDay(for: .now))
        #expect(studyManager.studyEnrollments.count == 1)
        let enrollment = try #require(studyManager.studyEnrollments.first)
        #expect(enrollment.studyId == studyBundle.id)
        #expect(enrollment.studyId == studyBundle.studyDefinition.id)
        #expect(try #require(enrollment.studyBundle).studyDefinition == studyBundle.studyDefinition)
        #expect(try scheduler.queryAllTasks().count == 2)
        #expect(try scheduler.queryEvents(for: cal.rangeOfDay(for: .now)).mapIntoSet { String(localized: $0.task.title) } == [
            "12-Minute Run Test"
        ])
        #expect(try scheduler.queryEvents(for: cal.startOfNextDay(for: .now)..<cal.startOfNextDay(for: cal.startOfNextDay(for: .now))).mapIntoSet {
            String(localized: $0.task.title)
        } == ["Six-Minute Walk Test"])
    }
    
    
    @Test
    func orphanTaskHandling() async throws {
        let allTime = Date.distantPast...Date.distantFuture
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            Scheduler(persistence: .inMemory)
            studyManager
        }
        try await studyManager.enroll(in: studyBundle)
        
        #expect(studyManager.studyEnrollments.count == 1)
        let enrollment = try #require(studyManager.studyEnrollments.first)
        #expect(enrollment.studyId == studyBundle.id)
        #expect(enrollment.studyId == studyBundle.studyDefinition.id)
        #expect(try #require(enrollment.studyBundle).studyDefinition == studyBundle.studyDefinition)
        try #expect(studyManager.scheduler.queryTasks(for: allTime).count == 3)
        studyManager.modelContext.delete(enrollment)
        try #expect(studyManager.scheduler.queryTasks(for: allTime).count == 3)
        try studyManager.removeOrphanedTasks()
        
        try await Swift::Task.sleep(for: .seconds(0.2))
        try #expect(studyManager.scheduler.queryTasks(for: allTime).isEmpty)
    }
    
    
    @Test
    func orphanStudyBundleHandling() async throws {
        let fileManager = FileManager.default
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            Scheduler(persistence: .inMemory)
            studyManager
        }
        try await studyManager.enroll(in: studyBundle)
        
        #expect(studyManager.studyEnrollments.count == 1)
        let enrollment = try #require(studyManager.studyEnrollments.first)
        #expect(enrollment.studyId == studyBundle.id)
        #expect(enrollment.studyId == studyBundle.studyDefinition.id)
        #expect(try #require(enrollment.studyBundle).studyDefinition == studyBundle.studyDefinition)
        #expect(try fileManager.contents(of: StudyManager.studyBundlesDirectory).contains(enrollment.studyBundleUrl))
        studyManager.modelContext.delete(enrollment)
        #expect(try fileManager.contents(of: StudyManager.studyBundlesDirectory).contains(enrollment.studyBundleUrl))
        try studyManager.removeOrphanedTasks() // not what we're testing but important to ensure that the test doesn't crash
        try studyManager.removeOrphanedStudyBundles()
        #expect(try !fileManager.contents(of: StudyManager.studyBundlesDirectory).contains(enrollment.studyBundleUrl))
    }
    
    
    @Test
    func localeMatching() throws {
        #expect(LocalizationKey(language: .english, region: .unitedStates).score(against: Locale(identifier: "en_US"), using: .default) == 1)
        #expect(LocalizationKey(language: .spanish, region: .unitedStates).score(against: Locale(identifier: "es_US"), using: .default) == 1)
        #expect(LocalizationKey(language: .german, region: .unitedStates).score(against: Locale(identifier: "es_US"), using: .default) == 0.75)
    }
    
    
    /// Tests that the StudyManager properly updates itself when the preferred locale changes.
    @Test
    func localeUpdate() async throws {
        let cal = Calendar.current
        let localeEnUS = Locale(identifier: "en_US")
        let localeEsUS = Locale(identifier: "es_US")
        let studyManager = StudyManager(preferredLocale: localeEnUS, persistence: .inMemory)
        let scheduler = Scheduler(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        try await studyManager.enroll(in: studyBundle)
        #expect(studyManager.studyEnrollments.count == 1)
        let enrollment = try #require(studyManager.studyEnrollments.first)
        
        do {
            let tasks = try scheduler.queryAllTasks()
            #expect(tasks.count == 3)
            #expect(tasks.mapIntoSet { String(localized: $0.title) } == [
                "Welcome to our Study!", "Six-Minute Walk Test", "12-Minute Run Test"
            ])
        }
        studyManager.preferredLocale = localeEsUS
        do {
            let tasks = try scheduler.queryAllTasks()
            #expect(tasks.count == 6) // it's doubled bc we now have a new version of every task
            #expect(tasks.mapIntoSet(\.id).count == 3)
            #expect(tasks.mapIntoSet { String(localized: $0.latestVersion.title) }.contains("Bienvenido a nuestro estudio!"))
            // ^ intentionally only looking for the article title, since the other 2 (timed walk test names) are still english; this is a known bug
        }
        let nextYear = try cal.startOfDay(for: .now)..<#require(cal.date(byAdding: .year, value: 1, to: cal.startOfDay(for: .now)))
        do {
            let welcomeEvents = try scheduler.queryEvents(for: nextYear).filter {
                $0.task.id.contains(Self.welcomeArticleComponentId.uuidString)
            }
            #expect(welcomeEvents.count == 1)
            #expect(try !#require(welcomeEvents.first).isCompleted)
            try #require(welcomeEvents.first).complete()
            try await Swift::Task.sleep(for: .seconds(0.2))
            #expect(try scheduler.queryEvents(for: nextYear).filter {
                $0.task.id.contains(Self.welcomeArticleComponentId.uuidString)
            }.count { !$0.isCompleted } == 0)
        }
        studyManager.preferredLocale = localeEnUS
        do {
            let welcomeEvents = try scheduler.queryEvents(for: nextYear).filter {
                $0.task.id.contains(Self.welcomeArticleComponentId.uuidString)
            }
            #expect(welcomeEvents.count { $0.isCompleted } == 1)
            #expect(welcomeEvents.count { !$0.isCompleted } == 0)
        }
        try await studyManager.unenroll(from: enrollment)
    }
    
    
    @Test
    func localeUtils() {
        let locale1 = Locale(language: .english, region: .germany)
        #expect(locale1.language == .english)
        #expect(locale1.region == .germany)
        
        let locale2 = Locale(language: .spanish, region: .antarctica)
        #expect(locale2.language == .spanish)
        #expect(locale2.region == .antarctica)
    }
    
    
    @Test
    func schedules() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = .losAngeles
        let enrollmentDate = try #require(cal.date(from: .init(year: 2025, month: 7, day: 31)))
        #expect(cal.component(.weekday, from: enrollmentDate) == 5)
        
        let schedule1: Schedule = .fromRepeated(
            .repeated(.daily(hour: 0, minute: 0)),
            in: cal,
            participationStartDate: enrollmentDate
        )
        let schedule2: Schedule = .fromRepeated(
            .repeated(.weekly(weekday: nil, hour: 0, minute: 0)),
            in: cal,
            participationStartDate: enrollmentDate
        )
        let schedule3: Schedule = .fromRepeated(
            .repeated(.weekly(weekday: .wednesday, hour: 0, minute: 0)),
            in: cal,
            participationStartDate: enrollmentDate
        )
        let schedule4: Schedule = .fromRepeated(
            .repeated(.monthly(day: nil, hour: 0, minute: 0)),
            in: cal,
            participationStartDate: enrollmentDate
        )
        let schedule5: Schedule = .fromRepeated(
            .repeated(.monthly(day: 2, hour: 0, minute: 0)),
            in: cal,
            participationStartDate: enrollmentDate
        )
        let schedule6: Schedule = .fromRepeated(
            .repeated(.monthly(day: nil, hour: 0, minute: 0), offset: .init(day: 5)),
            in: cal,
            participationStartDate: enrollmentDate
        )
        let nextOccurrence = { (schedule: Schedule) -> Date? in
            schedule.occurrences(in: enrollmentDate.addingTimeInterval(1)..<Date.distantFuture).first { _ in true }?.start
        }
        #expect(try #require(nextOccurrence(schedule1)) == #require(cal.date(from: .init(year: 2025, month: 8, day: 1))))
        #expect(try #require(nextOccurrence(schedule2)) == #require(cal.date(from: .init(year: 2025, month: 8, day: 7))))
        #expect(try #require(nextOccurrence(schedule3)) == #require(cal.date(from: .init(year: 2025, month: 8, day: 6))))
        #expect(try #require(nextOccurrence(schedule4)) == #require(cal.date(from: .init(year: 2025, month: 8, day: 31))))
        #expect(try #require(nextOccurrence(schedule5)) == #require(cal.date(from: .init(year: 2025, month: 8, day: 2))))
        #expect(try #require(nextOccurrence(schedule6)) == #require(cal.date(from: .init(year: 2025, month: 8, day: 5))))
    }
    
    
    @Test
    func taskVersionDeduplication() async throws {
        let cal = Calendar.current
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        try await studyManager.enroll(in: studyBundle)
        let initialTasks = try scheduler.queryAllTasks()
        #expect(initialTasks.count == 3)
        #expect(initialTasks.allSatisfy { $0.previousVersion == nil && $0.nextVersion == nil })
        
        // pick the 12-min run, which has its first occurrence tomorrow (per the test study bundle's `offset: 1 day`).
        // this lets us complete an event in a time window that any of V1/V2/V3 can be responsible for, as long as
        // their `effectiveFrom` dates are still today.
        let v1 = try #require(initialTasks.first { $0.studyContext?.componentId == Self.twelveMinuteRunTestComponentId })
        let originalStudyContext = try #require(v1.studyContext)
        let originalAction = try #require(v1.studyScheduledTaskAction)
        #expect(v1.outcomes.isEmpty)
        
        // we manufacture duplicates by mutating each version's userInfo to add a marker that the next
        // -createOrUpdateTask call won't reproduce. that forces a new version (userInfo differs) while keeping
        // `studyContext` and `studyScheduledTaskAction` equal across versions -- which is exactly the shape that
        // the dedup logic is supposed to merge.
        func createDuplicateVersion(of latest: Task, marker: String, effectiveFrom: Date) throws -> Task {
            latest.unsafelyUpdateContext { context in
                context.dedupeTestMarker = marker
            }
            try scheduler.context.save()
            return try scheduler.createOrUpdateTask(
                id: latest.id,
                title: latest.title,
                instructions: latest.instructions,
                category: latest.category,
                schedule: latest.schedule,
                completionPolicy: latest.completionPolicy,
                scheduleNotifications: latest.scheduleNotifications,
                notificationThread: latest.notificationThread,
                notificationTime: latest.notificationTime,
                tags: latest.tags,
                effectiveFrom: effectiveFrom,
                shadowedOutcomesHandling: .delete,
                with: { context in
                    context.studyContext = originalStudyContext
                    context.studyScheduledTaskAction = originalAction
                }
            ).task
        }
        let v2 = try createDuplicateVersion(of: v1, marker: "marker-v1", effectiveFrom: v1.effectiveFrom.addingTimeInterval(1))
        #expect(v2 != v1)
        #expect(v1.nextVersion == v2)
        #expect(v2.previousVersion == v1)
        let v3 = try createDuplicateVersion(of: v2, marker: "marker-v2", effectiveFrom: v1.effectiveFrom.addingTimeInterval(2))
        #expect(v3 != v2)
        #expect(v2.nextVersion == v3)
        #expect(v3.previousVersion == v2)
        #expect(v3.firstVersion == v1)
        #expect(v1.latestVersion == v3)
        #expect(try scheduler.queryAllTasks().count == 5) // 2 untouched tasks + the 3 versions of the 12-min run
        
        // complete an event on V3 so we have an outcome that the dedup logic must reassign to V1.
        let nextDayRange = cal.rangeOfDay(for: cal.startOfNextDay(for: .now))
        let v3Events = try scheduler.queryEvents(for: v3, in: nextDayRange)
        #expect(v3Events.count == 1)
        let outcome = try #require(v3Events.first).complete(ignoreCompletionPolicy: true)
        let outcomeId = outcome.id
        try scheduler.context.save()
        #expect(v3.outcomes.contains { $0.id == outcomeId })
        #expect(v1.outcomes.isEmpty)
        #expect(v2.outcomes.isEmpty)
        
        try studyManager.fixTaskContextAndDuplicateVersions()
        
        // after the migration: only the 3 original tasks remain (V2 and V3 of the run task got merged into V1),
        // V1's chain is collapsed, and the outcome we created on V3 was reassigned to V1.
        let postTasks = try scheduler.queryAllTasks()
        #expect(postTasks.count == 3)
        let surviving = try #require(postTasks.first { $0.id == v1.id })
        #expect(surviving == v1)
        #expect(surviving.previousVersion == nil)
        #expect(surviving.nextVersion == nil)
        #expect(surviving.outcomes.contains { $0.id == outcomeId })
        #expect(surviving.studyContext == originalStudyContext)
        #expect(surviving.studyScheduledTaskAction == originalAction)
        // the other 2 untouched tasks should still be there in their original single-version state.
        for task in postTasks where task.id != v1.id {
            #expect(task.previousVersion == nil)
            #expect(task.nextVersion == nil)
        }
    }
    
    
    @Test
    func taskContextMigration() async throws {
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        try await studyManager.enroll(in: studyBundle)
        let enrollment = try #require(studyManager.studyEnrollments.first)
        let allTasks = try scheduler.queryAllTasks()
        #expect(allTasks.count == 3)
        
        // capture the original UUID-based study contexts so we can verify the migration restores them.
        let originalContexts: [Task.ID: Task.Context.StudyContext] = allTasks.reduce(into: [:]) { dict, task in
            dict[task.id] = task.studyContext
        }
        #expect(originalContexts.count == 3)
        
        // simulate the legacy on-disk state: rewrite each task so the shared "studyContext" storage slot holds
        // the old `PersistentIdentifier`-keyed encoding rather than the new UUID-keyed one.
        // both @Property declarations target the same storage identifier, so the latter write wins, but the
        // in-memory cache is keyed by property *type*, not storage identifier -- so we explicitly clear the
        // new-format value first to evict it from the cache before populating the old-format one.
        for task in allTasks {
            let originalContext = try #require(originalContexts[task.id])
            task.unsafelyUpdateContext { context in
                context.studyContext = nil
                context.studyContextOld = Task.Context.StudyContextOld(
                    studyId: originalContext.studyId,
                    componentId: originalContext.componentId,
                    scheduleId: originalContext.scheduleId,
                    enrollmentId: enrollment.persistentModelID
                )
            }
            #expect(task.studyContext == nil)
            #expect(task.studyContextOld != nil)
        }
        try scheduler.context.save()
        
        try studyManager.fixTaskContextAndDuplicateVersions()
        
        // after the migration: every task has its UUID-based studyContext set (matching the pre-simulation values),
        // with the legacy enrollment id (PersistentIdentifier) swapped out for the enrollment's UUID id,
        // and the legacy studyContextOld cleared.
        let postTasks = try scheduler.queryAllTasks()
        #expect(postTasks.count == 3)
        for task in postTasks {
            let originalContext = try #require(originalContexts[task.id])
            let newContext = try #require(task.studyContext)
            #expect(task.studyContextOld == nil)
            #expect(newContext.studyId == originalContext.studyId)
            #expect(newContext.componentId == originalContext.componentId)
            #expect(newContext.scheduleId == originalContext.scheduleId)
            #expect(newContext.enrollmentId == enrollment.id)
        }
    }
    
    
    /// Strong end-to-end equivalence test for the destructive dedup migration.
    ///
    /// Builds a realistic production-shaped history: a run of three equal duplicate versions (V1 -> V2 -> V3), each
    /// responsible for, and owning a completed ``Outcome`` for, a distinct occurrence -- exactly the scattered-outcomes
    /// state real users have on-device. It then asserts that running the migration:
    /// - leaves the entire app-observable event stream (`queryEvents`) byte-for-byte identical,
    /// - preserves every `Outcome` (id, occurrence, completion date) with nothing lost or mutated,
    /// - collapses the run task to a single version that owns all consolidated outcomes,
    /// - leaves every other task untouched, and
    /// - is idempotent (a second run changes nothing).
    @Test
    func taskVersionDeduplicationPreservesObservableState() async throws {
        let cal = Calendar.current
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        let enrollmentDate = try #require(cal.date(byAdding: .day, value: -10, to: cal.startOfDay(for: .now)))
        let rangeEnd = try #require(cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: .now)))
        let wideRange = enrollmentDate..<rangeEnd
        try await studyManager.enroll(in: studyBundle, enrollmentDate: enrollmentDate)
        
        func snapshotEvents() throws -> Set<EventSnapshot> {
            Set(try scheduler.queryEvents(for: wideRange).map { event in
                EventSnapshot(
                    taskId: event.task.id,
                    occurrenceStart: event.occurrence.start,
                    title: String(localized: event.task.title),
                    isCompleted: event.isCompleted,
                    outcomeId: event.outcome?.id,
                    componentId: event.task.studyContext?.componentId
                )
            })
        }
        func snapshotOutcomes() throws -> Set<OutcomeSnapshot> {
            Set(try scheduler.queryAllOutcomes().map { outcome in
                OutcomeSnapshot(
                    id: outcome.id,
                    occurrenceStart: outcome.occurrence.start,
                    completionDate: outcome.completionDate,
                    taskId: outcome.task.id
                )
            })
        }
        
        // the recurring 6-minute walk task (daily, interval 2) gives us several occurrences to spread versions/outcomes across.
        let runTask = try #require(try scheduler.queryAllTasks().first { $0.studyContext?.componentId == Self.sixMinuteWalkTestComponentId })
        let runTaskId = runTask.id
        let origContext = try #require(runTask.studyContext)
        let origAction = try #require(runTask.studyScheduledTaskAction)
        let origEffectiveFrom = runTask.firstVersion.effectiveFrom
        
        func runEventsSorted() throws -> [Event] {
            try scheduler.queryEvents(for: wideRange, predicate: #Predicate { $0.id == runTaskId })
        }
        func completeEvent(at start: Date) throws -> Outcome {
            let event = try #require(try runEventsSorted().first { $0.occurrence.start == start })
            let outcome = try event.complete(ignoreCompletionPolicy: true)
            try scheduler.context.save()
            return outcome
        }
        // creates a new version equal to the latest in every observable way, differing only by a non-study userInfo marker
        // (this is exactly the shape the production duplication bug produced, and exactly what the dedup must merge).
        func makeEqualNextVersion(marker: String, effectiveFrom: Date) throws {
            runTask.latestVersion.unsafelyUpdateContext { context in
                context.dedupeTestMarker = marker
            }
            try scheduler.context.save()
            _ = try scheduler.createOrUpdateTask(
                id: runTaskId,
                title: runTask.latestVersion.title,
                instructions: runTask.latestVersion.instructions,
                category: runTask.latestVersion.category,
                schedule: runTask.latestVersion.schedule,
                completionPolicy: runTask.latestVersion.completionPolicy,
                scheduleNotifications: runTask.latestVersion.scheduleNotifications,
                notificationThread: runTask.latestVersion.notificationThread,
                notificationTime: runTask.latestVersion.notificationTime,
                tags: runTask.latestVersion.tags,
                effectiveFrom: effectiveFrom,
                shadowedOutcomesHandling: .delete,
                with: { context in
                    context.studyContext = origContext
                    context.studyScheduledTaskAction = origAction
                }
            )
        }
        
        // capture the first four occurrence start dates (all owned by V1 at this point).
        let occStarts = try runEventsSorted().prefix(4).map(\.occurrence.start)
        try #require(occStarts.count == 4)
        
        // build V1 -> V2 -> V3, completing a distinct occurrence in each version's responsibility window.
        let o1 = try completeEvent(at: occStarts[0]) // owned by V1
        try makeEqualNextVersion(marker: "m1", effectiveFrom: try #require(cal.date(byAdding: .second, value: 1, to: occStarts[0])))
        let o2 = try completeEvent(at: occStarts[1]) // owned by V2
        try makeEqualNextVersion(marker: "m2", effectiveFrom: try #require(cal.date(byAdding: .second, value: 1, to: occStarts[1])))
        let o3 = try completeEvent(at: occStarts[2]) // owned by V3
        // occStarts[3] is intentionally left incomplete, to prove incomplete events also survive unchanged.
        
        // precondition: the three outcomes really are scattered across three distinct version objects.
        let runOutcomes = try scheduler.queryAllOutcomes().filter { $0.task.id == runTaskId }
        try #require(runOutcomes.count == 3)
        try #require(Set(runOutcomes.map { ObjectIdentifier($0.task) }).count == 3)
        try #require(try scheduler.queryAllTasks().filter { $0.id == runTaskId }.count == 3)
        
        let eventsBefore = try snapshotEvents()
        let outcomesBefore = try snapshotOutcomes()
        let orderedEventsBefore = try scheduler.queryEvents(for: wideRange).count
        let totalTasksBefore = try scheduler.queryAllTasks().count
        
        try studyManager.fixTaskContextAndDuplicateVersions()
        
        // 1. the observable event stream is byte-for-byte identical (occurrences, titles, completion, outcome identity).
        #expect(try snapshotEvents() == eventsBefore)
        #expect(try scheduler.queryEvents(for: wideRange).count == orderedEventsBefore)
        // 2. every outcome is preserved exactly -- nothing lost or mutated.
        #expect(try snapshotOutcomes() == outcomesBefore)
        // 3. the run task collapsed to a single version that owns all three (now consolidated) outcomes.
        #expect(try scheduler.queryAllTasks().count == totalTasksBefore - 2)
        let survivors = try scheduler.queryAllTasks().filter { $0.id == runTaskId }
        #expect(survivors.count == 1)
        let surviving = try #require(survivors.first)
        #expect(surviving.previousVersion == nil)
        #expect(surviving.nextVersion == nil)
        #expect(surviving.effectiveFrom == origEffectiveFrom) // responsibility window start unchanged
        let survivingOutcomeIds: Set<UUID> = Set(surviving.outcomes.map(\.id))
        let expectedOutcomeIds: Set<UUID> = [o1.id, o2.id, o3.id]
        #expect(survivingOutcomeIds == expectedOutcomeIds)
        #expect(surviving.studyContext == origContext)
        #expect(surviving.studyScheduledTaskAction == origAction)
        
        // 4. idempotency: a second run is a complete no-op.
        try studyManager.fixTaskContextAndDuplicateVersions()
        #expect(try snapshotEvents() == eventsBefore)
        #expect(try snapshotOutcomes() == outcomesBefore)
        #expect(try scheduler.queryAllTasks().count == totalTasksBefore - 2)
    }
    
    
    /// Guards the other direction: the dedup must NEVER merge versions that genuinely differ (here, by title).
    /// Over-merging would silently delete a version the app still renders distinctly -- i.e. data loss.
    @Test
    func taskVersionDeduplicationKeepsGenuinelyDistinctVersions() async throws {
        let cal = Calendar.current
        let scheduler = Scheduler(persistence: .inMemory)
        let studyManager = StudyManager(persistence: .inMemory)
        withDependencyResolution(standard: TestStandard()) {
            scheduler
            studyManager
        }
        let enrollmentDate = try #require(cal.date(byAdding: .day, value: -4, to: cal.startOfDay(for: .now)))
        let rangeEnd = try #require(cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: .now)))
        let wideRange = enrollmentDate..<rangeEnd
        try await studyManager.enroll(in: studyBundle, enrollmentDate: enrollmentDate)
        
        func snapshotEvents() throws -> Set<EventSnapshot> {
            Set(try scheduler.queryEvents(for: wideRange).map { event in
                EventSnapshot(
                    taskId: event.task.id,
                    occurrenceStart: event.occurrence.start,
                    title: String(localized: event.task.title),
                    isCompleted: event.isCompleted,
                    outcomeId: event.outcome?.id,
                    componentId: event.task.studyContext?.componentId
                )
            })
        }
        
        let runTask = try #require(try scheduler.queryAllTasks().first { $0.studyContext?.componentId == Self.sixMinuteWalkTestComponentId })
        let runTaskId = runTask.id
        let origContext = try #require(runTask.studyContext)
        let origAction = try #require(runTask.studyScheduledTaskAction)
        
        // V2 differs from V1 by an observable property (title) -> subsumes() must return false -> no merge.
        _ = try scheduler.createOrUpdateTask(
            id: runTaskId,
            title: "A Genuinely Different Title",
            instructions: runTask.instructions,
            category: runTask.category,
            schedule: runTask.schedule,
            completionPolicy: runTask.completionPolicy,
            scheduleNotifications: runTask.scheduleNotifications,
            notificationThread: runTask.notificationThread,
            notificationTime: runTask.notificationTime,
            tags: runTask.tags,
            effectiveFrom: try #require(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))),
            shadowedOutcomesHandling: .delete,
            with: { context in
                context.studyContext = origContext
                context.studyScheduledTaskAction = origAction
            }
        )
        try #require(try scheduler.queryAllTasks().filter { $0.id == runTaskId }.count == 2)
        
        let eventsBefore = try snapshotEvents()
        let totalTasksBefore = try scheduler.queryAllTasks().count
        
        try studyManager.fixTaskContextAndDuplicateVersions()
        
        // nothing merged, nothing deleted, observable stream unchanged (V1's window keeps its title, V2's window keeps the new one).
        #expect(try scheduler.queryAllTasks().count == totalTasksBefore)
        #expect(try scheduler.queryAllTasks().filter { $0.id == runTaskId }.count == 2)
        #expect(try snapshotEvents() == eventsBefore)
    }
    
    
    deinit {
        try? FileManager.default.removeItem(at: studyBundle.bundleUrl)
        try? FileManager.default.removeItem(at: StudyManager.studyBundlesDirectory)
    }
}
#endif
