//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
import Foundation
import GroveLegacyIdentifiers
import OSLog


private let logger = Logger(subsystem: "org.grovealliance.scheduler", category: "Notifications")


@usableFromInline
struct PermittedBackgroundTaskIdentifier: RawRepresentable, Hashable, Sendable, Codable {
    /// The identifier the scheduler registers for its notification-refresh background task.
    ///
    /// Derived from the app's own bundle identifier, which is Apple's documented convention and means
    /// a future rename of this framework never invalidates a consumer's `Info.plist`.
    @usableFromInline static var schedulerNotificationsRefresh: PermittedBackgroundTaskIdentifier {
        PermittedBackgroundTaskIdentifier(rawValue: "\(Bundle.main.bundleIdentifier ?? "app").scheduler.refresh")
    }

    /// The identifier used before the rename.
    ///
    /// Unique among the migrations in that it lives in the *consuming app's* `Info.plist`, so no code
    /// can move it — only detect it, honour it for one release, and tell the developer what to change.
    @usableFromInline static var legacyNotificationsScheduling: PermittedBackgroundTaskIdentifier {
        PermittedBackgroundTaskIdentifier(rawValue: LegacyNotifications.schedulerBackgroundTask)
    }

    /// The identifier to use, given what the app actually permits.
    ///
    /// Registering an identifier the app has not listed in `BGTaskSchedulerPermittedIdentifiers`
    /// fails silently: notification refresh simply stops, with no crash and nothing a developer would
    /// notice in production. So the permitted list is read, and an app that still lists only the old
    /// identifier keeps working for this release while being told exactly what to change.
    @usableFromInline static var resolved: PermittedBackgroundTaskIdentifier {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        let current = schedulerNotificationsRefresh
        if permitted.contains(current.rawValue) {
            return current
        }
        let legacy = legacyNotificationsScheduling
        if permitted.contains(legacy.rawValue) {
            LegacyIdentifierReport.encountered(
                legacy.rawValue,
                in: "GroveScheduler",
                .duringMigration,
                remedy: "Replace it with '\(current.rawValue)' in BGTaskSchedulerPermittedIdentifiers."
            )
            return legacy
        }
        // Neither identifier is listed, so the app never opted into background refresh at all. That is
        // a legitimate configuration -- test hosts and macOS apps reach here normally -- and emphatically
        // not a legacy-identifier encounter, so it informs rather than trapping.
        logger.notice(
            """
            Background notification refresh is not enabled: add '\(current.rawValue, privacy: .public)' to \
            BGTaskSchedulerPermittedIdentifiers to turn it on.
            """
        )
        return current
    }

    @usableFromInline let rawValue: String

    @usableFromInline
    init(rawValue: String) {
        self.rawValue = rawValue
    }
}
#endif
