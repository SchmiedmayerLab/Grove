//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

import Algorithms
import Combine
public import Foundation
public import Grove
import GroveFoundation
import GroveHealthKit
import GroveLegacyIdentifiers
import GroveLocalStorage
@_spi(APISupport)
import GroveScheduler
import GroveSchedulerUI
@_documentation(visibility: internal)
@_exported import GroveStudyDefinition
public import SwiftData
import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import class UIKit.UIApplication
#endif


/// Manages enrollment and participation in studies.
///
/// ## Usage
///
/// The ``StudyManager`` module handles enrollment into Studies, and coordinates the scheduling of a study's components.
///
/// ## Topics
///
/// ### Initialization
/// - ``init(preferredLocale:persistence:)``
///
/// ### Study Enrollment
/// - ``enroll(in:enrollmentDate:)``
/// - ``unenroll(from:)``
/// - ``informAboutStudies(_:)``
/// - ``enrollment(withId:)-(StudyEnrollment.ID)``
/// - ``enrollment(withId:)-(PersistentIdentifier)``
/// - ``StudyEnrollment``
/// - ``StudyEnrollmentError``
///
/// ### Instance Properties
/// - ``preferredLocale``
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
public final class StudyManager: Module, EnvironmentAccessible, Sendable {
    /// How the ``StudyManager`` should persist its data.
    public enum PersistenceConfiguration {
        /// The ``StudyManager`` will use an on-disk database for persistence.
        case onDisk
        /// The ``StudyManager`` will use an in-memory database for persistence.
        /// Intended primarily for testing purposes.
        case inMemory
    }
    
    /// Where downloaded study bundles live, in the app's Application Support container.
    nonisolated static let studyBundlesDirectory: URL = {
        StudyStorage.prepareBundlesDirectory()
            ?? URL.temporaryDirectory.appendingPathComponent("StudyBundles", isDirectory: true)
    }()
    
    /// The prefix used for GroveScheduler Tasks created for study component schedules.
    ///
    /// Deliberately carries no vendor name: this is a primary key in the scheduler store, and every
    /// outcome a participant records hangs off a row keyed by it.
    static let studyComponentTaskIdPrefix = "studyComponentTask."
    
    
    // swiftlint:disable attributes
    @Dependency(HealthKit.self) var healthKit
    @Dependency(Scheduler.self) var scheduler
    @Application(\.logger) var logger
    // swiftlint:enable attributes
    
    /// The `Locale` the study manager should use when loading localized elements from a Study Bundle.
    ///
    /// This value affects e.g. the titles used for scheduled tasks and their resulting notifications.
    public var preferredLocale: Locale {
        didSet {
            guard preferredLocale.language != oldValue.language || preferredLocale.region != oldValue.region else {
                return
            }
            handleLocaleUpdate()
        }
    }
    
    #if targetEnvironment(simulator)
    private var autosaveTask: Swift::Task<Void, Never>?
    #endif
    
    let modelContainer: ModelContainer
    
    var modelContext: ModelContext {
        modelContainer.mainContext
    }
    
    private var outcomesObserverToken: AnyObject?
    
    /// All ``StudyEnrollment``s currently registered with the ``StudyManager``.
    public var studyEnrollments: [StudyEnrollment] {
        (try? modelContext.fetch(FetchDescriptor<StudyEnrollment>())) ?? []
    }
    
    /// Creates a new Study Manager, using the specified persistence configuration
    ///
    /// - parameter preferredLocale: The study manager's preferred locale.
    /// - parameter persistence: How the study manager should persist its data, such as enrollments. Defaults to using an on-disk Swift Data store.
    nonisolated public init(
        preferredLocale: Locale = .autoupdatingCurrent,
        persistence: PersistenceConfiguration = .onDisk
    ) {
        self.preferredLocale = preferredLocale
        self.modelContainer = { () -> ModelContainer in
            let schema = Schema([StudyEnrollment.self], version: Schema.Version(0, 0, 2))
            let config: ModelConfiguration
            switch persistence {
            case .onDisk:
                // The sandbox guard this replaced existed only because the store lived in ~/Documents.
                guard let url = StudyStorage.prepareStore() else {
                    fatalError("Could not determine where \(StudyManager.self) should store its data.")
                }
                config = ModelConfiguration("GroveStudy", schema: schema, url: url)
            case .inMemory:
                config = ModelConfiguration("GroveStudy", schema: schema, isStoredInMemoryOnly: true)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }()
    }
    
    
    /// Runs the identifier rewrite before anything reads the scheduler store.
    ///
    /// Synchronous and outside `configure()`'s `Task` block on purpose: that block's `catch` returns
    /// without logging, and the rewrite has to finish before tasks are registered against it.
    private func migrateLegacyTaskIdentifiersIfNeeded() {
        do {
            if try migrateLegacyTaskIdentifiers() {
                // Pending notification requests embed the task id, and their category identifier embeds
                // the category raw value. A refresh tears down every pending request and rebuilds them.
                scheduler.manuallyScheduleNotificationRefresh()
            }
        } catch {
            logger.error("Study identifier migration failed; legacy rows left in place: \(error)")
            assertionFailure("Study identifier migration failed: \(error)")
        }
    }


    @_documentation(visibility: internal)
    public func configure() { // swiftlint:disable:this function_body_length
        migrateLegacyTaskIdentifiersIfNeeded()
        typealias Task = Swift::Task
        Task { @MainActor [self] in
            let enrollments: [StudyEnrollment]
            do {
                enrollments = try modelContext.fetch(FetchDescriptor<StudyEnrollment>())
                try registerStudyTasksWithScheduler(for: enrollments)
                try await setupStudyBackgroundComponents(for: enrollments)
                try removeOrphanedTasks()
                try removeOrphanedStudyBundles()
            } catch {
                return
            }
            #if targetEnvironment(simulator)
            if autosaveTask == nil {
                autosaveTask = Task.detached {
                    while true {
                        await MainActor.run {
                            try? self.modelContext.save()
                        }
                        try? await Task.sleep(for: .seconds(0.25))
                    }
                }
            }
            #endif
            outcomesObserverToken = scheduler.observeNewOutcomes { [weak self] outcome in
                guard let self,
                      let studyContext = outcome.task.studyContext,
                      let studyBundle = self.studyEnrollments.first(where: { $0.studyId == studyContext.studyId })?.studyBundle else {
                    return
                }
                self.handleStudyLifecycleEvent(
                    .completedTask(componentId: studyContext.componentId),
                    for: studyBundle,
                    at: .now
                )
            }
        }
        
        Task { [weak self] in
            let localeUpdates = NotificationCenter.default.notifications(named: NSLocale.currentLocaleDidChangeNotification)
            for await _ in localeUpdates {
                guard let self else {
                    return
                }
                if self.preferredLocale == .autoupdatingCurrent {
                    self.handleLocaleUpdate()
                }
            }
        }
        #if canImport(UIKit) && !os(watchOS)
        Task { [weak self] in
            let timeUpdates = NotificationCenter.default.notifications(named: UIApplication.significantTimeChangeNotification)
            for await _ in timeUpdates {
                guard let self else {
                    return
                }
                self.handleLocaleUpdate()
            }
        }
        #endif
        
        do {
            try fixTaskContextAndDuplicateVersions()
        } catch {
            logger.error("-fixTaskContextAndDuplicateVersions failed: \(error)")
        }
    }
    
    
    @MainActor
    func sinkDidSavePublisher(into consume: @MainActor @escaping (Notification) -> Void) throws -> AnyCancellable {
        NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContainer.mainContext)
            .sink { notification in
                // We use the mainContext. Therefore, the vent will always be called from the main actor
                MainActor.assumeIsolated {
                    consume(notification)
                }
            }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    struct MigrationError: Error {
        let message: String
        let file: StaticString
        let line: UInt
    }
    
    
    /// Applies task fixes and deduplicates them where needed.
    ///
    /// This function does the following:
    /// - Updates all GroveStudy-managed Scheduler Tasks to use `UUID`s instead of `PersistentIdentifier`s
    /// - Merges successive task versions where possible.
    @MainActor
    @_spi(TestingSupport)
    public func fixTaskContextAndDuplicateVersions() throws {
        let context = try scheduler.context
        // we first save the scheduler's context, to ensure that we are operating on a clean slate.
        try context.save()
        do {
            try _fixTaskContextAndDuplicateVersions()
            try context.save()
        } catch {
            // if something goes wrong, we roll back the whole thing
            context.rollback()
            throw error
        }
    }
    
    // NOTE: it's important that this function remain isolated to the MainActor, and not be made async,
    // since that would break the atomicity we currently have in the migration!
    @MainActor
    private func _fixTaskContextAndDuplicateVersions() throws { // swiftlint:disable:this function_body_length cyclomatic_complexity
        func check(_ condition: Bool, _ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) throws {
            if !condition {
                throw StudyManager.MigrationError(
                    message: message(),
                    file: file,
                    line: line
                )
            }
        }
        /// Determines if `fstVersion` subsumes `sndVersion`, i.e., if `sndVersion` can be "merged" into `fstVersion`.
        func subsumes(_ fstVersion: Task, _ sndVersion: Task) -> Bool {
            guard fstVersion.nextVersion == sndVersion,
                  fstVersion.id.starts(with: Self.studyComponentTaskIdPrefix),
                  sndVersion.id.starts(with: Self.studyComponentTaskIdPrefix) else {
                // unreachable in the context of this function.
                return false
            }
            var nonEqualKeyPaths = fstVersion.keyPathsNecessitatingNewTaskVersion(
                title: sndVersion.title,
                instructions: sndVersion.instructions,
                category: sndVersion.category,
                schedule: sndVersion.schedule,
                completionPolicy: sndVersion.completionPolicy,
                scheduleNotifications: sndVersion.scheduleNotifications,
                notificationThread: sndVersion.notificationThread,
                notificationTime: sndVersion.notificationTime,
                tags: sndVersion.tags,
                // NOTE: we're intentionally passing the current task's value in here, bc this would otherwise always cause the whole check to fail.
                effectiveFrom: fstVersion.effectiveFrom,
                with: { context in
                    // set the context to that of the task
                    context = sndVersion[dynamicMember: \.self]
                }
            )
            guard !nonEqualKeyPaths.isEmpty else {
                return true
            }
            if nonEqualKeyPaths.contains(\.userInfo) {
                /// Checks if `fstVersion` and `sndVersion` have equal task context entries, at the specified key paths.
                func equalContext<each Value: Equatable>(_ keyPath: repeat KeyPath<Task, each Value>) -> Bool {
                    for keyPath in repeat each keyPath {
                        let val0 = fstVersion[keyPath: keyPath]
                        let val1 = sndVersion[keyPath: keyPath]
                        if val0 != val1 {
                            return false
                        }
                    }
                    return true
                }
                if equalContext(\.studyContext, \.studyScheduledTaskAction) {
                    nonEqualKeyPaths.remove(\.userInfo)
                }
            }
            // if they are empty, none of the properties are non-equal, and `fstVersion` subsumes `sndVersion`
            return nonEqualKeyPaths.isEmpty
        }
        for enrollment in studyEnrollments {
            guard let studyBundle = enrollment.studyBundle else {
                continue
            }
            let prefix = taskIdPrefix(for: studyBundle)
            var allStudyTasks: [Task] {
                get throws {
                    try scheduler.queryTasks(for: Date.distantPast...Date.distantFuture, predicate: #Predicate<Task> {
                        // we filter for all tasks that are part of this study (determined based on prefix)
                        $0.id.starts(with: prefix)
                    })
                }
            }
            // Step 1: update all tasks to use the correct, UUID-based context
            for task in try allStudyTasks {
                try task.unsafelyUpdateContext { context in
                    switch (context.studyContextOld, context.studyContext) {
                    case (.none, .none), (.none, .some), (.some, .some):
                        break
                    case (.some(let oldStudyContext), .none):
                        try check(self.enrollment(withId: oldStudyContext.enrollmentId) == enrollment, "invalid enrollment")
                        context.studyContextOld = nil // clear it from the cache
                        context.studyContext = .init(
                            studyId: oldStudyContext.studyId,
                            componentId: oldStudyContext.componentId,
                            scheduleId: oldStudyContext.scheduleId,
                            enrollmentId: enrollment.id
                        )
                        try check(context.studyContext != nil, "new context is nil?")
                        try check(context.studyContextOld == nil, "old context not nil?")
                    }
                }
                try check(task.studyContext != nil, "new context is nil?")
                try check(task.studyContextOld == nil, "old context not nil?")
            }
            
            // Step 2: Delete all unnecessary task versions.
            for var currentVersion in try allStudyTasks.mapIntoSet(\.firstVersion) {
                // walk over the chain of task versions
                loop: while let nextVersion = currentVersion.nextVersion {
                    guard subsumes(currentVersion, nextVersion) else {
                        currentVersion = nextVersion
                        continue loop
                    }
                    // `nextVersion` can be subsumed into `currentVersion`.
                    // this means the following:
                    // - we update all Outcomes belonging to `nextVersion` to instead belong to `currentVersion`
                    // - we adjust the task versioning chain, so that `currentVersion.nextVersion == nextVersion.nextVersion`
                    // - we delete `nextVersion`
                    for outcome in Array(nextVersion.outcomes) {
                        outcome.unsafelyReassignTask(to: currentVersion)
                    }
                    let newNextVersion = nextVersion.nextVersion
                    currentVersion.unsafelyUpdateNextVersion(to: nextVersion.nextVersion)
                    nextVersion.unsafelyUpdateNextVersion(to: nil) // technically not required, but we add it to make this explicit.
                    try check(nextVersion.previousVersion == nil, "invalid previousVersion")
                    try check(nextVersion.nextVersion == nil, "invalid nextVersion")
                    try check(nextVersion.outcomes.isEmpty, "still has outcomes")
                    try check(currentVersion.nextVersion != nextVersion, "invalid nextVersion")
                    try check(currentVersion.nextVersion == newNextVersion, "invalid nextVersion")
                    if let newNextVersion {
                        try check(newNextVersion.previousVersion == currentVersion, "invalid previousVersion")
                    }
                    if let newNextVersion = currentVersion.nextVersion {
                        try check(newNextVersion.previousVersion == currentVersion, "invalid previousVersion")
                    }
                    try scheduler.context.delete(nextVersion)
                    // we just subsumed `nextVersion` into `currentVersion`.
                    // this means that we now want to check `currentVersion` again, but this time against the new next version,
                    // so we re-enter the loop **without** updating `currentVersion`.
                }
            }
        }
    }
}


// MARK: Study Participation and Lifecycle Management

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    public enum StudyEnrollmentError: Error, LocalizedError {
        /// The user tried to enroll into a study with revision `X`, but they are already enrolled in revision `Y > X`.
        case alreadyEnrolledInNewerStudyRevision
        /// The user tried to enroll into a study which defines a depdenency on some other study, which the user isn't enrolled in.
        case missingEnrollmentInStudyDependency
        
        public var errorDescription: String? {
            switch self {
            case .alreadyEnrolledInNewerStudyRevision:
                "Already enrolled in a newer version of this study"
            case .missingEnrollmentInStudyDependency:
                "Cannot enroll in this study at this time, because the study has a dependency on another study, which the user is not enrolled in"
            }
        }
    }
    
    private enum TaskCreationError: Error {
        /// Attempted to create a `Task` for a component which cannot be scheduled (eg: a health data collection component)
        case componentNotEligibleForTaskCreation
        /// Asked to create a `Task` for an invalid `ComponentSchedule`, e.g. because the referenced component doesn't exist.
        case unableToFindComponent
    }
    
    
    @MainActor // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func registerStudyTasksWithScheduler(for enrollments: some Collection<StudyEnrollment>) throws {
        for enrollment in enrollments {
            guard let studyBundle = enrollment.studyBundle else {
                continue
            }
            let study = studyBundle.studyDefinition
            /// The IDs of all Tasks belonging to this study we consider to be "active" (i.e., we don't want to delete).
            var activeTaskIds = Set<Task.ID>()
            for schedule in study.componentSchedules {
                guard let component: StudyDefinition.Component = study.component(withId: schedule.componentId) else {
                    // ideally this shouldn't happen, but if it does (we have a schedule but can't resolve the corresponding component),
                    // we simply skip and ignore it.
                    continue
                }
                switch component.kind {
                case .userInteractive:
                    // user-interactive components get scheduled as Scheduler Tasks ...
                    break
                case .internal:
                    // ... but internal components don't
                    continue
                }
                let taskSchedule: GroveScheduler.Schedule
                switch schedule.scheduleDefinition {
                case .once(.event):
                    let taskId = taskId(for: schedule, in: studyBundle)
                    activeTaskIds.insert(taskId)
                    if let task = try scheduler.queryTasks(
                        for: Date.distantPast..<Date.distantFuture,
                        predicate: #Predicate<Task> { $0.id == taskId }
                    ).first?.latestVersion {
                        // there already exists a Task for this event-based schedule,
                        // meaning that the event has already occurred at some point in the past.
                        // since the locale may have changed, we now need to re-register the Task,
                        // in order to get an updated version that is created using the new locale.
                        // Note that we intentionally reuse the old task's schedule here, since it
                        // likely is a Date-based one-time schedule.
                        _ = try createOrUpdateTask(componentSchedule: schedule, enrollment: enrollment, taskSchedule: task.schedule)
                    }
                    continue
                case .once(.date(let dateComponents)):
                    guard let date = preferredLocale.calendar.date(from: dateComponents) else {
                        continue
                    }
                    taskSchedule = .once(at: date, duration: .tillEndOfDay)
                case .repeated:
                    taskSchedule = .fromRepeated(
                        schedule.scheduleDefinition,
                        in: preferredLocale.calendar,
                        participationStartDate: enrollment.enrollmentDate
                    )
                }
                do {
                    let task = try createOrUpdateTask(
                        componentSchedule: schedule,
                        enrollment: enrollment,
                        taskSchedule: taskSchedule
                    )
                    activeTaskIds.insert(task.id)
                } catch TaskCreationError.unableToFindComponent, TaskCreationError.componentNotEligibleForTaskCreation {
                    continue
                } catch {
                    throw error
                }
            }
            let prefix = taskIdPrefix(for: studyBundle)
            let orphanedTasks = (try? scheduler.queryTasks(for: Date.distantPast...Date.distantFuture, predicate: #Predicate<Task> {
                // we filter for all tasks that are part of this study (determined based on prefix),
                // and are not among the tasks we just scheduled.
                // any task that exists in the scheduler and does not fulfill these criteria is a task that must have been scheduled
                // for a previous revision of the study, and belongs to a component that no longer exists
                $0.id.starts(with: prefix) && !activeTaskIds.contains($0.id)
            })) ?? []
            for orphanedTask in orphanedTasks {
                logger.notice("Deleting orphaned Task for study '\(study.metadata.title[.enUS] ?? "")' (\(study.id)): \(orphanedTask)")
                try scheduler.deleteAllVersions(of: orphanedTask)
            }
        }
        try modelContext.save()
        try scheduler.context.save()
    }
    
    
    /// Creates (or updates) a `Task` for a study component, based on a schedule.
    @MainActor
    private func createOrUpdateTask( // swiftlint:disable:this function_body_length
        componentSchedule: StudyDefinition.ComponentSchedule,
        enrollment: StudyEnrollment,
        taskSchedule: GroveScheduler.Schedule
    ) throws -> Task {
        guard let studyBundle = enrollment.studyBundle,
              let component = studyBundle.studyDefinition.component(withId: componentSchedule.componentId) else {
            throw TaskCreationError.unableToFindComponent
        }
        let category: Task.Category?
        let action: ScheduledTaskAction?
        switch component {
        case .questionnaire(let component):
            category = .questionnaire
            action = .answerQuestionnaire(component)
        case .informational(let component):
            category = .informational
            action = .presentInformationalStudyComponent(component)
        case .timedWalkingTest(let component):
            category = switch component.test.kind {
            case .walking: .timedWalkingTest
            case .running: .timedRunningTest
            }
            action = .promptTimedWalkingTest(component)
        case .customActiveTask(let component):
            category = .customActiveTask(component.activeTask)
            action = .performCustomActiveTask(component)
        case .healthDataCollection:
            throw TaskCreationError.componentNotEligibleForTaskCreation
        }
        return try scheduler.createOrUpdateTask(
            id: taskId(for: componentSchedule, in: studyBundle),
            title: studyBundle.displayTitle(for: component, in: preferredLocale).map { "\($0)" } ?? "",
            instructions: studyBundle.displaySubtitle(for: component, in: preferredLocale).map { "\($0)" } ?? "",
            category: category,
            schedule: taskSchedule,
            completionPolicy: componentSchedule.completionPolicy,
            scheduleNotifications: {
                switch componentSchedule.notifications {
                case .disabled: false
                case .enabled: true
                }
            }(),
            notificationThread: componentSchedule.notifications.thread,
            notificationTime: componentSchedule.notifications.time,
            tags: nil,
            effectiveFrom: .now,
            shadowedOutcomesHandling: .delete,
            with: { context in
                context.studyContext = .init(
                    studyId: studyBundle.studyDefinition.id,
                    componentId: component.id,
                    scheduleId: componentSchedule.id,
                    enrollmentId: enrollment.id
                )
                context.studyScheduledTaskAction = action
            }
        ).task
    }
    
    private func taskIdPrefix(for studyBundle: StudyBundle) -> String {
        taskIdPrefix(forStudyId: studyBundle.id)
    }
    
    private func taskIdPrefix(forStudyId studyId: StudyBundle.ID) -> String {
        Self.studyComponentTaskIdPrefix + studyId.uuidString
    }
    
    private func taskId(for schedule: StudyDefinition.ComponentSchedule, in studyBundle: StudyBundle) -> String {
        "\(taskIdPrefix(for: studyBundle)).\(schedule.componentId).\(schedule.id)"
    }
    
    // MARK: Study Enrollment
    
    /// Enroll in a study.
    ///
    /// Once the device is enrolled into a study at revision `X`, subsequent ``enroll(in:enrollmentDate:)`` calls for the same study, with revision `Y`, will:
    /// - if `X = Y`: have no effect;
    /// - if `X < Y`: update the study enrollment, as if ``informAboutStudies(_:)`` was called with the new study revision;
    /// - if `X > Y`: throw an error.
    ///
    /// - parameter studyBundle: The `StudyBundle` to enroll into.
    /// - parameter enrollmentDate: The `Date` relative to which the enrollment should be registered.
    ///     This defaults to the current date, but you can override this to specify a date in the past if you re-enroll a user which was already enrolled before.
    @MainActor
    public func enroll(in studyBundle: StudyBundle, enrollmentDate: Date = .now) async throws {
        let study = studyBundle.studyDefinition
        // big issue in this function is that, if we throw somewhere we kinda need to unroll _all_ the changes we've made so far
        // (which is much easier said than done...)
        let enrollments = try modelContext.fetch(FetchDescriptor<StudyEnrollment>())
        
        if case let existingEnrollments = enrollments.filter({ $0.studyId == studyBundle.id }),
           !existingEnrollments.isEmpty {
            // There exists at least one enrollment for this study
            if let enrollment = existingEnrollments.first, existingEnrollments.count == 1 {
                if enrollment.studyRevision == study.studyRevision {
                    // already enrolled in this study, at this revision.
                    // this is a no-op.
                    logger.notice("Ignoring enrollment request bc we're already enrolled, at this revision.")
                    return
                } else if enrollment.studyRevision < study.studyRevision {
                    // if we have only one enrollment, and it is for an older version of the study,
                    // we treat the enroll call as a study definition update
                    logger.notice("Already enrolled in older version of the study; fwd'ing to -informAboutStudies.")
                    try await informAboutStudies(CollectionOfOne(studyBundle))
                    return
                } else {
                    // enrollment.studyRevision > study.studyRevision
                    // trying to enroll into an older version of the study.
                    throw StudyEnrollmentError.alreadyEnrolledInNewerStudyRevision
                }
            }
            throw StudyEnrollmentError.alreadyEnrolledInNewerStudyRevision
        }
        
        if let dependency = study.metadata.studyDependency {
            guard enrollments.contains(where: { $0.studyId == dependency }) else {
                throw StudyEnrollmentError.missingEnrollmentInStudyDependency
            }
        }
        
        let enrollment = try StudyEnrollment(enrollmentDate: enrollmentDate, studyBundle: studyBundle)
        modelContext.insert(enrollment)
        try modelContext.save()
        try registerStudyTasksWithScheduler(for: CollectionOfOne(enrollment))
        // intentionally doing this before the background component setup, since that call is async and might take several seconds to return
        // (bc of the HealthKit permissions)
        if preferredLocale.calendar.isDateInToday(enrollmentDate) {
            // if we enrolled for the current day, we trigger the enrollment-event-based component scheduled.
            // we intentionally skip this if the enrollment is for a different date.
            handleStudyLifecycleEvent(.enrollment, for: studyBundle, at: enrollmentDate)
        }
        handleStudyLifecycleEvent(.activation, for: studyBundle, at: .now)
        try await setupStudyBackgroundComponents(for: CollectionOfOne(enrollment))
    }
    
    
    /// Unenroll from a study.
    public func unenroll(from enrollment: StudyEnrollment) async throws {
        logger.notice("Unenrolling from study '\(enrollment.studyId)' (\(enrollment.studyBundle?.studyDefinition.metadata.title[.enUS] ?? ""))")
        do {
            // Delete all Tasks associated with this study.
            // Note that we do this by simply fetching & deleting all Tasks with a matching prefix,
            // instead of going (based on the study components) through all component ids and deleting the tasks based on that.
            // the reason being that we might be deleting an enrollment w/ an old study schema, which we can't necessarily trivially decode.
            let studyTaskPrefix = taskIdPrefix(forStudyId: enrollment.studyId)
            // Scoped to this one study, so matching the legacy prefix too is safe -- and stops a failed
            // migration from stranding the study's tasks after the participant has left it.
            let legacyTaskPrefix = LegacyStudyTaskIdentifiers.componentTaskPrefix + enrollment.studyId.uuidString
            let tasks = try scheduler.queryTasks(for: Date.distantPast...Date.distantFuture, predicate: #Predicate {
                $0.id.starts(with: studyTaskPrefix) || $0.id.starts(with: legacyTaskPrefix)
            })
            for task in tasks {
                try scheduler.deleteAllVersions(of: task)
            }
        }
        let studyBundleUrl = enrollment.studyBundleUrl
        await tearDownStudyBackgroundComponents(for: CollectionOfOne(enrollment))
        modelContext.delete(enrollment)
        try? FileManager.default.removeItem(at: studyBundleUrl)
        try modelContext.save()
    }
    
    
    /// Fetches the ``StudyEnrollment`` for the specified ``StudyEnrollment/ID``.
    public func enrollment(withId id: StudyEnrollment.ID) -> StudyEnrollment? {
        let enrollments = (try? modelContext.fetch(FetchDescriptor(predicate: #Predicate<StudyEnrollment> {
            $0.id == id
        }))) ?? []
        return enrollments.first
    }
    
    /// Fetches the ``StudyEnrollment`` for the specified `PersistentIdentifier`.
    public func enrollment(withId id: PersistentIdentifier) -> StudyEnrollment? {
        // for some reason, simply doing `modelContext.registeredModel(for: id)` doesn't work...
        let enrollments = (try? modelContext.fetch(FetchDescriptor(predicate: #Predicate<StudyEnrollment> {
            $0.persistentModelID == id
        }))) ?? []
        return enrollments.first
    }
    
    
    /// Removes all GroveScheduler Tasks which are in the GroveStudy domain (based on the task id's prefix), but for which we don't have any matching study enrollments.
    @_spi(TestingSupport)
    public func removeOrphanedTasks() throws {
        let activeStudyIds = try modelContext.fetch(FetchDescriptor<StudyEnrollment>()).mapIntoSet(\.studyId)
        // Note: it sadly seems like we can't use a #Predicate to filter through SwiftData here. (doing so will simply crash the app...)
        let allTasks = try scheduler.queryTasks(for: Date.distantPast...Date.distantFuture)
        if allTasks.contains(where: { $0.id.starts(with: LegacyStudyTaskIdentifiers.componentTaskPrefix) }) {
            // Deleting these would cascade into their outcomes, and they can never match an enrollment
            // because `taskIdPrefix(forStudyId:)` only ever emits the current prefix. Skipping them is
            // the deliberate choice, so this logs rather than trapping -- the migration itself already
            // asserts when it fails, which is where an actual defect shows up.
            logger.error("Study tasks under the pre-Grove prefix survived the migration. Skipping them to protect their outcomes.")
        }
        let orphanedTasks = allTasks.filter { task in
            // fetch all tasks which are in the GroveStudy domain, but don't match one of the currently-enrolled-in studies.
            Self.isStudyComponentTask(task) && !activeStudyIds.contains { task.id.starts(with: taskIdPrefix(forStudyId: $0)) }
        }
        for task in orphanedTasks {
            logger.notice("Found orphaned task in GroveStudy domain which doesn't match any current enrollment: '\(task.id)'. Will delete.")
            try scheduler.deleteAllVersions(of: task)
        }
    }
    
    /// Removes all entries in the ``StudyManager/studyBundlesDirectory`` which do not correspond to one of the current study enrollments.
    @_spi(TestingSupport)
    public func removeOrphanedStudyBundles() throws {
        let fm = FileManager.default // swiftlint:disable:this identifier_name
        let allStudyEnrollments = self.studyEnrollments
        let allStudyBundleUrls = (try? fm.contents(of: Self.studyBundlesDirectory)) ?? []
        let orphanedBundleUrls = allStudyBundleUrls.filter { url in
            !allStudyEnrollments.contains { $0.studyBundleUrl.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
        }
        guard !orphanedBundleUrls.isEmpty else {
            return // nothing to do
        }
        logger.notice("Found \(orphanedBundleUrls.count) orphaned study bundle(s). Will remove.")
        for url in orphanedBundleUrls {
            try fm.removeItem(at: url)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    private struct StudyCollectedSampleTypes {
        var required: [any AnySampleType] = []
        var optional: [any AnySampleType] = []
        
        var combined: some Sequence<any AnySampleType> {
            chain(required, optional)
        }
    }
    
    @MainActor
    private func setupStudyBackgroundComponents(for enrollments: some Collection<StudyEnrollment>) async throws {
        try await startBackgroundHealthDataCollection(for: enrollments)
    }
    
    @MainActor
    private func tearDownStudyBackgroundComponents(for enrollments: some Collection<StudyEnrollment>) async {
        await stopBackgroundHealthDataCollection(for: enrollments)
    }
    
    
    private func allCollectedSampleTypes(in enrollments: some Collection<StudyEnrollment>) -> StudyCollectedSampleTypes {
        enrollments.reduce(into: .init()) { sampleTypes, enrollment in
            guard let healthCollectionComponents = enrollment.studyBundle?.studyDefinition.healthDataCollectionComponents else {
                return
            }
            for component in healthCollectionComponents {
                sampleTypes.required.append(contentsOf: component.sampleTypes)
                sampleTypes.optional.append(contentsOf: component.optionalSampleTypes)
            }
        }
    }
    
    @MainActor
    private func startBackgroundHealthDataCollection(for enrollments: some Collection<StudyEnrollment>) async throws {
        func imp<Sample>(_ sampleType: some AnySampleType<Sample>) async {
            let sampleType = SampleType(sampleType)
            await healthKit.addHealthDataCollector(CollectSamples(
                sampleType,
                start: .automatic,
                continueInBackground: true
            ))
        }
        let collectedSampleTypes = allCollectedSampleTypes(in: enrollments)
        for sampleType in collectedSampleTypes.required {
            await imp(sampleType)
        }
        for sampleType in collectedSampleTypes.optional {
            // optional types only get registered for collection if they are already authorized.
            if await healthKit.didAskForAuthorization(toRead: [sampleType]) { // swiftlint:disable:this for_where
                await imp(sampleType)
            }
        }
        // we want to request HealthKit auth once, at the end, for everything we just registered.
        try await healthKit.askForAuthorization()
    }
    
    @MainActor
    private func stopBackgroundHealthDataCollection(for enrollments: some Collection<StudyEnrollment>) async {
        func imp<Sample>(_ sampleType: some AnySampleType<Sample>) async {
            let sampleType = SampleType(sampleType)
            await healthKit.resetSampleCollection(for: sampleType)
        }
        for sampleType in allCollectedSampleTypes(in: enrollments).combined {
            await imp(sampleType)
        }
    }
    
    /// Updates the health data collection for all currently enrolled studies.
    ///
    /// For required sample types within a study, this does nothing if the sample types are already being collected.
    /// For optional sample types within a study, this will start collection if the sample type currently is authorized.
    ///
    /// If your study does not define any optional health data collection, this function need not be called by your app.
    @MainActor
    public func updateHealthDataCollection() async throws {
        try await startBackgroundHealthDataCollection(for: studyEnrollments)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    private func handleLocaleUpdate() {
        try? registerStudyTasksWithScheduler(for: studyEnrollments)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    /// Informs the Study Manager about current study definitions.
    ///
    /// Ths study manager will use these definitions to determine whether it needs to update any of the study participation contexts ic currently manages.
    public func informAboutStudies(_ studyBundles: some Collection<StudyBundle>) async throws {
        for studyBundle in studyBundles {
            let studyId = studyBundle.studyDefinition.id
            let studyRevision = studyBundle.studyDefinition.studyRevision
            for enrollment in try modelContext.fetch(FetchDescriptor(predicate: #Predicate<StudyEnrollment> {
                $0.studyId == studyId && $0.studyRevision < studyRevision
            })) {
                try enrollment.updateStudyBundle(studyBundle)
                try registerStudyTasksWithScheduler(for: CollectionOfOne(enrollment))
                try await setupStudyBackgroundComponents(for: CollectionOfOne(enrollment))
            }
        }
    }
}


// MARK: Event-Based Scheduling

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyManager {
    private func handleStudyLifecycleEvent(_ event: StudyLifecycleEvent, for studyBundle: StudyBundle, at date: Date) {
        logger.notice(
            "Handling study lifecycle event '\(String(describing: event))' for study \(studyBundle.id) (\(studyBundle.studyDefinition.metadata.title[.enUS] ?? ""))"
        )
        let cal = preferredLocale.calendar
        for enrollment in studyEnrollments where enrollment.studyId == studyBundle.id {
            guard let studyBundle = enrollment.studyBundle else {
                continue
            }
            for schedule in studyBundle.studyDefinition.componentSchedules {
                switch schedule.scheduleDefinition {
                case .repeated, .once(.date):
                    continue
                case let .once(.event(lifecycleEvent, offsetInDays, time)):
                    guard lifecycleEvent == event else {
                        continue
                    }
                    guard let occurrenceDate = cal
                        .date(byAdding: .day, value: offsetInDays, to: date)
                        .flatMap({ date in
                            time.flatMap { cal.date(bySettingHour: $0.hour, minute: $0.minute, second: $0.second, of: date) } ?? date
                        }) else {
                        logger.error("Unable to compute occurrence date. Skipping \(schedule.scheduleDefinition)")
                        continue
                    }
                    do {
                        _ = try createOrUpdateTask(
                            componentSchedule: schedule,
                            enrollment: enrollment,
                            taskSchedule: .once(at: occurrenceDate)
                        )
                    } catch TaskCreationError.unableToFindComponent, TaskCreationError.componentNotEligibleForTaskCreation {
                        continue
                    } catch {
                        logger.error("Error creating task: \(error)")
                    }
                }
            }
        }
    }
}
