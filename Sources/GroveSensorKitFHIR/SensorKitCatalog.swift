//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import GroveFHIRContract


/// The relationship between one SensorKit source token and Grove's implementation.
public enum SensorKitCatalogScope: String, CaseIterable, Sendable {
    case catalogBaseline = "catalog-baseline"
    case stableAddition = "stable-addition"
}


/// The authoritative Grove FHIR status of one SensorKit stream.
public enum SensorKitImplementationStatus: String, CaseIterable, Sendable {
    case supported
    case mappedStandard = "mapped-standard"
    case platformExclusive = "platform-exclusive"
    case unmodeled
    case deferred
    case intentionallyUnsupported = "intentionally-unsupported"
}


/// The admitted structured projection for a SensorKit stream, when one exists.
public enum SensorKitStructuredContract: String, CaseIterable, Sendable {
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
    case wristTemperature = "wrist-temperature"
}


/// One generated row in Grove's complete SensorKit source inventory.
public struct SensorKitCatalogEntry: Equatable, Sendable {
    public let sourceToken: String
    public let sourceTypeCode: String
    public let minimumIOS: String
    public let scope: SensorKitCatalogScope
    public let status: SensorKitImplementationStatus
    public let structuredContract: SensorKitStructuredContract?
    public let structuredProfiles: [String]
    public let rawProfiles: [String]
    public let rawFormats: [RegisteredRecordingFormat]
    public let requirement: String?
}


/// The exact machine-generated SensorKit source inventory consumed by this producer.
public struct SensorKitCatalog: Equatable, Sendable {
    /// The catalog generated from the Grove FHIR Implementation Guides contract.
    public static let current = SensorKitGenerated.catalog

    public let schemaVersion: Int
    public let version: String
    public let fhirVersion: String
    public let entries: [SensorKitCatalogEntry]

    /// Returns the one catalog row for its authoritative source token.
    public func entry(sourceToken: String) -> SensorKitCatalogEntry? {
        entries.first { $0.sourceToken == sourceToken }
    }

    /// Returns the one catalog row for its source-type code.
    public func entry(sourceTypeCode: String) -> SensorKitCatalogEntry? {
        entries.first { $0.sourceTypeCode == sourceTypeCode }
    }
}


extension SensorKitCatalogEntry {
    /// The sole registered payload format for this source, when the catalog admits exactly one.
    public var soleRawFormat: RegisteredRecordingFormat? {
        rawFormats.count == 1 ? rawFormats[0] : nil
    }
}
