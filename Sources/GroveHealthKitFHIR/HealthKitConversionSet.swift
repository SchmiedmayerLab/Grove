//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract


/// Something an accepted record carried that its graph does not; each case is one registered
/// `mobile-omission` rule. An omission a disclosure policy chose is not a warning.
public enum HealthKitConversionWarning: Hashable, Sendable {
    /// The source named a recording device without a stable per-unit token.
    case recordingDeviceOmitted(deviceName: String?)
    /// The source stated no UTC offset or time zone, so the effective instant is serialized in UTC.
    case sourceOffsetUnavailable
    /// The record carried metadata outside the adapter's typed allowlist.
    case unmodeledMetadataWithheld(keys: [String])

    public var diagnostic: ExchangeGraphDiagnostic {
        switch self {
        case .recordingDeviceOmitted:
            ExchangeGraphRule.mobileOmissionRecordingDevice.diagnostic
        case .sourceOffsetUnavailable:
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic
        case .unmodeledMetadataWithheld:
            ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic
        }
    }
}


/// Why one record of a batch was not emitted; the caller's context error keeps its own type.
public enum HealthKitRecordFailure<ContextError: Error>: Error {
    case context(HealthKitSourceRecord, ContextError)
    case conversion(HealthKitSourceRecord, HealthKitConversionError)
    /// A sample whose type the inventory does not list has no ``HealthKitSourceRecord`` to name.
    case unregisteredSourceType(uuid: UUID, identifier: String)
}


/// The independently exchangeable graphs produced from one conversion request, and what was lost.
///
/// Most HealthKit samples yield only ``primary``. An ECG additionally yields its correlated
/// symptom samples as normal, separately provenanced conversions; the ECG refers to their
/// source-output identifiers without embedding those resources.
public struct HealthKitConversionSet: Sendable {
    public let primary: HealthKitConversion
    public let companions: [HealthKitConversion]
    /// Empty when the graphs carry everything the source supplied.
    public let warnings: [HealthKitConversionWarning]

    public var all: [HealthKitConversion] { [primary] + companions }

    public init(
        primary: HealthKitConversion,
        companions: [HealthKitConversion] = [],
        warnings: [HealthKitConversionWarning] = []
    ) {
        self.primary = primary
        self.companions = companions
        self.warnings = warnings
    }
}

#endif
