//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import class ModelsR4.Questionnaire
import SpeziScheduler
import SpeziStudyDefinition
import SwiftData
import SwiftUI


@available(iOS 18, macOS 15, macCatalyst 18, watchOS 11, visionOS 2, *)
extension StudyManager {
    /// The user-facing action that is associated with a study-related `SpeziScheduler.Task`
    public enum ScheduledTaskAction: Hashable, Codable {
        case presentInformationalStudyComponent(StudyDefinition.InformationalComponent)
        case answerQuestionnaire(StudyDefinition.QuestionnaireComponent)
        case promptTimedWalkingTest(StudyDefinition.TimedWalkingTestComponent)
        case performCustomActiveTask(StudyDefinition.CustomActiveTaskComponent)
    }
}

@available(iOS 18, macOS 15, macCatalyst 18, watchOS 11, visionOS 2, *)
extension Task.Context {
    typealias StudyContextOld = _StudyContextImpl<PersistentIdentifier>
    /// The study-related context of a Task
    public typealias StudyContext = _StudyContextImpl<StudyEnrollment.ID>
    
    
    /// The study-related context of a Task
    ///
    /// - Note: Always use ``StudyContext`` instead of directly referring to this type. It will be removed in a future update.
    public struct _StudyContextImpl<EnrollmentId: Codable & Hashable & Sendable>: Codable, Hashable, Sendable { // swiftlint:disable:this type_name
        /// The identifier of the study to which the Task belongs
        public let studyId: StudyDefinition.ID
        /// The identifier of the study component for which the Task was created
        public let componentId: StudyDefinition.Component.ID
        /// The identifier of the specific study schedule from which the Task was created
        public let scheduleId: StudyDefinition.ComponentSchedule.ID
        /// The enrollment identifier of the ``StudyEnrollment`` this `Task` belongs to.
        public let enrollmentId: EnrollmentId
    }
    
    /// The study to which this Task belongs, and the component for which it was scheduled.
    @Property(coding: .json, storageIdentifier: "studyContext")
    public var studyContext: StudyContext?
    
    @Property(coding: .json, storageIdentifier: "studyContext")
    var studyContextOld: StudyContextOld?
    
    /// The ``StudyManager/ScheduledTaskAction`` associated with the task.
    @Property(coding: .json)
    public var studyScheduledTaskAction: StudyManager.ScheduledTaskAction?
}


@available(iOS 18, macOS 15, macCatalyst 18, watchOS 11, visionOS 2, *)
extension Task.Category {
    /// An informational task, e.g. an article the user should read
    public static let informational = Self.custom("edu.stanford.spezi.SpeziStudy.task.informational")
    
    /// A Timed Walking Test Task
    public static let timedWalkingTest = Self.custom("edu.stanford.spezi.SpeziStudy.task.timedWalkingTest")
    /// A Timed Running Test Task
    public static let timedRunningTest = Self.custom("edu.stanford.spezi.SpeziStudy.task.timedRunningTest")
    
    /// A custom active task.
    public static func customActiveTask(_ activeTask: StudyDefinition.CustomActiveTaskComponent.ActiveTask) -> Self {
        .custom("edu.stanford.spezi.SpeziStudy.task.customActiveTask:\(activeTask.identifier)")
    }
}


@available(iOS 18, macOS 15, macCatalyst 18, watchOS 11, visionOS 2, *)
extension View {
    /// Configures the SpeziStudy-specific task category appearances
    public func injectingCustomTaskCategoryAppearances() -> some View {
        self
            .taskCategoryAppearance(for: .informational, label: "Informational", image: .system("text.rectangle.page"))
            .taskCategoryAppearance(for: .timedWalkingTest, label: "Active Task", image: .system("figure.walk"))
            .taskCategoryAppearance(for: .timedRunningTest, label: "Active Task", image: .system("figure.run"))
    }
}


@available(iOS 18, macOS 15, macCatalyst 18, watchOS 11, visionOS 2, *)
extension SpeziScheduler.Schedule {
    /// Creates a `SpeziScheduler.Schedule` from a `StudyDefinition.ComponentSchedule.ScheduleDefinition.repeated`.
    ///
    /// - parameter other: the study definition schedule element which should be turned into a `Schedule`
    /// - parameter participationStartDate: the date at which the user started to participate in the study.
    ///
    /// - invariant: `other` MUST be a `.repeated` `ScheduleDefinition`, otherwise the function will abort.
    static func fromRepeated( // swiftlint:disable:this function_body_length
        _ other: StudyDefinition.ComponentSchedule.ScheduleDefinition,
        in cal: Calendar,
        participationStartDate: Date
    ) -> Self {
        let addingOffset = { (date: Date, offset: DateComponents) -> Date in
            if let date = cal.date(byAdding: offset, to: date) {
                return date
            } else {
                preconditionFailure("Unable to add offset \(offset) to \(date)")
            }
        }
        switch other {
        case let .repeated(.daily(interval, hour, minute, second), offset):
            return .daily(
                calendar: cal,
                interval: interval,
                hour: hour,
                minute: minute,
                second: second,
                startingAt: addingOffset(participationStartDate, offset),
                end: .never,
                duration: .tillEndOfDay
            )
        case let .repeated(.weekly(interval, weekday, hour, minute, second), offset):
            return .weekly(
                calendar: cal,
                interval: interval,
                weekday: weekday ?? { () -> Locale.Weekday in
                    guard let weekday = cal.dateComponents([.weekday], from: addingOffset(participationStartDate, offset)).weekday else {
                        preconditionFailure("Unable to determine study enrollment weekday")
                    }
                    return cal.weekday(from: weekday)
                }(),
                hour: hour,
                minute: minute,
                second: second,
                startingAt: addingOffset(participationStartDate, offset),
                end: .never,
                duration: .tillEndOfDay
            )
        case let .repeated(.monthly(interval, day, hour, minute, second), offset):
            return .monthly(
                calendar: cal,
                interval: interval,
                day: day ?? cal.component(.day, from: addingOffset(participationStartDate, offset)),
                hour: hour,
                minute: minute,
                second: second,
                startingAt: addingOffset(participationStartDate, offset),
                end: .never,
                duration: .tillEndOfDay
            )
        case .once:
            preconditionFailure("Unexpected input: expected .repeated, got '\(other)'")
        }
    }
}


@available(iOS 16, macOS 13, macCatalyst 16, watchOS 9, visionOS 1, *)
extension Calendar {
    /// Obtains, for a `DateComponents/weekday` value, the corresponding `Locale.Weekday`.
    func weekday(from rawValue: Int) -> Locale.Weekday {
        repeatElement([Locale.Weekday.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday], count: .max)
            .lazy
            .flatMap(\.self)
            .dropFirst(self.firstWeekday - 1)
            .dropFirst(rawValue + self.weekdaySymbols.count - self.firstWeekday)
            // SAFETY: we operate on what is effectively a neverending sequence; there will always be an element
            .first! // swiftlint:disable:this force_unwrapping
    }
}
