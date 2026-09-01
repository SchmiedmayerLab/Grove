//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveLegacyIdentifiers
import Testing


/// Pins the contents of the legacy vault.
///
/// Every string in the vault names data already sitting on a user's device, so changing one
/// silently orphans it. The vault carries no deprecation — it is not a package product, so the only
/// callers are the migrations entitled to read it — and this suite is what makes adding to or editing
/// it a deliberate act instead of an accident.
@Suite
struct LegacyIdentifierInventoryTests {
    /// Every transitional identifier paired with the exact literal it shipped with. The vault's
    /// only job is that none of these strings ever changes, so the expectation pins the values
    /// themselves -- a count would pass even if an identifier were edited.
    private static let transitional: [(identifier: String, shipped: String)] = [
        (FrozenKeyTags.localStorageKeyPrefix, "LocalStorage."),
        (LegacyKeychain.accessGuardService, "edu.stanford.spezi.accessGuard"),
        (LegacyKeychain.firebaseActiveAccountService, "active-service.firebase.stanford.edu"),
        (LegacyKeychain.firebaseEmailPasswordCredentials, "account.email-pw.firebase.stanford.edu"),
        (LegacyNotifications.schedulerPrefix, "edu.stanford.spezi.scheduler.notification"),
        (LegacyNotifications.schedulerBackgroundTask, "edu.stanford.spezi.scheduler.notifications-scheduling"),
        (LegacyNotifications.scheduledDateUserInfoKey, "edu.stanford.SpeziNotifications.notificationScheduledDate"),
        (LegacyNotifications.schedulerOneDotZeroTasks, "spezi.scheduler.tasks"),
        (LegacyPreferenceKey.schedulerEarliestRefreshDate, "edu.stanford.spezi.scheduler.earliestScheduleRefreshDate"),
        (LegacyPreferenceKey.schedulerAuthorizationDisallowed, "edu.stanford.spezi.scheduler.authorizationDisallowedLastScheduling"),
        (LegacyPreferenceKey.devicesEverPairedOnce, "edu.stanford.spezi.SpeziDevices.ever-paired-once"),
        (LegacyPreferenceKey.devicesAccessorySetupKitMigration, "edu.stanford.spezi.SpeziDevices.askit-migration"),
        (LegacyStorage.localStorageDirectory, "edu.stanford.spezi/LocalStorage"),
        (LegacyStorage.schedulerDirectory, "SpeziScheduler"),
        (LegacyStorage.schedulerStore, "edu.stanford.spezi.scheduler.storage.sqlite"),
        (LegacyStorage.studyStore, "edu.stanford.spezi.studymanager.storage.sqlite"),
        (LegacyStorage.studyBundlesDirectory, "edu.stanford.SpeziStudy/StudyBundles"),
        (LegacyStorage.studyBundleFileExtension, "spezistudybundle"),
        (LegacyStorage.pairedDevicesStore, "edu.stanford.spezidevices.paired-devices.sqlite"),
        (LegacyStorage.healthMeasurementsStore, "edu.stanford.spezidevices.health-measurements.sqlite"),
        (LegacyStorageKeyPrefix.healthKitQueryAnchors, "edu.stanford.Spezi.SpeziHealthKit.queryAnchors"),
        (LegacyStorageKeyPrefix.healthKitSampleCollectionStartDates, "edu.stanford.Spezi.SpeziHealthKit.sampleCollectionStartDates"),
        (LegacyStorageKeyPrefix.sensorKitQueryAnchors, "edu.stanford.SpeziSensorKit.QueryAnchors"),
        (LegacyStorageKeyPrefix.bulkExportSessions, "edu.stanford.spezi.HealthKit.BulkExport"),
        (LegacyStorageKeyPrefix.accountDetailsCache, "edu.stanford.spezi.details-cache"),
        (LegacyStudyTaskIdentifiers.componentTaskPrefix, "edu.stanford.spezi.SpeziStudy.studyComponentTask."),
        (LegacyStudyTaskIdentifiers.categoryPrefix, "edu.stanford.spezi.SpeziStudy.task.")
    ]

    @Test
    func everyVaultIdentifierStillCarriesItsShippedValue() {
        #expect(Self.transitional.count == 27)
        for entry in Self.transitional {
            #expect(entry.identifier == entry.shipped)
        }
    }

    @Test
    func noIdentifierIsEmptyOrPadded() {
        for entry in Self.transitional {
            #expect(!entry.identifier.isEmpty)
            #expect(entry.identifier == entry.identifier.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
