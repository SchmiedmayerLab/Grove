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
    public let converterHost: RepositoryID?
    public let sourceAuthor: RepositoryID?
    public let sourceAuthorHost: RepositoryID?
    public let provenance: RepositoryID?

    public init(
        bundle: RepositoryID? = nil,
        observation: RepositoryID? = nil,
        document: RepositoryID? = nil,
        recordingDevice: RepositoryID? = nil,
        converterApplication: RepositoryID? = nil,
        converterHost: RepositoryID? = nil,
        sourceAuthor: RepositoryID? = nil,
        sourceAuthorHost: RepositoryID? = nil,
        provenance: RepositoryID? = nil
    ) {
        self.bundle = bundle
        self.observation = observation
        self.document = document
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.converterHost = converterHost
        self.sourceAuthor = sourceAuthor
        self.sourceAuthorHost = sourceAuthorHost
        self.provenance = provenance
    }
}


/// Explicit inputs needed to make a reproducible, auditable FHIR graph.
public struct HealthKitConversionContext: Sendable {
    public let subject: Reference
    /// Stable deployment identity of `subject`, used only in opaque identity preimages.
    public let subjectIdentity: BusinessIdentifier
    public let converter: HealthKitApplication
    public let converterHost: HealthKitHostDevice
    /// Persisted identity of this immutable source-version event. Exact retry reuses it.
    public let eventIdentifier: ExchangeEventIdentifier
    public let entryNodeIdentifierSystem: IdentifierSystem
    public let identityScope: PseudonymousIdentityScope
    public let repositoryScope: BusinessIdentifier
    public let sourceActor: HealthKitSourceActor
    public let converterWasGateway: Bool
    /// The instant of this conversion event.
    ///
    /// Written to `Provenance.occurred`/`recorded` and `Bundle.timestamp`; it is deliberately not
    /// substituted for `Observation.issued`, which HealthKit does not provide. Each sample's own
    /// measurement time lands in `Observation.effective`. Callers persist this with the event;
    /// Grove never reads the clock.
    public let conversionInstant: Date
    /// Stable source-local token for the physical recorder, when one is available.
    /// It is HMAC input and is never emitted verbatim.
    public let recordingDeviceStableUnitToken: String?
    /// Explicit UDI disclosure policy. The default omits the UDI even when HealthKit
    /// supplies one.
    public let udiDisclosurePolicy: HealthKitUDIDisclosurePolicy
    /// Whether the source `HKObject.uuid` is also carried as a governed native identifier.
    public let nativeIdentifierDisclosurePolicy: HealthKitNativeIdentifierDisclosurePolicy
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
    /// let patientID = try BusinessIdentifier(
    ///     system: "https://study.example/fhir/identifiers/participant",
    ///     value: "participant-42"
    /// )
    /// let patient = Reference(
    ///     identifier: patientID.fhirIdentifier,
    ///     type: FHIRPrimitive(FHIRURI(stringLiteral: "Patient"))
    /// )
    /// ```
    public init(
        subject: Reference,
        subjectIdentity: BusinessIdentifier,
        converter: HealthKitApplication,
        converterHost: HealthKitHostDevice,
        eventIdentifier: ExchangeEventIdentifier,
        entryNodeIdentifierSystem: IdentifierSystem,
        identityScope: PseudonymousIdentityScope,
        repositoryScope: BusinessIdentifier,
        sourceActor: HealthKitSourceActor,
        converterWasGateway: Bool = false,
        conversionInstant: Date,
        recordingDeviceStableUnitToken: String? = nil,
        udiDisclosurePolicy: HealthKitUDIDisclosurePolicy = .omit,
        nativeIdentifierDisclosurePolicy: HealthKitNativeIdentifierDisclosurePolicy = .omit,
        routeDisclosurePolicy: HealthKitRouteDisclosurePolicy = .omit,
        protocolCanonical: String? = nil,
        researchStudies: [Reference] = [],
        repositoryIDs: HealthKitRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.subjectIdentity = subjectIdentity
        self.converter = converter
        self.converterHost = converterHost
        self.eventIdentifier = eventIdentifier
        self.entryNodeIdentifierSystem = entryNodeIdentifierSystem
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.sourceActor = sourceActor
        self.converterWasGateway = converterWasGateway
        self.conversionInstant = conversionInstant
        self.recordingDeviceStableUnitToken = recordingDeviceStableUnitToken
        self.udiDisclosurePolicy = udiDisclosurePolicy
        self.nativeIdentifierDisclosurePolicy = nativeIdentifierDisclosurePolicy
        self.routeDisclosurePolicy = routeDisclosurePolicy
        self.protocolCanonical = protocolCanonical
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}

#endif
