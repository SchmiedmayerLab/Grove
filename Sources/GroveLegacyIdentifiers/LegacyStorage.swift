//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// On-disk locations used before the rename.
///
/// All of these sat under the user's `Documents` directory or under a vendor-named folder in
/// Application Support. They are read once, migrated, and then gone.
public enum LegacyStorage {
    /// Directory holding everything `LocalStorage` ever wrote, relative to Application Support.
    public static let localStorageDirectory = "edu.stanford.spezi/LocalStorage"

    /// Directory holding the scheduler store, relative to the documents directory.
    public static let schedulerDirectory = "SpeziScheduler"

    /// Scheduler store file name, inside ``schedulerDirectory``.
    public static let schedulerStore = "edu.stanford.spezi.scheduler.storage.sqlite"

    /// Study manager store file name, directly in the documents directory.
    public static let studyStore = "edu.stanford.spezi.studymanager.storage.sqlite"

    /// Directory holding downloaded study bundles, relative to the documents directory.
    public static let studyBundlesDirectory = "edu.stanford.SpeziStudy/StudyBundles"

    /// File extension carried by every study bundle written before the rename.
    public static let studyBundleFileExtension = "spezistudybundle"

    /// Paired-devices store file name, directly in the documents directory.
    public static let pairedDevicesStore = "edu.stanford.spezidevices.paired-devices.sqlite"

    /// Health-measurements store file name, directly in the documents directory.
    public static let healthMeasurementsStore = "edu.stanford.spezidevices.health-measurements.sqlite"
}
