//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// How the converting application relates to the measurement it converts.
public enum ConverterRole: Hashable, Sendable {
    /// The application assembled the graph from a record it did not mediate.
    case assembler
    /// The converting application itself mediated the measurement.
    case gateway
    /// A distinct application mediated the measurement; it travels as a second application snapshot.
    case gatewayApplication(ApplicationDevice)
}


/// The graph nodes a repository may have assigned a logical id to.
public enum ExchangeGraphNode: Hashable, Sendable {
    case bundle
    case primaryOutput
    case sourceArtifact
    case recordingDevice
    case applicationDevice
    case hostDevice
    case sourceAuthor
    case sourceAuthorHost
    case provenance
}


/// Whether a recorded route may be disclosed.
///
/// A route re-identifies more readily than any other series, and no aggregate substitutes for it
/// when a study needs the path, so the choice belongs to the deployment. Omission drops the route
/// and keeps the session it belongs to.
public enum RouteDisclosurePolicy: Hashable, Sendable {
    case omit
    case authorized
}


/// Everything one exchange event shares across adapters: who it is about, which event it is,
/// the identity scope that mints its opaque identities, and the converting application and host.
///
/// Callers persist the event identity and identity-scope inputs with the event and reuse them for
/// an exact retry. Grove never reads the clock; ``conversionInstant`` is the caller's.
public struct ExchangeEventContext: Sendable {
    public let subject: Subject
    public let event: ExchangeEventIdentifier
    public let identityScope: OpaqueIdentityScope
    public let repositoryScope: BusinessIdentifier
    public let application: ApplicationDevice
    public let host: HostDevice
    public let converterRole: ConverterRole
    public let conversionInstant: Date
    public let studies: [StudyEnrollment]
    public let repositoryIDs: [ExchangeGraphNode: RepositoryID]

    /// The deployment's entry-node system, held by the identity scope.
    public var entryNodeIdentifierSystem: IdentifierSystem { identityScope.systems.entryNode }

    public init(
        subject: Subject,
        event: ExchangeEventIdentifier,
        identityScope: OpaqueIdentityScope,
        repositoryScope: BusinessIdentifier,
        application: ApplicationDevice,
        host: HostDevice = .current(),
        conversionInstant: Date = .now,
        converterRole: ConverterRole = .assembler,
        studies: [StudyEnrollment] = [],
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) {
        self.subject = subject
        self.event = event
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.application = application
        self.host = host
        self.converterRole = converterRole
        self.conversionInstant = conversionInstant
        self.studies = studies
        self.repositoryIDs = repositoryIDs
    }
}
