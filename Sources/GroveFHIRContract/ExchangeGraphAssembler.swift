//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape.
// swiftlint:disable multiline_literal_brackets

package import Foundation
package import ModelsR4


/// Builds the one exchange graph shape the HealthKit and SensorKit adapters emit: outputs decorated with the
/// event's identities and links, the study context, the device snapshots, the conversion Provenance, and the
/// Bundle header, in the fixed entry order the guide validates.
///
/// Every identity is minted once and its fullUrl computed once. The adapter supplies content; the
/// assembler supplies everything the graph says about the event, the producer and the record. Questionnaire keeps
/// its own entry list and takes only the Device bodies and the conversion Provenance from the assembler's builders.
package struct ExchangeGraphAssembler: Sendable {
    /// What every output of one graph may link to, resolved once per graph.
    struct Surroundings {
        let subject: Reference
        let studyReferences: [Reference]
        let recordingURL: String?
        let gatewayURL: String?
        let converterURL: String
    }

    /// The device snapshots of one graph.
    struct Devices {
        let converter: ConverterSnapshots
        let recording: RecordingSnapshot?
        let writer: WriterSnapshots?

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

    /// The revision of the graphs this assembler builds. Bump it whenever the bytes it emits can change for
    /// equal inputs: it enters every exporter's context fingerprint, so an event reserved under an older
    /// revision is never redelivered under the same identifier with different bytes.
    package static let outputRevision: UInt = 1

    package let envelope: ExchangeEnvelope

    package init(envelope: ExchangeEnvelope) {
        self.envelope = envelope
    }

    /// Assembles, encodes and validates one event's graph, handing `onValidation` how long encoding and validating took.
    package func assemble(
        _ draft: ExchangeGraphDraft,
        onValidation: ((Swift.Duration) -> Void)? = nil
    ) throws -> AssembledExchangeGraph {
        guard !draft.outputs.isEmpty else {
            throw ExchangeAssemblyError.noOutputs
        }
        let studyContext = try StudyContext(
            subject: envelope.subject, studies: envelope.studies, event: draft.event, identityScope: envelope.identityScope
        )
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
        let provenance = try Self.conversionProvenance(
            of: draft.sourceRecord,
            targetURLs: outputs.map(\.url),
            assemblerURL: devices.converter.applicationURL,
            // The writer application is the Provenance author; without one the Provenance names none.
            authorURL: devices.writer?.applicationURL,
            profile: envelope.adapter.provenanceProfile,
            at: draft.instant
        )

        var entries = outputs.map { BundleEntry(identifier: $0.identity, fullURL: $0.url, resource: $0.resource.proxy) }
        entries.append(contentsOf: studyContext.allEntries)
        entries.append(contentsOf: try devices.entries.map { try BundleEntry(identifier: $0.identity, resource: ResourceProxy(with: $0.resource)) })
        entries.append(try BundleEntry(identifier: provenanceNode.identifier, resource: ResourceProxy(with: provenance)))
        return AssembledExchangeGraph(
            graph: try graph(entries: entries, draft: draft, timestamp: provenance.recorded, onValidation: onValidation),
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

    /// The validated graph of one event's entries, in the order given, stamped `timestamp`: the conversion instant, as
    /// the conversion Provenance already records it.
    private func graph(
        entries: [BundleEntry],
        draft: ExchangeGraphDraft,
        timestamp: FHIRPrimitive<Instant>,
        onValidation: ((Swift.Duration) -> Void)?
    ) throws -> ExchangeGraph {
        var bundle = Bundle(
            entry: entries,
            identifier: draft.event.identifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: timestamp,
            type: FHIRPrimitive(.collection)
        )
        bundle.id = draft.bundleID?.primitive
        guard let onValidation else {
            return try ExchangeGraph(kind: .active, eventIdentifier: draft.event, bundle: bundle)
        }
        let start = ContinuousClock.now
        let graph = try ExchangeGraph(kind: .active, eventIdentifier: draft.event, bundle: bundle)
        onValidation(ContinuousClock.now - start)
        return graph
    }
}


// MARK: - Outputs

extension ExchangeGraphAssembler {
    private static let manualEntry = Extension(
        url: Canonicals.recordingMethod,
        value: .coding(Coding(code: "manual-entry", display: "Manual entry", system: Canonicals.recordingMethodCodeSystem))
    )

    /// Every output with its identities and links applied; a derived child names the primary it derives from.
    private func decoratedOutputs(of draft: ExchangeGraphDraft, surroundings: Surroundings) throws -> [DecoratedOutput] {
        var outputs = try draft.outputs.map { try decorate($0, draft: draft, surroundings: surroundings) }
        let primaryURL = outputs[0].url
        for (index, output) in draft.outputs.enumerated() where output.derivedFromPrimary && index > 0 {
            if case .observation(var observation) = outputs[index].resource {
                observation.derivedFrom = [Reference(reference: primaryURL.asFHIRStringPrimitive())]
                outputs[index].resource = .observation(observation)
            }
        }
        return outputs
    }

    private func decorate(
        _ output: ExchangeOutputDraft,
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
        let resource: ExchangeOutputDraft.Resource
        switch output.resource {
        case .observation(var observation):
            observation.identifier = identifiers
            decorate(&observation, links: output.links, wasUserEntered: output.wasUserEntered, surroundings: surroundings)
            if let writerRecord {
                observation.extension.append(Extension(
                    url: Canonicals.writerRecordVersion,
                    value: .string(writerRecord.version.asFHIRStringPrimitive())
                ))
            }
            output.trailingExtensions.forEach { observation.extension.append($0) }
            resource = .observation(observation)
        case .document(var document):
            document.identifier = identifiers
            document.date = FHIRPrimitive(try ExchangeInstant.fhirInstant(draft.instant))
            decorate(&document, links: output.links, surroundings: surroundings)
            output.trailingExtensions.forEach { document.extension.append($0) }
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
            // The studies follow whatever context the adapter stated, such as a period or its own related outputs.
            var context = document.context ?? DocumentReferenceContext()
            context.related = (context.related ?? []) + surroundings.studyReferences
            document.context = context
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
    /// The conversion Provenance as every exchange graph states it: the transform activity, the converting application as
    /// the assembler agent, the source record as the entity, with the writer that authored it when the graph names one, and
    /// every output as a target.
    ///
    /// `recorded` states the conversion instant in UTC and `occurred` the same instant at `occurredOffset`'s offset: UTC
    /// in the assembler's graphs, the response's authored offset in Questionnaire's.
    ///
    /// - Parameters:
    ///   - source: The record the outputs were converted from.
    ///   - targetURLs: The fullUrl of every output, in entry order.
    ///   - assemblerURL: The fullUrl of the converting application's snapshot.
    ///   - authorURL: The fullUrl of the writer application's snapshot when the graph names the record's author.
    ///   - profile: The adapter's conversion Provenance profile.
    ///   - instant: The conversion instant, the event reservation's millisecond.
    ///   - occurredOffset: The zone whose offset `occurred` states the instant at.
    package static func conversionProvenance(
        of source: SourceRecordIdentity,
        targetURLs: [String],
        assemblerURL: String,
        authorURL: String? = nil,
        profile: FHIRPrimitive<Canonical>,
        at instant: Date,
        occurredOffset: TimeZone = .utc
    ) throws -> Provenance {
        var entity = ProvenanceEntity(role: FHIRPrimitive(.source), what: Reference(identifier: source.identifier.fhirIdentifier))
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
                who: Reference(reference: assemblerURL.asFHIRStringPrimitive())
            )],
            entity: [entity],
            meta: Meta(profile: [profile]),
            occurred: .dateTime(FHIRPrimitive(try ExchangeInstant.fhirDateTime(instant, offsetIn: occurredOffset))),
            recorded: FHIRPrimitive(try ExchangeInstant.fhirInstant(instant)),
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
