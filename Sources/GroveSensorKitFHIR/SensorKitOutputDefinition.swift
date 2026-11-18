//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFHIRContract


/// Portable output-selection facts for a cataloged SensorKit converter.
/// These facts describe the current producer's resource shapes, not permission to collect,
/// operating-system availability, or full validation of every field against the guide.
public struct SensorKitOutputDefinition: Sendable {
    /// The effective-time datatypes an Observation states.
    public enum Effective: Sendable, Equatable {
        /// A whole interval.
        case period
        /// Either a point in time or an interval.
        case dateTimeOrPeriod
    }

    /// The value shape of an Observation.
    public enum ValueShape: Sendable, Equatable {
        /// A top-level Quantity.
        case quantity
        /// A top-level CodeableConcept.
        case coded
        /// Components without a top-level value.
        case components
        /// A top-level SampledData.
        case sampledData
        /// A component whose value is SampledData.
        case sampledDataComponent
    }

    /// The facts of a converter's structured Observation.
    public struct Observation: Sendable {
        /// The structured contract of the converter.
        public let contract: SensorKitStructuredContract
        /// All simultaneous profile claims, read directly from the generated catalog row.
        public let profiles: [String]
        /// The effective-time datatypes the Observation states.
        public let effective: Effective
        /// The value shape of the Observation.
        public let valueShape: ValueShape
        /// Whether conversion requires an accompanying exact native recording.
        public let requiresRecording: Bool

        /// The sole SensorKit-specific claim, distinct from additional shared sensor profile claims.
        public var primaryProfile: String? {
            let candidates = profiles.filter { $0.hasPrefix(SensorKitContract.canonicalRoot + "/StructureDefinition/") }
            return candidates.count == 1 ? candidates.first : nil
        }
    }

    /// The source's catalog token.
    public let sourceToken: String
    /// The source-type code the outputs state.
    public let sourceTypeCode: String
    /// The converter's structured Observation, when the source has one.
    public let observation: Observation?
    /// Every simultaneous profile on an emitted recording DocumentReference.
    public let recordingProfiles: [String]
    /// Registered native formats admitted by the source; this is not arbitrary opaque JSON admission.
    public let recordingFormats: [RegisteredRecordingFormat]
    /// Profiles required for complete source custody; this does not grant any study access to those outputs.
    public let requiredCompanionProfiles: [String]

    init?(_ entry: SensorKitCatalogEntry) {
        sourceToken = entry.sourceToken
        sourceTypeCode = entry.sourceTypeCode
        recordingProfiles = entry.rawProfiles
        recordingFormats = entry.rawFormats
        observation = entry.structuredContract.map { contract in
            Observation(
                contract: contract,
                profiles: entry.structuredProfiles,
                effective: contract == .onWrist ? .dateTimeOrPeriod : .period,
                valueShape: Self.valueShape(contract),
                requiresRecording: Self.requiresRecording(contract)
            )
        }
        if observation?.requiresRecording == true {
            guard entry.rawProfiles.contains(SensorKitContract.recordingDocumentProfile) else {
                return nil
            }
            requiredCompanionProfiles = [SensorKitContract.recordingDocumentProfile]
        } else {
            requiredCompanionProfiles = []
        }
    }

    private static func valueShape(_ contract: SensorKitStructuredContract) -> ValueShape {
        switch contract {
        case .sampledData: .sampledData
        case .electrocardiogram: .sampledDataComponent
        case .onWrist: .coded
        case .deviceUsage, .phoneUsage, .keyboardMetrics, .sleepSession: .quantity
        case .visit, .messagesUsage, .accelerometer, .ppg, .wristTemperature: .components
        }
    }

    private static func requiresRecording(_ contract: SensorKitStructuredContract) -> Bool {
        switch contract {
        case .electrocardiogram, .deviceUsage, .keyboardMetrics, .accelerometer, .ppg, .wristTemperature: true
        case .sampledData, .onWrist, .visit, .messagesUsage, .phoneUsage, .sleepSession: false
        }
    }
}


extension SensorKitCatalogEntry {
    /// Current converter output shapes, distinct from the guide's inventory/status label.
    /// A missing descriptor leaves deferred or unadmitted streams unavailable.
    public var implementedOutput: SensorKitOutputDefinition? {
        guard status != .deferred, status != .intentionallyUnsupported,
              structuredContract != nil || !rawFormats.isEmpty else {
            return nil
        }
        return SensorKitOutputDefinition(self)
    }
}
