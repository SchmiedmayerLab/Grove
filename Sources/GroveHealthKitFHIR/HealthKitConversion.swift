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
public import ModelsR4


/// Complete business identities of one emitted exchange graph.
public struct HealthKitGraphIdentifiers: Hashable, Sendable {
    public let event: BusinessIdentifier
    public let sourceRecord: BusinessIdentifier
    public let primaryOutput: BusinessIdentifier
    public let childOutputs: [BusinessIdentifier]
    public let recordingDeviceSnapshot: BusinessIdentifier?
    public let converterApplicationSnapshot: BusinessIdentifier
    public let converterHostSnapshot: BusinessIdentifier
    public let sourceAuthorSnapshot: BusinessIdentifier?
    public let sourceAuthorHostSnapshot: BusinessIdentifier?
    public let provenance: BusinessIdentifier
}


/// The independently exchangeable graphs produced from one conversion request.
///
/// Most HealthKit samples yield only ``primary``. An ECG can additionally yield its correlated
/// symptom samples as normal, separately provenanced HealthKit conversions; the ECG refers to
/// their source-output identifiers without embedding or duplicating those resources.
public struct HealthKitConversionSet: Sendable {
    public let primary: HealthKitConversion
    public let companions: [HealthKitConversion]

    public var all: [HealthKitConversion] { [primary] + companions }

    public init(primary: HealthKitConversion, companions: [HealthKitConversion] = []) {
        self.primary = primary
        self.companions = companions
    }
}


/// One complete conversion graph.
///
/// Resources have no logical `Resource.id` unless the caller supplied a repository id.
/// Deterministic UUIDv5 Bundle fullUrls connect graph entries.
public struct HealthKitConversion: Sendable {
    /// The source-store coordinate retained for local outbox/crosswalk work.
    ///
    /// This value is never inserted into the FHIR graph. Wire disclosure remains governed solely
    /// by ``HealthKitNativeIdentifierDisclosurePolicy``.
    public let localSourceUUID: UUID
    /// The exact HealthKit source type paired with ``localSourceUUID``.
    public let localSourceTypeIdentifier: String
    /// The subject identity used to derive this graph's opaque protocol identities.
    ///
    /// Retained on the local conversion result so graph composition can reject companions from a
    /// different subject. It is not added to the wire beyond the explicitly supplied `subject`
    /// reference already present on the converted resources.
    public let subjectIdentity: BusinessIdentifier
    /// The repository scope used to derive this graph's opaque protocol identities.
    ///
    /// This local context value lets graph composition reject a companion converted for another
    /// repository even when both deployments use the same public identifier systems.
    public let repositoryScope: BusinessIdentifier
    public let sourceIdentifier: Identifier
    public let graphIdentifiers: HealthKitGraphIdentifiers
    public let observation: Observation
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let converterHost: Device
    public let sourceAuthor: Device?
    public let sourceAuthorHost: Device?
    public let provenance: Provenance
    public let graph: ExchangeGraph

    public var bundle: ModelsR4.Bundle { graph.bundle }
}


#endif
