//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The relationship between one SensorKit source token and Grove's implementation.
public enum SensorKitFHIRCatalogScope: String, CaseIterable, Sendable {
    case catalogBaseline = "catalog-baseline"
    case stableAddition = "stable-addition"
}


/// The authoritative v0.2 status of one SensorKit stream.
public enum SensorKitFHIRImplementationStatus: String, CaseIterable, Sendable {
    case supported
    case mappedStandard = "mapped-standard"
    case platformExclusive = "platform-exclusive"
    case unmodeled
    case deferred
    case intentionallyUnsupported = "intentionally-unsupported"
}


/// The admitted structured projection for a SensorKit stream, when one exists.
public enum SensorKitFHIRStructuredContract: String, CaseIterable, Sendable {
    case sampledData = "sampled-data"
    case electrocardiogram = "ecg"
    case deviceUsage = "device-usage"
    case onWrist = "on-wrist"
    case visit = "visit"
    case messagesUsage = "messages-usage"
    case phoneUsage = "phone-usage"
    case keyboardMetrics = "keyboard-metrics"
    case sleepSession = "sleep-sessions"
    case accelerometer
    case ppg
}


/// One generated row in Grove's complete SensorKit v0.2 source inventory.
public struct SensorKitFHIRCatalogEntry: Equatable, Sendable {
    public let sourceToken: String
    public let sourceTypeCode: String
    public let minimumIOS: String
    public let scope: SensorKitFHIRCatalogScope
    public let status: SensorKitFHIRImplementationStatus
    public let structuredContract: SensorKitFHIRStructuredContract?
    public let structuredProfiles: [String]
    public let rawProfiles: [String]
    public let rawFormats: [String]
    public let requirement: String?
}


/// The exact machine-generated SensorKit source inventory consumed by this producer.
public struct SensorKitFHIRCatalog: Equatable, Sendable {
    /// The catalog generated from grove-fhir's adapter-inclusive v0.2 branch.
    public static let current = GroveSensorKitGenerated.catalog

    public let schemaVersion: Int
    public let version: String
    public let fhirVersion: String
    public let entries: [SensorKitFHIRCatalogEntry]
}
