//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape.
// swiftlint:disable multiline_literal_brackets

import Foundation
import ModelsR4


/// Builds the one exchange graph shape every adapter emits: outputs decorated with the event's
/// identities and links, the study context, the device snapshots, the conversion Provenance, and the
/// Bundle header, in the fixed entry order the guide validates.
///
/// Every identity is minted once and its fullUrl computed once. The adapter supplies content; the
/// assembler supplies everything the graph says about the event, the producer and the record.
package struct ExchangeGraphAssembler: Sendable {
    /// What every output of one graph may link to, resolved once per graph.
    struct Surroundings {
        let subject: Reference
        let studyReferences: [Reference]
        let recordingURL: String?
        let gatewayURL: String?
        let converterURL: String
    }

    /// The device snapshots of one graph and who the Provenance names as author.
    struct Devices {
        let converter: ConverterSnapshots
        let recording: RecordingSnapshot?
        let writer: WriterSnapshots?
        let authorURL: String?

        /// Every Device entry, in its fixed order.
        var entries: [IdentifiedDevice] {
            var entries: [IdentifiedDevice] = []
            if let recording {
                entries.append(recording.device)
            }
            entries += [converter.host, converter.application]
            if let gateway = converter.gateway {
                entries.append(gateway)
            }
            return entries + (writer?.entries ?? [])
        }
    }

    struct DecoratedOutput {
        let identity: RoledIdentifier
        let url: String
        let artifact: RoledIdentifier?
        var resource: ExchangeOutputDraft.Resource
    }

    package let envelope: ExchangeEnvelope

    package init(envelope: ExchangeEnvelope) {
        self.envelope = envelope
    }

    /// Assembles, encodes and validates one event's graph.
    package func assemble(_ draft: ExchangeGraphDraft) throws -> AssembledExchangeGraph {
        guard !draft.outputs.isEmpty else {
            throw ExchangeAssemblyError.noOutputs
        }
        let studyContext = try eventContext(for: draft).studyContext()
        let devices = try resolveDevices(for: draft)
        let surroundings = Surroundings(
            subject: studyContext.subjectReference,
            studyReferences: studyContext.studyReferences,
            recordingURL: devices.recording?.url,
            gatewayURL: devices.converter.gatewayURL,
            converterURL: devices.converter.applicationURL
        )
        let outputs = try decoratedOutputs(of: draft, surroundings: surroundings)
        let provenanceNode = try EntryNodeKey(
            system: envelope.identityScope.systems.entryNode,
            event: draft.event,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        var provenance = try provenance(
            sourceIdentifier: draft.sourceRecord.identifier.fhirIdentifier,
            targetURLs: outputs.map(\.url),
            converterURL: devices.converter.applicationURL,
            authorURL: devices.authorURL,
            recordedAt: draft.instant
        )
        provenance.id = draft.repositoryIDs[.provenance]?.primitive

        var entries = try outputs.map { try BundleEntry(identifier: $0.identity, resource: $0.resource.proxy) }
        entries.append(contentsOf: studyContext.allEntries)
        entries.append(contentsOf: try devices.entries.map { try BundleEntry(identifier: $0.identity, resource: ResourceProxy(with: $0.resource)) })
        entries.append(try BundleEntry(identifier: provenanceNode.identifier, resource: ResourceProxy(with: provenance)))
        return AssembledExchangeGraph(
            graph: try graph(entries: entries, draft: draft),
            identifiers: ExchangeGraphIdentifiers(
                event: draft.event.identifier,
                sourceRecord: draft.sourceRecord.identifier,
                primaryOutput: outputs[0].identity,
                applicationSnapshot: devices.converter.application.identity,
                hostSnapshot: devices.converter.host.identity,
                provenance: provenanceNode.identifier,
                childOutputs: outputs.dropFirst().map(\.identity),
                sourceArtifact: outputs[0].artifact,
                recordingDeviceSnapshot: devices.recording?.device.identity,
                writerSnapshot: devices.writer?.application.identity,
                writerHostSnapshot: devices.writer?.entries.isEmpty == false ? devices.writer?.host.identity : nil
            )
        )
    }

    /// The validated graph of one event's entries, in the order given.
    private func graph(entries: [BundleEntry], draft: ExchangeGraphDraft) throws -> ExchangeGraph {
        var bundle = Bundle(
            entry: entries,
            identifier: draft.event.identifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(utc: draft.instant)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = draft.repositoryIDs[.bundle]?.primitive
        return try ExchangeGraph(kind: .active, eventIdentifier: draft.event, bundle: bundle)
    }

    /// The context the study entries are minted from; the subject and enrollments never vary per event.
    private func eventContext(for draft: ExchangeGraphDraft) -> ExchangeEventContext {
        ExchangeEventContext(
            subject: envelope.subject,
            event: draft.event,
            identityScope: envelope.identityScope,
            repositoryScope: envelope.repositoryScope,
            application: envelope.application,
            host: envelope.host,
            conversionInstant: draft.instant,
            converterRole: draft.converterRole,
            studies: envelope.studies,
            repositoryIDs: draft.repositoryIDs
        )
    }
}


// MARK: - Outputs

extension ExchangeGraphAssembler {
    private static let manualEntry = Extension(
        url: Canonicals.recordingMethod,
        value: .coding(Coding(code: "manual-entry", display: "Manual entry", system: Canonicals.recordingMethodCodeSystem))
    )

    /// Every output with its identities and links applied; in-graph members are linked from the primary.
    private func decoratedOutputs(of draft: ExchangeGraphDraft, surroundings: Surroundings) throws -> [DecoratedOutput] {
        var outputs: [DecoratedOutput] = []
        for (index, output) in draft.outputs.enumerated() {
            outputs.append(try decorate(output, isPrimary: index == 0, draft: draft, surroundings: surroundings))
        }
        let primaryURL = outputs[0].url
        for (index, output) in draft.outputs.enumerated() where output.derivedFromPrimary && index > 0 {
            if case .observation(var observation) = outputs[index].resource {
                observation.derivedFrom = [Reference(reference: primaryURL.asFHIRStringPrimitive())]
                outputs[index].resource = .observation(observation)
            }
        }
        let memberURLs = zip(draft.outputs, outputs).filter { $0.0.memberOfPrimary }.map(\.1.url)
        if !memberURLs.isEmpty, case .observation(var observation) = outputs[0].resource {
            observation.hasMember = (observation.hasMember ?? []) + memberURLs.map { Reference(reference: $0.asFHIRStringPrimitive()) }
            outputs[0].resource = .observation(observation)
        }
        return outputs
    }

    private func decorate(
        _ output: ExchangeOutputDraft,
        isPrimary: Bool,
        draft: ExchangeGraphDraft,
        surroundings: Surroundings
    ) throws -> DecoratedOutput {
        let identity = try draft.sourceRecord.output(role: output.role, discriminator: output.discriminator)
        let artifact = try output.artifactFormatCode.map { try draft.sourceRecord.artifact(formatCode: $0, partIndex: 0) }
        let writerRecord = try output.writerRecord.map(writerRecordIdentity)
        var identifiers = [draft.sourceRecord.identifier.fhirIdentifier, identity.fhirIdentifier]
        if let artifact {
            identifiers.append(artifact.fhirIdentifier)
        }
        identifiers += output.clearIdentifiers
        if let writerRecord {
            identifiers.append(writerRecord.identity.fhirIdentifier)
        }
        let repositoryID = isPrimary ? draft.repositoryIDs[.primaryOutput]?.primitive : nil
        let resource: ExchangeOutputDraft.Resource
        switch output.resource {
        case .observation(var observation):
            observation.id = repositoryID
            observation.identifier = identifiers
            decorate(&observation, links: output.links, wasUserEntered: output.wasUserEntered, surroundings: surroundings)
            if let writerRecord {
                observation.extension.append(Extension(
                    url: Canonicals.writerRecordVersion,
                    value: .string(writerRecord.version.asFHIRStringPrimitive())
                ))
            }
            resource = .observation(observation)
        case .document(var document):
            document.id = repositoryID
            document.identifier = identifiers
            document.date = FHIRPrimitive(try Instant(utc: draft.instant))
            decorate(&document, links: output.links, surroundings: surroundings)
            resource = .document(document)
        }
        return DecoratedOutput(identity: identity, url: try identity.fullURLString, artifact: artifact, resource: resource)
    }

    private func decorate(
        _ observation: inout Observation,
        links: ExchangeOutputDraft.Links,
        wasUserEntered: Bool,
        surroundings: Surroundings
    ) {
        if links.contains(.subject) {
            observation.subject = surroundings.subject
        }
        if links.contains(.recordingDevice), let recordingURL = surroundings.recordingURL {
            observation.device = Reference(reference: recordingURL.asFHIRStringPrimitive())
        }
        if links.contains(.manualEntry), wasUserEntered {
            observation.extension.replace(Self.manualEntry)
        }
        if links.contains(.gateway), let gatewayURL = surroundings.gatewayURL {
            observation.extension.replace(
                Extension(url: Canonicals.gatewayDevice, value: .reference(Reference(reference: gatewayURL.asFHIRStringPrimitive())))
            )
        }
        if links.contains(.studies) {
            for study in surroundings.studyReferences {
                observation.extension.append(Extension(url: Canonicals.researchStudy, value: .reference(study)))
            }
        }
    }

    private func decorate(_ document: inout DocumentReference, links: ExchangeOutputDraft.Links, surroundings: Surroundings) {
        if links.contains(.subject) {
            document.subject = surroundings.subject
        }
        if links.contains(.recordingDevice) {
            document.author = [surroundings.recordingURL, surroundings.converterURL].compactMap { url in
                url.map { Reference(reference: $0.asFHIRStringPrimitive()) }
            }
        }
        if links.contains(.studies), !surroundings.studyReferences.isEmpty {
            document.context = DocumentReferenceContext(related: surroundings.studyReferences)
        }
    }

    private func writerRecordIdentity(_ record: ExchangeOutputDraft.WriterRecord) throws -> (identity: RoledIdentifier, version: String) {
        let identity = try envelope.identityScope.writerRecord(
            writerApplication: BusinessIdentifier(
                system: IdentifierSystem(Canonicals.appleBundleIdentifierSystem),
                value: record.writerApplication
            ),
            writerRecordID: record.syncIdentifier
        )
        return (identity, record.version)
    }
}


// MARK: - Provenance

extension ExchangeGraphAssembler {
    private func provenance(
        sourceIdentifier: Identifier,
        targetURLs: [String],
        converterURL: String,
        authorURL: String?,
        recordedAt: Date
    ) throws -> Provenance {
        var entity = ProvenanceEntity(role: FHIRPrimitive(.source), what: Reference(identifier: sourceIdentifier))
        entity.agent = authorURL.map { url in
            [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(code: "author", display: "Author", system: Canonicals.provenanceParticipantType)]),
                who: Reference(reference: url.asFHIRStringPrimitive())
            )]
        }
        return Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform",
                display: "Transform/Translate Record Lifecycle Event",
                system: Canonicals.isoLifecycleEvent
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(code: "assembler", display: "Assembler", system: Canonicals.provenanceParticipantType)]),
                who: Reference(reference: converterURL.asFHIRStringPrimitive())
            )],
            entity: [entity],
            meta: Meta(profile: [envelope.adapter.provenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(utc: recordedAt))),
            recorded: FHIRPrimitive(try Instant(utc: recordedAt)),
            target: targetURLs.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        )
    }
}


extension ExchangeOutputDraft.Resource {
    var proxy: ResourceProxy {
        switch self {
        case .observation(let observation): ResourceProxy(with: observation)
        case .document(let document): ResourceProxy(with: document)
        }
    }
}


extension Optional where Wrapped == [Extension] {
    /// Appends `extension`, creating the array.
    mutating func append(_ extension: Extension) {
        self = (self ?? []) + [`extension`]
    }

    /// Replaces every extension of the same url with `extension`, or appends it.
    mutating func replace(_ extension: Extension) {
        var extensions = self ?? []
        extensions.removeAll { $0.url == `extension`.url }
        extensions.append(`extension`)
        self = extensions
    }
}

// swiftlint:enable multiline_literal_brackets
