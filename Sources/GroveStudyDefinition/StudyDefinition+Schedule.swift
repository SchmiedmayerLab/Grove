//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import GroveFoundation
public import enum GroveScheduler.AllowedCompletionPolicy
public import enum GroveScheduler.NotificationThread
public import struct GroveScheduler.NotificationTime


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// A schedule, defining when a specific ``Component`` should get activated.
    ///
    /// A component schedule associates a ``Component`` (identified via its unique ``Component/id``) with a ``ScheduleDefinition-swift.enum``.
    ///
    /// When enrolling into a study, GroveStudy's [`StudyManager`](../GroveStudy/GroveStudy.docc/GroveStudy.md)
    /// will process the ``StudyDefinition``'s schedules into [GroveScheduler](../GroveScheduler/GroveScheduler.docc/GroveScheduler.md)
    /// [`Task`](../GroveScheduler/GroveScheduler.docc/GroveScheduler.md)s, `Event`s for which can then be queried by an app and displayed to a user.
    ///
    /// A ``StudyDefinition`` may not contain multiple schedules for the same component.
    ///
    /// - Note: These schedules only apply to user-interactive ``Component``s (e.g.: ``QuestionnaireComponent`` or ``InformationalComponent``).
    ///     Non-user-interactive components (e.g.: ``HealthDataCollectionComponent``) are always implicitly activated upon enrollment, and are active for the entire duration of the participant's enrollment in the study.
    ///
    /// ## Topics
    ///
    /// ### Initializers
    /// - ``init(id:componentId:scheduleDefinition:completionPolicy:notifications:)``
    ///
    /// ### Instance Properties
    /// - ``componentId``
    /// - ``scheduleDefinition-swift.property``
    /// - ``completionPolicy``
    ///
    /// ### Other
    /// - ``ScheduleDefinition-swift.enum``
    public struct ComponentSchedule: StudyDefinitionElement, Identifiable {
        /// Time Components
        public struct Time: Hashable, Codable, Sendable, CustomStringConvertible {
            /// Midnight
            @inlinable public static var midnight: Self {
                Time(hour: 0, minute: 0, second: 0)
            }

            /// Noon
            @inlinable public static var noon: Self {
                Time(hour: 12, minute: 0, second: 0)
            }

            /// The hour
            public let hour: Int
            /// The minute
            public let minute: Int
            /// The second
            public let second: Int

            public var description: String {
                if second == 0 {
                    String(format: "%02lld:%02lld", hour, minute)
                } else {
                    String(format: "%02lld:%02lld:%02lld", hour, minute, second)
                }
            }

            /// Creates a new `Time` object.
            public init(hour: Int, minute: Int = 0, second: Int = 0) {
                self.hour = hour
                self.minute = minute
                self.second = second
                precondition((0...24).contains(hour), "Invalid hour value")
                precondition((0...60).contains(hour), "Invalid minute value")
                precondition((0...60).contains(hour), "Invalid second value")
            }
        }

        /// A schedule, defining when a ``Component`` should be activated.
        ///
        /// ## Topics
        ///
        /// ### Schedule Kinds
        /// - ``once(_:)``
        /// - ``repeated(_:offset:)``
        ///
        /// ### Supporting Types
        /// - ``RepetitionPattern``
        public enum ScheduleDefinition: StudyDefinitionElement {
            /// A schedule that should not repeat on its own.
            ///
            /// Note that `once` schedules only run "once" in the sense that they are not inherently repetitive.
            /// Depending on its specific ``OneTimeSchedule``, a `once` schedule can get scheduled multiple times, but every time it is scheduled, it only gets triggered once.
            case once(OneTimeSchedule)

            /// A schedule that will run multiple times, based on a repetition pattern (e.g.: weekly).
            ///
            /// This case defines a schedule which will activate repeatedly, based on a repetition pattern.
            /// - parameter pattern: The pattern based on which the schedule should repeat itself.
            /// - parameter offset: The offsetbetween the participant's enrollment into the study and the first time the schedule should take effect.
            case repeated(_ pattern: RepetitionPattern, offset: DateComponents = .init())

            public enum OneTimeSchedule: StudyDefinitionElement { // swiftlint:disable:this nesting
                /// A schedule that should run only once, at a specific date in the user's time zone.
                case date(DateComponents) // DateComponents bc we need it to be TimeZone independent...
                /// A schedule that should run only once, in response to an event within the study's lifecycle.
                ///
                /// For example, the following definition schedules a component to occur at 9 AM, 2 days after the user enrolled in the study:
                /// ```swift
                /// let schedule: ScheduleDefinition = .once(.event(.enrollment), offsetInDays: 2, time: .init(hour: 9))
                /// ```
                /// Regardless of whether the participant enrolled before or after 9 AM, the event will trigger on the 2nd day after the enrollment, at 9 AM.
                ///
                /// - parameter event: The event to which the schedule should be anchored.
                /// - parameter offsetInDays: Allows moving the schedule to occur `offsetInDays` after the day on which the event occurred.
                /// - parameter time: The specific time for which the occurrence should be scheduled.
                case event(_ event: StudyLifecycleEvent, offsetInDays: Int = 0, time: Time? = nil)
            }

            /// Pattern defining how a repeating ``StudyDefinition/ComponentSchedule/ScheduleDefinition-swift.enum`` should repeat itself.
            public enum RepetitionPattern: StudyDefinitionElement { // swiftlint:disable:this nesting
                /// A repetition pattern that will take effect daily, at the specified time.
                case daily(interval: Int = 1, hour: Int, minute: Int = 0, second: Int = 0)
                /// A repetition pattern that will take effect weekly, at the specified `weekday` and time.
                /// - parameter weekday: the day of the week at which the schedule should repeat.
                ///     specifying `nil` causes the schedule to repeat weekly relative to the study enrollment date.
                case weekly(interval: Int = 1, weekday: Locale.Weekday?, hour: Int, minute: Int = 0, second: Int = 0)
                // swiftlint:disable:previous enum_case_associated_values_count
                /// A repetition pattern that will take effect monthly, at the specified `day` and time.
                /// - parameter day: the day of the month at which the schedule should repeat.
                ///     specifying `nil` causes the schedule to repeat monthly relative to the study enrollment date.
                case monthly(interval: Int = 1, day: Int?, hour: Int, minute: Int = 0, second: Int = 0)
                // swiftlint:disable:previous enum_case_associated_values_count
            }
        }

        public enum NotificationsConfig: StudyDefinitionElement {
            /// There should not be any notifications for occurrences of this schedule.
            case disabled
            /// There should be notifications for occurrences of this schedule.
            /// - parameter thread: the notification thread used to group the notifications
            case enabled(thread: GroveScheduler.NotificationThread, time: GroveScheduler.NotificationTime? = nil)

            /// The resulting effective notification thread
            public var thread: GroveScheduler.NotificationThread {
                switch self {
                case .disabled: .none
                case .enabled(let thread, time: _): thread
                }
            }

            /// The notification time override, if specified
            public var time: GroveScheduler.NotificationTime? {
                switch self {
                case .disabled: nil
                case .enabled(thread: _, let time): time
                }
            }
        }

        /// This schedule's unique, stable identifier.
        public var id: UUID
        /// The identifier of the component this schedule is referencing
        public var componentId: StudyDefinition.Component.ID
        /// The schedule itself
        public var scheduleDefinition: ScheduleDefinition
        /// Defines when an `Event` scheduled based on this schedule is allowed to be marked as completed.
        public var completionPolicy: GroveScheduler.AllowedCompletionPolicy
        /// Whether notifications should be sent for occurrences of this schedule.
        public var notifications: NotificationsConfig

        /// Creates a new `ComponentSchedule`.
        public init(
            id: UUID,
            componentId: StudyDefinition.Component.ID,
            scheduleDefinition: ScheduleDefinition,
            completionPolicy: GroveScheduler.AllowedCompletionPolicy,
            notifications: NotificationsConfig
        ) {
            self.id = id
            self.componentId = componentId
            self.scheduleDefinition = scheduleDefinition
            self.completionPolicy = completionPolicy
            self.notifications = notifications
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition.ComponentSchedule.ScheduleDefinition: CustomStringConvertible {
    private static let ordinalsFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .ordinal
        return fmt
    }()

    public var description: String {
        func fmtTime(hour: Int, minute: Int, second: Int, omitSecondsIfZero: Bool = true) -> String {
            if omitSecondsIfZero && second == 0 {
                String(format: "%.2d:%.2d", hour, minute)
            } else {
                String(format: "%.2d:%.2d:%.2d", hour, minute, second)
            }
        }
        switch self {
        case let .repeated(.daily(interval, hour, minute, second), offset):
            let intervalDesc = switch interval {
            case ...0: ""
            case 1: "daily"
            default: "every \(Self.ordinalsFormatter.string(from: .init(value: interval)) ?? "\(interval)th") day"
            }
            return "\(intervalDesc) @ \(fmtTime(hour: hour, minute: minute, second: second))\(Self.offsetDesc(offset))"
        case let .repeated(.weekly(interval, weekday, hour, minute, second), offset):
            let intervalDesc = switch interval {
            case ...0: ""
            case 1: "weekly"
            default: "every \(Self.ordinalsFormatter.string(from: .init(value: interval)) ?? "\(interval)th") week"
            }
            let timeDesc = "\(fmtTime(hour: hour, minute: minute, second: second))\(Self.offsetDesc(offset))"
            return "\(intervalDesc) @ \(weekday?.rawValue ?? "(study enrollment weekday)") \(timeDesc)"
        case let .repeated(.monthly(interval, day, hour, minute, second), offset):
            let intervalDesc = switch interval {
            case ...0: ""
            case 1: "monthly"
            default: "every \(Self.ordinalsFormatter.string(from: .init(value: interval)) ?? "\(interval)th") month"
            }
            let timeDesc = "\(fmtTime(hour: hour, minute: minute, second: second))\(Self.offsetDesc(offset))"
            let dayDesc = day.map { "\(Self.ordinalsFormatter.string(from: .init(value: $0)) ?? "\($0)th") day" } ?? "(study enrollment day)"
            return "\(intervalDesc) @ \(dayDesc) \(timeDesc)"
        case let .once(.date(dateComponents)):
            let date = Calendar.current.date(from: dateComponents)
            return "once; at \(date?.ISO8601Format() ?? dateComponents.description)"
        case let .once(.event(event, offsetInDays, time)):
            var desc = "once; at \(event)"
            if offsetInDays != 0 {
                desc += " \(offsetInDays < 0 ? "-" : "+") \(abs(offsetInDays)) day\(abs(offsetInDays) != 1 ? "s" : "")"
            }
            if let time {
                desc += "; at \(time)"
            }
            return desc
        }
    }

    private static func offsetDesc(_ offset: DateComponents) -> String {
        if offset == .init() {
            ""
        } else {
            "; offset by \(offset)".trimmingWhitespace()
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyLifecycleEvent: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .enrollment:
            "enrollment"
        case .activation:
            "activation"
        case .unenrollment:
            "unenrollment"
        case .studyEnd:
            "studyEnd"
        case .completedTask(let componentId):
            "completedTask(\(componentId.uuidString))"
        }
    }
}
