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


/// Optional logical ids already assigned by a FHIR repository.
///
/// These are never derived from HealthKit identities or Bundle UUID URNs.
public struct HealthKitRepositoryIDs: Hashable, Sendable {
    public let bundle: RepositoryID?
    public let observation: RepositoryID?
    /// The logical id of a recording document, for the sources carried as one rather than reduced
    /// to an Observation result.
    public let document: RepositoryID?
    public let recordingDevice: RepositoryID?
    public let converterApplication: RepositoryID?
    public let sourceAuthor: RepositoryID?
    public let provenance: RepositoryID?

    public init(
        bundle: RepositoryID? = nil,
        observation: RepositoryID? = nil,
        document: RepositoryID? = nil,
        recordingDevice: RepositoryID? = nil,
        converterApplication: RepositoryID? = nil,
        sourceAuthor: RepositoryID? = nil,
        provenance: RepositoryID? = nil
    ) {
        self.bundle = bundle
        self.observation = observation
        self.document = document
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.sourceAuthor = sourceAuthor
        self.provenance = provenance
    }
}


/// Explicit inputs needed to make a reproducible, auditable FHIR graph.
public struct HealthKitConversionContext: Sendable {
    public let subject: Reference
    public let converter: HealthKitApplication
    /// Deployment-owned identifier namespace for graph nodes that have no natural identity.
    ///
    /// A sample's Observation is identified by its HealthKit object UUID, but the Bundle, the
    /// conversion Provenance, and derived Device resources exist only because of this export.
    /// Their business identifiers are minted deterministically inside this namespace, so the
    /// same conversion always produces the same graph and re-sends deduplicate on the server.
    ///
    /// Defaults to a namespace derived from the converting application's bundle identifier, which
    /// is globally unique and stable across releases. Pass one stable URL you own once the deployment has a
    /// server namespace, for example `https://mystudy.example.org/fhir/identifiers/mobile-graph`.
    ///
    /// - Note: See <doc:ConfiguringAConversion> for what an identifier namespace is in FHIR.
    public let graphIdentifierSystem: IdentifierSystem?
    public let sourceActor: HealthKitSourceActor
    public let converterWasGateway: Bool
    /// The instant of this conversion event.
    ///
    /// Written to `Observation.issued`, `Provenance.occurred`/`recorded`, and `Bundle.timestamp`;
    /// each sample's own measurement time always comes from the sample and lands in
    /// `Observation.effective`. Defaults to the wall clock; pass a fixed instant to make a
    /// conversion reproducible.
    public let conversionInstant: Date
    /// Deployment-owned namespace that authorizes disclosure of an opaque, local
    /// `HKDevice.localIdentifier`. It does not authorize UDI disclosure.
    public let recordingDeviceIdentifierSystem: IdentifierSystem?
    /// Explicit UDI disclosure policy. The default omits the UDI even when HealthKit
    /// supplies one.
    public let udiDisclosurePolicy: HealthKitUDIDisclosurePolicy
    /// Explicit policy for the linkable source-revision evidence required by correlated
    /// ECG symptoms.
    public let sourceRevisionDisclosurePolicy: HealthKitSourceDisclosurePolicy
    /// Whether retained metadata may carry entries that identify a record across systems.
    public let linkableMetadataPolicy: HealthKitLinkableMetadataPolicy
    /// Whether a workout's recorded route may be disclosed.
    public let routeDisclosurePolicy: HealthKitRouteDisclosurePolicy
    /// The versioned protocol a measurement was collected under, as `PlanDefinition.url|version`.
    ///
    /// `workflow-researchStudy` links the study, whose protocol moves on; this states the exact
    /// revision in force when the measurement was taken. The guide's study model already versions
    /// the PlanDefinition, so nothing new is invented to carry it.
    public let protocolCanonical: String?
    public let researchStudies: [Reference]
    public let repositoryIDs: HealthKitRepositoryIDs

    /// Creates a conversion context, deriving everything that can be read from the running app.
    ///
    /// Only ``subject`` has no local answer: nothing on the device knows who the receiving
    /// system thinks this data is about. See <doc:ConfiguringAConversion>.
    ///
    /// ```swift
    /// let context = HealthKitConversionContext(subject: Reference(reference: "Patient/example"))
    /// ```
    public init(
        subject: Reference,
        converter: HealthKitApplication = .main,
        graphIdentifierSystem: IdentifierSystem? = nil,
        sourceActor: HealthKitSourceActor = .application,
        converterWasGateway: Bool = false,
        conversionInstant: Date = .now,
        recordingDeviceIdentifierSystem: IdentifierSystem? = nil,
        udiDisclosurePolicy: HealthKitUDIDisclosurePolicy = .omit,
        sourceRevisionDisclosurePolicy: HealthKitSourceDisclosurePolicy = .omit,
        linkableMetadataPolicy: HealthKitLinkableMetadataPolicy = .omit,
        routeDisclosurePolicy: HealthKitRouteDisclosurePolicy = .omit,
        protocolCanonical: String? = nil,
        researchStudies: [Reference] = [],
        repositoryIDs: HealthKitRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem ?? converter.graphIdentifierSystem
        self.sourceActor = sourceActor
        self.converterWasGateway = converterWasGateway
        self.conversionInstant = conversionInstant
        self.recordingDeviceIdentifierSystem = recordingDeviceIdentifierSystem
        self.udiDisclosurePolicy = udiDisclosurePolicy
        self.sourceRevisionDisclosurePolicy = sourceRevisionDisclosurePolicy
        self.linkableMetadataPolicy = linkableMetadataPolicy
        self.routeDisclosurePolicy = routeDisclosurePolicy
        self.protocolCanonical = protocolCanonical
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


extension HealthKitConversionContext {
    /// The namespace derived nodes are minted in.
    ///
    /// Context validation rejects a conversion whose converter cannot supply one, so every
    /// resource built after that point has a namespace to mint into.
    var resolvedGraphIdentifierSystem: IdentifierSystem {
        get throws(HealthKitConversionError) {
            guard let graphIdentifierSystem else {
                throw .invalidConverterApplication("bundleIdentifier")
            }
            return graphIdentifierSystem
        }
    }
}

#endif
