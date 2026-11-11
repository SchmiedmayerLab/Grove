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
import ThreadLocal


/// Builds the one record shape the HealthKit and SensorKit adapters emit: outputs decorated with the record's
/// identities and links, the study context, the device snapshots and the conversion Provenance, in a fixed entry order.
///
/// Every identity is minted once and its fullUrl computed once, each shared node after the nodes it references and after
/// its body is final. The adapter supplies content; the assembler supplies everything the record says about the producer
/// and its source. Questionnaire keeps its own entry list and takes the Device bodies, the conversion Provenance and
/// ``conversionRecord(provenance:sourceRecord:entries:subject:identityScope:onValidation:)`` from the assembler's builders.
package struct ExchangeGraphAssembler: Sendable {
    /// What every output of one record may link to, resolved once per record.
    struct Surroundings {
        let subject: Reference
        let studyReferences: [Reference]
        let recordingURL: String?
        /// The Device an Observation names as the one that generated its data.
        let observationDeviceURL: String?
        let gatewayURL: String?
        let converterURL: String
    }

    /// The device snapshots of one record.
    struct Devices {
        let converter: ConverterSnapshots
        let recording: IdentifiedDevice?
        /// The record's peripherals, each once; one that states ``recording``'s very content is that entry.
        let sources: [IdentifiedDevice]
        /// The record's one peripheral, when it names exactly one and that one isn't ``recording``.
        let soleSource: IdentifiedDevice?
        let writer: WriterSnapshots?

        /// Every Device entry, in its fixed order.
        var entries: [IdentifiedDevice] {
            var entries: [IdentifiedDevice] = []
            if let recording {
                entries.append(recording)
            }
            entries += sources
            entries += [converter.host, converter.application]
            if let gateway = converter.gateway {
                entries.append(gateway)
            }
            return entries + (writer?.entries ?? [])
        }

        /// The recording Device that recorded the peripherals' samples, which the source entity names as the composer so the
        /// record unit keeps it when no output references it; `nil` when the record names no peripheral.
        var composerURL: String? {
            sources.isEmpty ? nil : recording?.url
        }

        /// The links every output of a record shares, with the Device an Observation names as the one that generated its
        /// data: the sole peripheral when it supplied every sample, the recording Device otherwise.
        func surroundings(
            of studyContext: StudyContext,
            sourceDevicesSuppliedEverySample: Bool
        ) -> Surroundings {
            Surroundings(
                subject: studyContext.subjectReference,
                studyReferences: studyContext.studyReferences,
                recordingURL: recording?.url,
                observationDeviceURL: (sourceDevicesSuppliedEverySample ? soleSource ?? recording : recording)?.url,
                gatewayURL: converter.gatewayURL,
                converterURL: converter.application.url
            )
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

    /// Assembles, encodes and validates one record, handing `onValidation` how long encoding and validating took.
    package func assemble(
        _ draft: ExchangeRecordDraft,
        onValidation: ((Swift.Duration) -> Void)? = nil
    ) throws -> AssembledExchangeRecord {
        guard !draft.outputs.isEmpty else {
            throw ExchangeAssemblyError.noOutputs
        }
        let studyContext = try StudyContext(subject: envelope.subject, studies: envelope.studies, identityScope: envelope.identityScope)
        let devices = try resolveDevices(for: draft)
        let surroundings = devices.surroundings(
            of: studyContext,
            sourceDevicesSuppliedEverySample: draft.sourceDevicesSuppliedEverySample
        )
        let outputs = try decoratedOutputs(of: draft, surroundings: surroundings)
        let provenance = try Self.conversionProvenance(
            of: draft.sourceRecord,
            targetURLs: outputs.map(\.url),
            assemblerURL: devices.converter.application.url,
            // The writer application is the Provenance author; without one the Provenance names none.
            authorURL: devices.writer?.application.url,
            sourceDeviceURLs: devices.sources.map(\.url),
            composerURL: devices.composerURL,
            sourceExtensions: draft.sourceExtensions,
            profile: envelope.adapter.provenanceProfile,
            at: draft.instant
        )
        var entries = outputs.map { BundleEntry(identifier: $0.identity, fullURL: $0.url, resource: $0.resource.proxy) }
        entries.append(contentsOf: studyContext.allEntries)
        entries.append(contentsOf: devices.entries.map(\.entry))
        let record = try Self.conversionRecord(
            provenance: provenance,
            sourceRecord: draft.sourceRecord.identifier,
            entries: entries,
            subject: envelope.subject.identifier,
            identityScope: envelope.identityScope,
            onValidation: onValidation
        )
        return AssembledExchangeRecord(
            record: record,
            identifiers: ExchangeGraphIdentifiers(
                sourceRecord: draft.sourceRecord.identifier,
                primaryOutput: outputs[0].identity,
                applicationSnapshot: devices.converter.application.identity,
                hostSnapshot: devices.converter.host.identity,
                provenance: record.version.identifier,
                childOutputs: outputs.dropFirst().map(\.identity),
                sourceArtifact: outputs[0].artifact,
                recordingDeviceSnapshot: devices.recording?.identity,
                writerSnapshot: devices.writer?.application.identity,
                writerHostSnapshot: devices.writer?.entries.isEmpty == false ? devices.writer?.host.identity : nil
            )
        )
    }
}


// MARK: - Records

extension ExchangeGraphAssembler {
    /// The record of a finished conversion, the one place a record version is minted.
    ///
    /// The digest covers `provenance` and the outputs it targets as they travel, so the version is minted last; the
    /// Provenance then repeats it in `grove-record-version`, the one extension the digest leaves out.
    ///
    /// - Parameters:
    ///   - provenance: The conversion Provenance, final but for that extension.
    ///   - sourceRecord: The source record the Provenance's entity names.
    ///   - entries: Every other entry of the record, in Bundle order: its outputs and its shared nodes.
    ///   - subject: The participant the record is about.
    ///   - identityScope: The deployment's scope, whose key mints the version.
    ///   - onValidation: Told how long encoding and validating took.
    package static func conversionRecord(
        provenance: Provenance,
        sourceRecord: RoledIdentifier,
        entries: [BundleEntry],
        subject: BusinessIdentifier,
        identityScope: OpaqueIdentityScope,
        onValidation: ((Swift.Duration) -> Void)? = nil
    ) throws -> ExchangeRecord {
        let digest = try recordContentDigest(of: provenance, entries: entries)
        let key = try identityScope.recordVersion(sourceRecord: sourceRecord.identifier, contentDigest: digest)
        var keyed = provenance
        keyed.extension.append(Extension(url: Canonicals.recordVersion, value: .identifier(key.fhirIdentifier)))
        return try record(
            kind: .active,
            entries: entries + [try BundleEntry(identifier: key, resource: ResourceProxy(with: keyed))],
            timestamp: provenance.recorded,
            subject: subject,
            onValidation: onValidation
        )
    }

    /// The record of `entries` under the Provenance's recorded instant, encoded and validated as a one-record Bundle.
    static func record(
        kind: ExchangeGraph.Kind,
        entries: [BundleEntry],
        timestamp: FHIRPrimitive<Instant>,
        subject: BusinessIdentifier,
        onValidation: ((Swift.Duration) -> Void)? = nil
    ) throws(ExchangeGraphError) -> ExchangeRecord {
        let bundle = Bundle(
            entry: entries,
            meta: Meta(profile: [kind.profile]),
            timestamp: timestamp,
            type: FHIRPrimitive(.collection)
        )
        let start = onValidation == nil ? nil : ContinuousClock.now
        let graph = try ExchangeGraph(kind: kind, bundle: bundle)
        if let start {
            onValidation?(ContinuousClock.now - start)
        }
        let records = try graph.records(subject: subject)
        guard records.count == 1 else {
            throw .invalidEntries("A record states exactly one lifecycle Provenance")
        }
        return records[0]
    }

    /// The `record-content-digest` of `provenance` and the entries it targets, in target order.
    private static func recordContentDigest(of provenance: Provenance, entries: [BundleEntry]) throws -> String {
        var resources: [String: ResourceProxy] = [:]
        for entry in entries {
            resources[entry.fullUrl?.value?.url.absoluteString ?? ""] = entry.resource
        }
        var outputs: [LosslessJSONValue] = []
        for target in provenance.target {
            guard let resource = resources[target.reference?.value?.string ?? ""] else {
                throw ExchangeGraphError.ruleViolation(.mobileExchangeResolvedReference)
            }
            outputs.append(try LosslessJSONValue(encoding: resource))
        }
        return try LosslessJSONValue.recordContentDigest(provenance: LosslessJSONValue(encoding: provenance), outputs: outputs)
    }
}


// MARK: - Outputs

extension ExchangeGraphAssembler {
    private static let manualEntry = Extension(
        url: Canonicals.recordingMethod,
        value: .coding(Coding(code: "manual-entry", display: "Manual entry", system: Canonicals.recordingMethodCodeSystem))
    )

    /// Every output with its identities and links applied; a derived child names the primary it derives from.
    private func decoratedOutputs(of draft: ExchangeRecordDraft, surroundings: Surroundings) throws -> [DecoratedOutput] {
        var outputs = try draft.outputs.map { try decorate($0, draft: draft, surroundings: surroundings) }
        let primaryURL = outputs[0].url
        for (index, output) in draft.outputs.enumerated() where output.derivedFromPrimary && index > 0 {
            if case .observation(var observation) = outputs[index].resource {
                observation.derivedFrom = [Reference(reference: primaryURL.asFHIRStringPrimitive())]
                outputs[index].resource = .observation(observation)
            }
        }
        let members = zip(draft.outputs, outputs).filter { $0.0.memberOfPrimary }.map(\.1.url)
        if !members.isEmpty, case .observation(var observation) = outputs[0].resource {
            observation.hasMember = (observation.hasMember ?? []) + members.map {
                Reference(reference: $0.asFHIRStringPrimitive(), type: "Observation".asFHIRURIPrimitive())
            }
            outputs[0].resource = .observation(observation)
        }
        return outputs
    }

    private func decorate(
        _ output: ExchangeOutputDraft,
        draft: ExchangeRecordDraft,
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
        if links.contains(.recordingDevice), let deviceURL = surroundings.observationDeviceURL {
            observation.device = Reference(reference: deviceURL.asFHIRStringPrimitive())
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
            subject: envelope.subject.identifier,
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
    /// The FHIR forms of the last conversion instant one thread stated, kept because every record of one call shares its
    /// instant and a FHIR instant or dateTime is built by parsing its lexeme.
    private final class ConversionTimes {
        private struct Forms {
            let milliseconds: Int64
            let offsetMinutes: Int64
            let recorded: Instant
            let occurred: DateTime
        }

        private var last: Forms?

        /// `instant` in UTC, for `Provenance.recorded`, and at `occurredOffset`'s offset, for `Provenance.occurred`:
        /// exactly what ``ExchangeInstant`` states for it.
        func forms(of instant: Date, occurredOffset: TimeZone) throws -> (recorded: Instant, occurred: DateTime) {
            let milliseconds = ExchangeInstant.millisecondsSinceEpoch(instant)
            let offsetMinutes = Int64(occurredOffset.secondsFromGMT(for: instant) / 60)
            if let last, last.milliseconds == milliseconds, last.offsetMinutes == offsetMinutes {
                return (last.recorded, last.occurred)
            }
            let forms = Forms(
                milliseconds: milliseconds,
                offsetMinutes: offsetMinutes,
                recorded: try ExchangeInstant.fhirInstant(instant),
                occurred: try ExchangeInstant.fhirDateTime(instant, offsetIn: occurredOffset)
            )
            last = forms
            return (forms.recorded, forms.occurred)
        }
    }

    @ThreadLocal private static var conversionTimes: ConversionTimes = .init()

    /// The conversion Provenance as every record states it: the transform activity, the converting application as the
    /// assembler agent, the source record as the entity, with the writer that authored it and the peripherals that supplied
    /// it when the record names them, and every output as a target. It carries no `grove-record-version` yet: that repeats a
    /// digest over this very resource.
    ///
    /// `recorded` states the conversion instant in UTC and `occurred` the same instant at `occurredOffset`'s offset: UTC
    /// in the assembler's records, the response's authored offset in Questionnaire's.
    ///
    /// - Parameters:
    ///   - source: The record the outputs were converted from.
    ///   - targetURLs: The fullUrl of every output, in entry order.
    ///   - assemblerURL: The fullUrl of the converting application's snapshot.
    ///   - authorURL: The fullUrl of the writer application's snapshot when the record names its author.
    ///   - sourceDeviceURLs: The fullUrl of each peripheral that supplied the source record.
    ///   - composerURL: The fullUrl of the recording Device that recorded the peripherals' samples, when there are any.
    ///   - profile: The adapter's conversion Provenance profile.
    ///   - instant: The conversion instant.
    ///   - occurredOffset: The zone whose offset `occurred` states the instant at.
    package static func conversionProvenance(
        of source: SourceRecordIdentity,
        targetURLs: [String],
        assemblerURL: String,
        authorURL: String? = nil,
        sourceDeviceURLs: [String] = [],
        composerURL: String? = nil,
        sourceExtensions: [Extension] = [],
        profile: FHIRPrimitive<Canonical>,
        at instant: Date,
        occurredOffset: TimeZone = .utc
    ) throws -> Provenance {
        let times = try conversionTimes.forms(of: instant, occurredOffset: occurredOffset)
        var entity = ProvenanceEntity(role: FHIRPrimitive(.source), what: Reference(identifier: source.identifier.fhirIdentifier))
        entity.extension = sourceExtensions.isEmpty ? nil : sourceExtensions
        let agents = [authorURL].compactMap { $0 }.map { sourceAgent($0, code: "author", display: "Author") }
            + sourceDeviceURLs.map { sourceAgent($0, code: "performer", display: "Performer") }
            + [composerURL].compactMap { $0 }.map { sourceAgent($0, code: "composer", display: "Composer") }
        entity.agent = agents.isEmpty ? nil : agents
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
            occurred: .dateTime(FHIRPrimitive(times.occurred)),
            recorded: FHIRPrimitive(times.recorded),
            target: targetURLs.map { Reference(reference: $0.asFHIRStringPrimitive()) }
        )
    }

    private static func sourceAgent(_ url: String, code: FHIRPrimitive<FHIRString>, display: FHIRPrimitive<FHIRString>) -> ProvenanceAgent {
        ProvenanceAgent(
            type: CodeableConcept(coding: [Coding(code: code, display: display, system: Canonicals.provenanceParticipantType)]),
            who: Reference(reference: url.asFHIRStringPrimitive())
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
