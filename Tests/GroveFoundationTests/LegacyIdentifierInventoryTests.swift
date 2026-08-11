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
/// Every string in `Transitional/` names data already sitting on a user's device, so changing one
/// silently orphans it. The vault carries no deprecation — it is not a package product, so the only
/// callers are the migrations entitled to read it — and this suite is what makes adding to or editing
/// it a deliberate act instead of an accident.
@Suite
struct LegacyIdentifierInventoryTests {
    /// Every transitional identifier, exactly as it was written before the rename.
    private static let transitional: [String] = [
        FrozenKeyTags.localStorageKeyPrefix,
        LegacyKeychain.accessGuardService,
        LegacyKeychain.firebaseActiveAccountService,
        LegacyKeychain.firebaseEmailPasswordCredentials,
        LegacyNotifications.schedulerPrefix,
        LegacyNotifications.schedulerBackgroundTask,
        LegacyNotifications.scheduledDateUserInfoKey,
        LegacyNotifications.schedulerOneDotZeroTasks,
        LegacyPreferenceKey.schedulerEarliestRefreshDate,
        LegacyPreferenceKey.schedulerAuthorizationDisallowed,
        LegacyPreferenceKey.devicesEverPairedOnce,
        LegacyPreferenceKey.devicesAccessorySetupKitMigration,
        LegacyStorage.localStorageDirectory,
        LegacyStorage.schedulerDirectory,
        LegacyStorage.schedulerStore,
        LegacyStorage.studyStore,
        LegacyStorage.studyBundlesDirectory,
        LegacyStorage.studyBundleFileExtension,
        LegacyStorage.pairedDevicesStore,
        LegacyStorage.healthMeasurementsStore,
        LegacyStorageKeyPrefix.healthKitQueryAnchors,
        LegacyStorageKeyPrefix.healthKitSampleCollectionStartDates,
        LegacyStorageKeyPrefix.sensorKitQueryAnchors,
        LegacyStorageKeyPrefix.bulkExportSessions,
        LegacyStorageKeyPrefix.accountDetailsCache,
        LegacyStudyTaskIdentifiers.componentTaskPrefix,
        LegacyStudyTaskIdentifiers.categoryPrefix
    ]

    /// A count, not a set: two identifiers may legitimately share a value, and losing one to a
    /// deduplicating collection is exactly the accident this pins against.
    @Test
    func theVaultHoldsTheIdentifiersItShipped() {
        #expect(Self.transitional.count == 27)
    }

    @Test
    func noIdentifierIsEmptyOrPadded() {
        for identifier in Self.transitional {
            #expect(!identifier.isEmpty)
            #expect(identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The whole point of the vault: every pre-Grove name lives here and nowhere else. Anything in it
    /// that has already lost its brand token belongs in the modules, not in the vault.
    @Test
    func everyTransitionalIdentifierStillCarriesWhatItWasMintedWith() {
        let exemptions = [
            FrozenKeyTags.localStorageKeyPrefix,  // never carried a brand; frozen because it is on disk
            LegacyStorage.schedulerDirectory      // a bare "SpeziScheduler" folder name
        ]
        for identifier in Self.transitional where !exemptions.contains(identifier) {
            let lowered = identifier.lowercased()
            // Legacy tokens on purpose: the vault holds pre-Grove spellings, so "grove" must never appear.
            let brandTokens = ["spezi", "stanford", "bdh", "biodesign", "cardinalkit"]
            #expect(brandTokens.contains { lowered.contains($0) }, "'\(identifier)' carries no legacy brand")
        }
    }

    /// Superseded FHIR URLs outlive every device migration — they sit in resources this project does
    /// not own — so they must never be folded into `Transitional/` and deleted with it.
    @Test
    func publishedURLsAreAbsoluteAndDistinctFromTheTransitionalSet() {
        let published = SupersededFHIRURLs.validationText
            + SupersededFHIRURLs.iosKeyboardType
            + SupersededFHIRURLs.iosTextContentType
            + SupersededFHIRURLs.iosAutocapitalizationType
            + SupersededFHIRURLs.sourceDevice
            + SupersededFHIRURLs.healthKitSampleId

        #expect(!published.isEmpty)
        for url in published {
            #expect(url.hasPrefix("http://") || url.hasPrefix("https://"), "'\(url)' is not absolute")
            #expect(!Self.transitional.contains(url))
        }
    }
}
