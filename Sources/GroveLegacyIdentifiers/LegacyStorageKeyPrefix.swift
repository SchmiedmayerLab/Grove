//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// `LocalStorage` key prefixes used before the rename.
///
/// The keys themselves are not enumerable — HealthKit anchors are suffixed with a sample type
/// identifier, bulk exports with a session identifier — so migration renames by prefix over the
/// directory rather than key by key.
public enum LegacyStorageKeyPrefix {
    /// HealthKit query anchors, one entry per sample type.
    public static let healthKitQueryAnchors = "edu.stanford.Spezi.SpeziHealthKit.queryAnchors"

    /// HealthKit collection start dates, one entry per sample type.
    public static let healthKitSampleCollectionStartDates = "edu.stanford.Spezi.SpeziHealthKit.sampleCollectionStartDates"

    /// SensorKit query anchors, one entry per sensor and device.
    public static let sensorKitQueryAnchors = "edu.stanford.SpeziSensorKit.QueryAnchors"

    /// Bulk-export session state, one entry per session.
    public static let bulkExportSessions = "edu.stanford.spezi.HealthKit.BulkExport"

    /// Cached account details, one entry per account.
    public static let accountDetailsCache = "edu.stanford.spezi.details-cache"
}
