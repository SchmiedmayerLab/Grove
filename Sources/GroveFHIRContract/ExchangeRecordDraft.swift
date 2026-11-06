//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// What one adapter states identically in every record it emits: its id and the profiles and clear
/// identifiers its envelope resources declare.
package struct ExchangeAdapterContract: Sendable {
    package let adapterID: String
    package let provenanceProfile: FHIRPrimitive<Canonical>
    package let applicationDeviceProfile: FHIRPrimitive<Canonical>
    /// The clear identifier an application Device carries beside its snapshot identity, when the
    /// adapter states one: ``ApplicationDevice/appleBundleIdentifier`` for each Apple adapter.
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


/// What one record states about its producer and source repository beside the record itself.
package struct ExchangeEnvelope: Sendable {
    /// What every record of one producer states identically: the adapter, the identity scope, the subject and
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
        package func sourceRecord(sourceType: String, nativeRecordID: String) throws(ExchangeIdentityError) -> SourceRecordIdentity {
            try identityScope.sourceRecord(
                adapterID: adapter.adapterID,
                sourceType: sourceType,
                repositoryScope: repositoryScope,
                nativeRecordID: nativeRecordID
            )
        }
    }

    package let scope: Scope
    /// The application, host and studies the record states.
    package let facts: ConversionFacts

    package var adapter: ExchangeAdapterContract { scope.adapter }
    package var identityScope: OpaqueIdentityScope { scope.identityScope }
    package var subject: Subject { scope.subject }
    package var application: ApplicationDevice { facts.application }
    package var host: HostDevice { facts.host }
    package var studies: [StudyEnrollment] { facts.studies }

    package init(scope: Scope, facts: ConversionFacts) {
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
        /// On an Observation, `device` names the recording Device when the record has one. On a DocumentReference,
        /// `author` names the recording Device when the record has one, then the converting application, always.
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
    /// Whether the primary Observation lists this child through a resolving `hasMember` reference.
    package var memberOfPrimary: Bool
    /// Whether this output states the primary under `derivedFrom`; never set on the primary itself.
    package var derivedFromPrimary: Bool
    /// The native artifact a document output carries, named by its registered format code.
    package var artifactFormatCode: String?
    /// Identifiers the deployment discloses beside the opaque ones, in order.
    package var clearIdentifiers: [Identifier]
    package var writerRecord: WriterRecord?
    package var wasUserEntered: Bool
    /// Extensions the resource states after the ones its links add, in order, such as SensorKit's wrist-temperature
    /// algorithm version, which follows the study references.
    package var trailingExtensions: [Extension]

    package init(
        role: String,
        discriminator: String = "single",
        resource: Resource,
        links: Links = .all,
        memberOfPrimary: Bool = false,
        derivedFromPrimary: Bool = false,
        artifactFormatCode: String? = nil,
        clearIdentifiers: [Identifier] = [],
        writerRecord: WriterRecord? = nil,
        wasUserEntered: Bool = false,
        trailingExtensions: [Extension] = []
    ) {
        self.role = role
        self.discriminator = discriminator
        self.resource = resource
        self.links = links
        self.memberOfPrimary = memberOfPrimary
        self.derivedFromPrimary = derivedFromPrimary
        self.artifactFormatCode = artifactFormatCode
        self.clearIdentifiers = clearIdentifiers
        self.writerRecord = writerRecord
        self.wasUserEntered = wasUserEntered
        self.trailingExtensions = trailingExtensions
    }
}


/// The application that wrote the record into the source store, and the host it ran on, stated as snapshots of their
/// own and as the Provenance author; a draft without one names no author.
package struct ExchangeWriterDraft: Sendable {
    package let application: ApplicationDevice
    package let host: HostDevice
    /// Whether the source states its marketing version. Its build remains independent of this choice.
    package let statesVersion: Bool

    package init(application: ApplicationDevice, host: HostDevice, statesVersion: Bool) {
        self.application = application
        self.host = host
        self.statesVersion = statesVersion
    }
}


/// Why a draft could not become a record.
package enum ExchangeAssemblyError: Error, Equatable, Sendable {
    /// The draft states no output.
    case noOutputs
}


/// One assembled record and the identities it minted, for callers that index or cross-reference them.
package struct AssembledExchangeRecord: Sendable {
    package let record: ExchangeRecord
    package let identifiers: ExchangeGraphIdentifiers
}


/// How the converting application relates to the measurement it converts.
///
/// Recording and clinical documents carry no gateway link under any role: the guide defines
/// `observation-gatewayDevice` for Observations only.
package enum ConverterRole: Hashable, Sendable {
    /// The application assembled the record from one it did not mediate.
    case assembler
    /// The converting application itself mediated the measurement.
    case gateway
    /// A distinct application mediated the measurement; records whose Observation outputs name it through
    /// `observation-gatewayDevice` carry it as a second application snapshot, and document-only records carry none.
    case gatewayApplication(ApplicationDevice)
}


/// One record before assembly: the source record, its outputs, and the devices and policies the adapter resolved for it.
package struct ExchangeRecordDraft: Sendable {
    /// The conversion instant.
    package let instant: Date
    package let sourceRecord: SourceRecordIdentity
    /// The primary output first; members and other children follow in entry order.
    package var outputs: [ExchangeOutputDraft]
    /// The hardware the source names; the assembler renders it, with its identities, into the recording Device.
    package var recordingDevice: RecordingDevice?
    /// The peripherals that supplied the record through ``recordingDevice``. Each is a recording Device of its own, which
    /// the outputs do not reference: the Provenance's source entity names it as a performer.
    package var sourceDevices: [RecordingDevice]
    package var writer: ExchangeWriterDraft?
    /// Adapter facts about the consumed source record, independent of its author agent.
    package var sourceExtensions: [Extension]
    package var converterRole: ConverterRole

    package init(
        instant: Date,
        sourceRecord: SourceRecordIdentity,
        outputs: [ExchangeOutputDraft],
        recordingDevice: RecordingDevice? = nil,
        sourceDevices: [RecordingDevice] = [],
        writer: ExchangeWriterDraft? = nil,
        sourceExtensions: [Extension] = [],
        converterRole: ConverterRole = .assembler
    ) {
        self.instant = instant
        self.sourceRecord = sourceRecord
        self.outputs = outputs
        self.recordingDevice = recordingDevice
        self.sourceDevices = sourceDevices
        self.writer = writer
        self.sourceExtensions = sourceExtensions
        self.converterRole = converterRole
    }
}
