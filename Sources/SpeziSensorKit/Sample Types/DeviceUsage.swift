//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SensorKit


@available(iOS 17, *)
extension SRDeviceUsageReport: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        public typealias CategoryKey = SRDeviceUsageReport.CategoryKey
        
        /// The point in time when the system recorded the measurement.
        public let timestamp: Date
        
        /// Total duration of the report.
        public let duration: TimeInterval
        /// Total number of screen wakes tracked by the report.
        public let totalScreenWakes: Int
        /// Total number of unlocks tracked by the report.
        public let totalUnlocks: Int
        /// Total amount of time the device was unlocked tracked by the report.
        public let totalUnlockDuration: TimeInterval
        /// Version of the algorithm used to produce the report.
        public let version: String
        
        /// Tracked app usage, by category
        public let appUsageByCategory: [CategoryKey: [AppUsage]]
        
        /// Tracked notification usage, by category
        public let notificationUsageByCategory: [CategoryKey: [NotificationUsage]]
        
        /// Tracked web usage, by category
        public let webUsageByCategory: [CategoryKey: [WebUsage]]
        
        @inlinable public var timeRange: Range<Date> {
            timestamp..<(timestamp + duration)
        }
        
        @inlinable
        init(timestamp: Date, report: SRDeviceUsageReport) {
            self.timestamp = timestamp
            self.duration = report.duration
            self.totalScreenWakes = report.totalScreenWakes
            self.totalUnlocks = report.totalUnlocks
            self.totalUnlockDuration = report.totalUnlockDuration
            self.version = report.version
            self.appUsageByCategory = report.applicationUsageByCategory.mapValues {
                $0.map { AppUsage($0) }
            }
            self.notificationUsageByCategory = report.notificationUsageByCategory.mapValues {
                $0.map { NotificationUsage($0) }
            }
            self.webUsageByCategory = report.webUsageByCategory.mapValues {
                $0.map { WebUsage($0) }
            }
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRDeviceUsageReport)>
    ) throws -> [SafeRepresentation] {
        samples.map {
            SafeRepresentation(timestamp: $0, report: $1)
        }
    }
}


@available(iOS 17, *)
extension SRDeviceUsageReport.SafeRepresentation {
    public struct AppUsage: Hashable, Sendable {
        public struct SupplementalCategory: Hashable, Sendable {
            /// An opaque identifier for the supplemental category
            ///
            /// More information about what this category represents can be found in Apple's developer documentation
            public let identifier: String
            
            @inlinable
            init(_ other: SRSupplementalCategory) {
                self.identifier = other.identifier
            }
        }
        
        public struct TextInputSession: Hashable, Sendable {
            /// The length of time, in seconds, that the session spans.
            public let duration: TimeInterval
            public let sessionType: SRTextInputSession.SessionType
            /// Unique identifier of keyboard session
            public let identifier: String
            
            @inlinable
            init(_ other: SRTextInputSession) {
                self.duration = other.duration
                self.sessionType = other.sessionType
                self.identifier = other.sessionIdentifier
            }
        }
        
        /// The bundle identifier of the app in use. Only populated for Apple apps.
        public let bundleIdentifier: String?
        
        /// App start time relative to the first app start time in the report interval
        ///
        /// relativeStartTime value for the very first app in the report interval is equal to 0, N seconds for the seccond app and so on.
        /// This will allow to order app uses and determine the time between app uses.
        public let relativeStartTime: TimeInterval
        
        /// The amount of time the app is used
        public let usageTime: TimeInterval
        
        /// An application identifier that is valid for the duration of the report.
        /// This is useful for identifying distinct application uses within the same report duration without revealing the actual application identifier.
        public let reportApplicationIdentifier: String

        /// The text input session types that occurred during this application usage
        ///
        /// The list of text input sessions describes the order and type of text input that may
        /// have occured during an application usage. Multiple sessions of the same text input
        /// type will appear as separate array entries. If no text input occurred, this array
        /// will be empty.
        public let textInputSessions: [TextInputSession]

        /// Additional categories that describe this app
        public let supplementalCategories: [SupplementalCategory]
        
        @inlinable
        init(_ other: SRDeviceUsageReport.ApplicationUsage) {
            self.bundleIdentifier = other.bundleIdentifier
            self.relativeStartTime = other.relativeStartTime
            self.usageTime = other.usageTime
            self.reportApplicationIdentifier = other.reportApplicationIdentifier
            self.textInputSessions = other.textInputSessions.map {
                TextInputSession($0)
            }
            self.supplementalCategories = other.supplementalCategories.map {
                SupplementalCategory($0)
            }
        }
    }
}


@available(iOS 17, *)
extension SRDeviceUsageReport.SafeRepresentation {
    public struct NotificationUsage: Hashable, Sendable {
        /// The bundle identifier of the application that corresponds to the notification. Only populated for Apple apps.
        public let bundleIdentifier: String?
        
        /// The way that the user interacts with the notification.
        public let event: SRDeviceUsageReport.NotificationUsage.Event
        
        @inlinable
        init(_ other: SRDeviceUsageReport.NotificationUsage) {
            self.bundleIdentifier = other.bundleIdentifier
            self.event = other.event
        }
    }
}


@available(iOS 17, *)
extension SRDeviceUsageReport.SafeRepresentation {
    public struct WebUsage: Hashable, Sendable {
        /// The amount of web usage time that the report spans.
        public let totalUsageTime: TimeInterval
        
        @inlinable
        init(_ other: SRDeviceUsageReport.WebUsage) {
            self.totalUsageTime = other.totalUsageTime
        }
    }
}
