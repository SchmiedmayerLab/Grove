//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// What one adapter states identically in every graph it emits: its id and the profiles and clear
/// identifiers its envelope resources declare.
package struct ExchangeAdapterContract: Sendable {
    package let adapterID: String
    package let provenanceProfile: FHIRPrimitive<Canonical>
    package let applicationDeviceProfile: FHIRPrimitive<Canonical>
    /// The clear identifier an application Device carries beside its snapshot identity, when the
    /// adapter's guide states one; HealthKit names the Apple bundle identifier.
    package let applicationIdentifier: (@Sendable (ApplicationDevice) -> Identifier?)?

    package init(
        adapterID: String,
        provenanceProfile: FHIRPrimitive<Canonical>,
        applicationDeviceProfile: FHIRPrimitive<Canonical>,
        applicationIdentifier: (@Sendable (ApplicationDevice) -> Identifier?)? = nil
    ) {
        self.adapterID = adapterID
        self.provenanceProfile = provenanceProfile
        self.applicationDeviceProfile = applicationDeviceProfile
        self.applicationIdentifier = applicationIdentifier
    }
}


/// What one graph states about its producer and source repository beside the record itself: the scope every
/// event of one producer shares, and the facts frozen with this event.
///
/// An envelope is built per event from its reservation's facts, so no graph can state a producer's live
/// application, host or studies; whatever outlives one event holds only the ``Scope``.
package struct ExchangeEnvelope: Sendable {
    /// What every event of one producer states identically: the adapter, the identity scope, the subject and
    /// the repository scope. It carries no application, host or studies.
    package struct Scope: Sendable {
        package let adapter: ExchangeAdapterContract
        package let identityScope: OpaqueIdentityScope
        package let subject: Subject
        package let repositoryScope: BusinessIdentifier

        package init(
            adapter: ExchangeAdapterContract,
            identityScope: OpaqueIdentityScope,
            subject: Subject,
            repositoryScope: BusinessIdentifier
        ) {
            self.adapter = adapter
            self.identityScope = identityScope
            self.subject = subject
            self.repositoryScope = repositoryScope
        }

        /// The source-record identity of one native record in this repository.
        package func sourceRecord(sourceType: String, nativeRecordID: String) throws(OpaqueIdentityError) -> SourceRecordIdentity {
            try identityScope.sourceRecord(
                adapterID: adapter.adapterID,
                sourceType: sourceType,
                repositoryScope: repositoryScope,
                nativeRecordID: nativeRecordID
            )
        }
    }

    package let scope: Scope
    /// The application, host and studies the event states, as its reservation froze them.
    package let facts: ExchangeEventFacts

    package var adapter: ExchangeAdapterContract { scope.adapter }
    package var identityScope: OpaqueIdentityScope { scope.identityScope }
    package var subject: Subject { scope.subject }
    package var repositoryScope: BusinessIdentifier { scope.repositoryScope }
    package var application: ApplicationDevice { facts.application }
    package var host: HostDevice { facts.host }
    package var studies: [StudyEnrollment] { facts.studies }

    package init(scope: Scope, facts: ExchangeEventFacts) {
        self.scope = scope
        self.facts = facts
    }
}


/// One output of a source record before the envelope is applied: the resource's own content, and
/// which envelope links it takes.
package struct ExchangeOutputDraft: Sendable {
    /// The envelope statements an output carries beside its content.
    package struct Links: OptionSet, Sendable {
        /// `subject`: who the measurement is about.
        package static let subject = Links(rawValue: 1 << 0)
        /// `Observation.device` or `DocumentReference.author`: the recording Device when the graph has one.
        package static let recordingDevice = Links(rawValue: 1 << 1)
        /// The gateway-device extension when the converter role names a gateway.
        package static let gateway = Links(rawValue: 1 << 2)
        /// One research-study reference per bundled enrollment.
        package static let studies = Links(rawValue: 1 << 3)
        /// The manual-entry recording method when the record was entered by hand.
        package static let manualEntry = Links(rawValue: 1 << 4)

        package static let all: Links = [.subject, .recordingDevice, .gateway, .studies, .manualEntry]

        package let rawValue: UInt8

        package init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    package enum Resource: Sendable {
        case observation(Observation)
        case document(DocumentReference)
    }

    /// Apple's paired sync metadata, carried as a writer-record identity and version.
    package struct WriterRecord: Sendable {
        package let writerApplication: String
        package let syncIdentifier: String
        package let version: String

        package init(writerApplication: String, syncIdentifier: String, version: String) {
            self.writerApplication = writerApplication
            self.syncIdentifier = syncIdentifier
            self.version = version
        }
    }

    package let role: String
    package let discriminator: String
    package var resource: Resource
    package var links: Links
    /// Whether this output states the primary under `derivedFrom`; never set on the primary itself.
    package var derivedFromPrimary: Bool
    /// The native artifact a document output carries, named by its registered format code.
    package var artifactFormatCode: String?
    /// Identifiers the deployment discloses beside the opaque ones, in order.
    package var clearIdentifiers: [Identifier]
    package var writerRecord: WriterRecord?
    package var wasUserEntered: Bool

    package init(
        role: String,
        discriminator: String = "single",
        resource: Resource,
        links: Links = .all,
        derivedFromPrimary: Bool = false,
        artifactFormatCode: String? = nil,
        clearIdentifiers: [Identifier] = [],
        writerRecord: WriterRecord? = nil,
        wasUserEntered: Bool = false
    ) {
        self.role = role
        self.discriminator = discriminator
        self.resource = resource
        self.links = links
        self.derivedFromPrimary = derivedFromPrimary
        self.artifactFormatCode = artifactFormatCode
        self.clearIdentifiers = clearIdentifiers
        self.writerRecord = writerRecord
        self.wasUserEntered = wasUserEntered
    }
}


/// The physical unit a record was measured on, as the adapter resolved it.
package struct ExchangeRecordingDeviceDraft: Sendable {
    package let device: RecordingDevice
    /// The Device body the adapter prepared from its own source facts (name, model, versions, UDI);
    /// the assembler adds identity and repository id.
    package var resource: Device

    package init(device: RecordingDevice, resource: Device) {
        self.device = device
        self.resource = resource
    }
}


/// The application that wrote the record into the source store, and the host it ran on, stated as snapshots of their
/// own and as the Provenance author; a draft without one names no author.
package struct ExchangeWriterDraft: Sendable {
    package let application: ApplicationDevice
    package let host: HostDevice
    /// False when the source named no version, so the application Device carries none.
    package let statesVersion: Bool

    package init(application: ApplicationDevice, host: HostDevice, statesVersion: Bool) {
        self.application = application
        self.host = host
        self.statesVersion = statesVersion
    }
}


/// Why a draft could not become a graph.
package enum ExchangeAssemblyError: Error, Equatable, Sendable {
    /// A repository id names a node the graph does not carry.
    case repositoryIDWithoutNode(ExchangeGraphNode)
    /// The draft states no output.
    case noOutputs
}


/// One assembled graph and the identities it minted, for callers that index or cross-reference them.
package struct AssembledExchangeGraph: Sendable {
    package let graph: ExchangeGraph
    package let identifiers: ExchangeGraphIdentifiers
}


/// One event's graph before assembly: the record, its outputs, and the devices and policies the
/// adapter resolved for it.
package struct ExchangeGraphDraft: Sendable {
    package let event: ExchangeEventIdentifier
    package let instant: Date
    package let sourceRecord: SourceRecordIdentity
    /// The primary output first; members and other children follow in entry order.
    package var outputs: [ExchangeOutputDraft]
    package var recordingDevice: ExchangeRecordingDeviceDraft?
    package var writer: ExchangeWriterDraft?
    package var converterRole: ConverterRole
    package var repositoryIDs: [ExchangeGraphNode: RepositoryID]

    package init(
        event: ExchangeEventIdentifier,
        instant: Date,
        sourceRecord: SourceRecordIdentity,
        outputs: [ExchangeOutputDraft],
        recordingDevice: ExchangeRecordingDeviceDraft? = nil,
        writer: ExchangeWriterDraft? = nil,
        converterRole: ConverterRole = .assembler,
        repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:]
    ) {
        self.event = event
        self.instant = instant
        self.sourceRecord = sourceRecord
        self.outputs = outputs
        self.recordingDevice = recordingDevice
        self.writer = writer
        self.converterRole = converterRole
        self.repositoryIDs = repositoryIDs
    }
}
