//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// How the converting application relates to the measurement it converts.
///
/// Recording and clinical documents carry no gateway link under any role: the guide defines
/// `observation-gatewayDevice` for Observations only.
///
/// Public only for the caller-managed converters that take an ``ExchangeEventContext``; a candidate for package
/// access once they are gone.
public enum ConverterRole: Hashable, Sendable {
    /// The application assembled the graph from a record it did not mediate.
    case assembler
    /// The converting application itself mediated the measurement.
    case gateway
    /// A distinct application mediated the measurement; graphs whose Observation outputs name it through
    /// `observation-gatewayDevice` carry it as a second application snapshot, and document-only graphs carry none.
    case gatewayApplication(ApplicationDevice)
}


/// The graph nodes a repository may have assigned a logical id to.
///
/// Public only for the caller-managed converters that take an ``ExchangeEventContext`` and the errors they report;
/// a candidate for package access once they are gone.
public enum ExchangeGraphNode: Hashable, Sendable {
    case bundle
    case primaryOutput
    case sourceArtifact
    case recordingDevice
    case applicationDevice
    case hostDevice
    /// The application that wrote the source record, when it is not the recording device.
    case writer
    /// The host the writer ran on.
    case writerHost
    case provenance
}


/// Everything one exchange event shares across adapters: who it is about, which event it is,
/// the identity scope that mints its opaque identities, and the converting application and host.
///
/// Callers persist the event identity and identity-scope inputs with the event and reuse them for
/// an exact retry. The `host` and `conversionInstant` defaults read the current host and the clock, so pass both
/// explicitly when you rebuild a persisted event.
///
/// A candidate for removal: the exporters number their events through an ``ExchangeProducer`` instead, and only
/// the caller-managed source-neutral sensor converter, itself a removal candidate, still takes it (beside the
/// package retraction builder, which the HealthKit exporter feeds from its reservation).
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
