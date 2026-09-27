//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    struct WriterDevices {
        let application: IdentifiedDevice
        let host: IdentifiedDevice?

        /// The writer snapshots the graph carries as entries of their own. A snapshot the converter already
        /// states is that entry, and the host of a writer that is the converter's application has nothing to connect to.
        func entries(excluding stated: Set<RoledIdentifier>) -> [IdentifiedDevice] {
            guard !stated.contains(application.identity) else {
                return []
            }
            return [host].compactMap(\.self).filter { !stated.contains($0.identity) } + [application]
        }
    }

    private struct AssembledGraphResources {
        let observation: Observation
        let provenance: Provenance
        let children: [GraphChildOutput]
    }

    /// The identity, device, study and provenance surroundings every emitted graph shares.
    ///
    /// Resolved from the source sample before the record's own resource exists, so an Observation
    /// graph and a recording-document graph agree on identity by construction rather than through
    /// two implementations that have to be kept in step.
    struct GraphEnvelope {
        let source: HealthKitSourceRecord
        let sourceRecord: SourceRecordIdentity
        let primary: RoledIdentifier
        let provenanceNode: EntryNodeKey
        let converterApplication: IdentifiedDevice
        let converterHost: IdentifiedDevice
        let gatewayApplication: IdentifiedDevice?
        let recordingDevice: IdentifiedDevice?
        let writer: WriterDevices?
        let writerEntries: [IdentifiedDevice]
        let studyContext: StudyContext
        let primaryURL: String
        let converterURL: String
        let gatewayURL: String?
        let recordingDeviceURL: String?
        let writerURL: String?
        let warnings: [HealthKitConversionWarning]

        var graphContext: HealthKitGraphContext {
            HealthKitGraphContext(
                subject: studyContext.subjectReference,
                recordingDeviceURL: recordingDeviceURL,
                gatewayURL: gatewayURL,
                studyReferences: studyContext.studyReferences
            )
        }
    }

    /// One secondary source output and the relationship, if any, the primary output publishes.
    struct GraphChildOutput {
        enum PrimaryRelationship: Equatable {
            case hasMember
            case none
        }

        let identity: RoledIdentifier
        let observation: Observation
        let primaryRelationship: PrimaryRelationship
    }

    private struct SourceIdentities {
        let sourceRecord: SourceRecordIdentity
        let primary: RoledIdentifier
        let provenanceNode: EntryNodeKey
    }

    private struct ConverterSnapshots {
        let host: IdentifiedDevice
        let application: IdentifiedDevice
        let applicationURL: String
        /// A distinct application that mediated the measurement; the converter itself when it did.
        let gateway: IdentifiedDevice?
        let gatewayURL: String?

        var identities: Set<RoledIdentifier> {
            Set([host, application, gateway].compactMap { $0?.identity })
        }
    }

    /// Resolves all graph identities and device snapshots as one transaction.
    static func graphEnvelope(
        for sample: HKSample,
        context: HealthKitConversionContext,
        outputRole: String,
        outputDiscriminator: String = "single"
    ) throws -> GraphEnvelope {
        guard let type = HealthKitSourceType(sample) else {
            throw HealthKitConversionError.unregisteredSourceType(sample.sampleType.identifier)
        }
        let sourceUUID = sample.uuid.uuidString.lowercased()
        let identities = try sourceIdentities(
            type: type,
            sourceUUID: sourceUUID,
            outputRole: outputRole,
            outputDiscriminator: outputDiscriminator,
            context: context
        )
        let converter = try converterSnapshots(context: context)
        let recordingDevice = try Self.recordingDevice(for: sample.device, context: context)
        let writer = try Self.writer(
            for: sample.sourceRevision,
            classification: context.options.writer,
            context: context
        )
        let writerEntries = writer?.entries(excluding: converter.identities) ?? []
        try validateRepositoryIDs(recordingDevice: recordingDevice.device, writer: writer, writerEntries: writerEntries, context: context)
        let recordingDeviceURL = try recordingDevice.device.map { try $0.identity.fullURLString }
        let writerURL = try resolvedWriterURL(
            writer,
            classification: context.options.writer,
            recordingDeviceURL: recordingDeviceURL
        )
        return GraphEnvelope(
            source: HealthKitSourceRecord(uuid: sample.uuid, type: type),
            sourceRecord: identities.sourceRecord,
            primary: identities.primary,
            provenanceNode: identities.provenanceNode,
            converterApplication: converter.application,
            converterHost: converter.host,
            gatewayApplication: converter.gateway,
            recordingDevice: recordingDevice.device,
            writer: writer,
            writerEntries: writerEntries,
            studyContext: try context.event.studyContext(),
            primaryURL: try identities.primary.fullURLString,
            converterURL: converter.applicationURL,
            gatewayURL: converter.gatewayURL,
            recordingDeviceURL: recordingDeviceURL,
            writerURL: writerURL,
            warnings: warnings(for: sample, recordingDevice: recordingDevice)
        )
    }

    private static func sourceIdentities(
        type: HealthKitSourceType,
        sourceUUID: String,
        outputRole: String,
        outputDiscriminator: String,
        context: HealthKitConversionContext
    ) throws -> SourceIdentities {
        let sourceRecord = try context.identityScope.sourceRecord(
            adapterID: HealthKitConverter.adapterID,
            sourceType: type.rawValue,
            repositoryScope: context.repositoryScope,
            nativeRecordID: sourceUUID
        )
        return SourceIdentities(
            sourceRecord: sourceRecord,
            primary: try sourceRecord.output(role: outputRole, discriminator: outputDiscriminator),
            provenanceNode: try EntryNodeKey(
                system: context.entryNodeIdentifierSystem,
                event: context.eventIdentifier,
                nodeRole: "conversion-provenance",
                ordinal: 0
            )
        )
    }

    private static func converterSnapshots(context: HealthKitConversionContext) throws -> ConverterSnapshots {
        let host = try hostSnapshot(context.event.host, repositoryID: context.repositoryID(.hostDevice), context: context)
        let application = try applicationSnapshot(
            context.event.application,
            parentURL: try host.identity.fullURLString,
            repositoryID: context.repositoryID(.applicationDevice),
            context: context
        )
        let applicationURL = try application.identity.fullURLString
        switch context.event.converterRole {
        case .assembler:
            return ConverterSnapshots(host: host, application: application, applicationURL: applicationURL, gateway: nil, gatewayURL: nil)
        case .gateway:
            return ConverterSnapshots(
                host: host, application: application, applicationURL: applicationURL, gateway: nil, gatewayURL: applicationURL
            )
        case .gatewayApplication(let gatewayApplication):
            let gateway = try applicationSnapshot(gatewayApplication, parentURL: nil, repositoryID: nil, context: context)
            return ConverterSnapshots(
                host: host,
                application: application,
                applicationURL: applicationURL,
                gateway: gateway,
                gatewayURL: try gateway.identity.fullURLString
            )
        }
    }

    /// What any graph of the sample does not carry although the sample did.
    private static func warnings(
        for sample: HKSample,
        recordingDevice: ResolvedRecordingDevice
    ) -> [HealthKitConversionWarning] {
        var warnings: [HealthKitConversionWarning] = []
        if let warning = recordingDevice.warning {
            warnings.append(warning)
        }
        let unmodeled = (sample.metadata ?? [:]).keys.filter { !HealthKitMetadataField.keys.contains($0) }.sorted()
        if !unmodeled.isEmpty {
            warnings.append(.unmodeledMetadataWithheld(keys: unmodeled))
        }
        return warnings
    }

    /// The effective elements the outputs serialized in UTC because the sample named no time zone, each once.
    private static func sourceOffsetWarnings(
        for sample: HKSample,
        outputs: [Observation]
    ) -> [HealthKitConversionWarning] {
        guard sample.metadata?[HKMetadataKeyTimeZone] == nil else {
            return []
        }
        var fields: [String] = []
        for output in outputs {
            let elements = switch output.effective {
            case .dateTime: ["Observation.effectiveDateTime"]
            case .period: ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"]
            case .instant, .timing, nil: [String]()
            }
            fields += elements.filter { !fields.contains($0) }
        }
        return fields.map { .sourceOffsetUnavailable(field: $0) }
    }

    private static func validateRepositoryIDs(
        recordingDevice: IdentifiedDevice?,
        writer: WriterDevices?,
        writerEntries: [IdentifiedDevice],
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) {
        let entries = Set(writerEntries.map(\.identity))
        if context.repositoryID(.recordingDevice) != nil, recordingDevice == nil {
            throw .repositoryIDWithoutNode(.recordingDevice)
        }
        if context.repositoryID(.writer) != nil, !entries.contains(where: { $0 == writer?.application.identity }) {
            throw .repositoryIDWithoutNode(.writer)
        }
        if context.repositoryID(.writerHost) != nil, !entries.contains(where: { $0 == writer?.host?.identity }) {
            throw .repositoryIDWithoutNode(.writerHost)
        }
    }

    private static func resolvedWriterURL(
        _ writer: WriterDevices?,
        classification: HealthKitWriter,
        recordingDeviceURL: String?
    ) throws -> String? {
        if let writer {
            return try writer.application.identity.fullURLString
        }
        return classification == .device ? recordingDeviceURL : nil
    }

    /// Builds the self-contained exchange Bundle for one source record.
    static func exchangeBundle(
        envelope: GraphEnvelope,
        primary: ResourceProxy,
        members: [(identity: RoledIdentifier, resource: ResourceProxy)] = [],
        provenance: Provenance,
        context: HealthKitConversionContext
    ) throws -> ExchangeGraph {
        var entries = [try BundleEntry(identifier: envelope.primary, resource: primary)]
        for member in members {
            entries.append(try BundleEntry(identifier: member.identity, resource: member.resource))
        }
        entries.append(contentsOf: envelope.studyContext.allEntries)
        entries.append(contentsOf: try deviceEntries(envelope: envelope))
        entries.append(try BundleEntry(
            identifier: envelope.provenanceNode.identifier,
            resource: ResourceProxy(with: provenance)
        ))

        var bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.identifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(utc: context.conversionInstant)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryID(.bundle)?.primitive
        return try ExchangeGraph(
            kind: .active,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )
    }

    /// Every Device snapshot of the graph, in its fixed entry order.
    private static func deviceEntries(envelope: GraphEnvelope) throws -> [BundleEntry] {
        var devices: [IdentifiedDevice] = []
        if let recordingDevice = envelope.recordingDevice {
            devices.append(recordingDevice)
        }
        devices.append(envelope.converterHost)
        devices.append(envelope.converterApplication)
        if let gateway = envelope.gatewayApplication {
            devices.append(gateway)
        }
        devices.append(contentsOf: envelope.writerEntries)
        return try devices.map { try BundleEntry(identifier: $0.identity, resource: ResourceProxy(with: $0.resource)) }
    }

    static func identifiers(
        envelope: GraphEnvelope,
        context: HealthKitConversionContext,
        childOutputs: [RoledIdentifier] = [],
        sourceArtifact: RoledIdentifier? = nil
    ) -> ExchangeGraphIdentifiers {
        ExchangeGraphIdentifiers(
            event: context.eventIdentifier.identifier,
            sourceRecord: envelope.sourceRecord.identifier,
            primaryOutput: envelope.primary,
            applicationSnapshot: envelope.converterApplication.identity,
            hostSnapshot: envelope.converterHost.identity,
            provenance: envelope.provenanceNode.identifier,
            childOutputs: childOutputs,
            sourceArtifact: sourceArtifact,
            recordingDeviceSnapshot: envelope.recordingDevice?.identity,
            writerSnapshot: envelope.writer?.application.identity,
            writerHostSnapshot: envelope.writerEntries.isEmpty ? nil : envelope.writer?.host?.identity
        )
    }

    static func assembleGraph(
        for sample: HKSample,
        context: HealthKitConversionContext,
        outputRole: String,
        outputDiscriminator: String = "single",
        childBuilder: ((_ envelope: GraphEnvelope) throws -> [GraphChildOutput])? = nil,
        observationBuilder: (_ graphContext: HealthKitGraphContext) throws -> Observation
    ) throws -> HealthKitConversionSet {
        let envelope = try graphEnvelope(
            for: sample,
            context: context,
            outputRole: outputRole,
            outputDiscriminator: outputDiscriminator
        )
        let resources = try assembledGraphResources(
            sample: sample,
            envelope: envelope,
            context: context,
            childBuilder: childBuilder,
            observationBuilder: observationBuilder
        )
        let graph = try exchangeBundle(
            envelope: envelope,
            primary: ResourceProxy(with: resources.observation),
            members: resources.children.map { ($0.identity, ResourceProxy(with: $0.observation)) },
            provenance: resources.provenance,
            context: context
        )
        return HealthKitConversionSet(
            primary: HealthKitConversion(
                source: envelope.source,
                identifiers: identifiers(envelope: envelope, context: context, childOutputs: resources.children.map(\.identity)),
                graph: graph,
                warnings: envelope.warnings + sourceOffsetWarnings(
                    for: sample,
                    outputs: [resources.observation] + resources.children.map(\.observation)
                )
            )
        )
    }

    private static func assembledGraphResources(
        sample: HKSample,
        envelope: GraphEnvelope,
        context: HealthKitConversionContext,
        childBuilder: ((_ envelope: GraphEnvelope) throws -> [GraphChildOutput])?,
        observationBuilder: (_ graphContext: HealthKitGraphContext) throws -> Observation
    ) throws -> AssembledGraphResources {
        var observation = try observationBuilder(envelope.graphContext)
        observation.id = context.repositoryID(.primaryOutput)?.primitive
        observation.identifier = [
            envelope.sourceRecord.identifier.fhirIdentifier,
            envelope.primary.fhirIdentifier
        ] + nativeIdentifiers(for: sample, policy: context.options.nativeIdentifierDisclosure)
        try applySyncIdentity(of: sample, to: &observation, context: context)

        var provenance = try Self.provenance(
            sourceIdentifier: envelope.sourceRecord.identifier.fhirIdentifier,
            targetURL: envelope.primaryURL,
            converterURL: envelope.converterURL,
            writerURL: envelope.writerURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryID(.provenance)?.primitive
        let children = try childBuilder?(envelope) ?? []
        try applyChildRelationships(
            children,
            primaryURL: envelope.primaryURL,
            observation: &observation,
            provenance: &provenance
        )
        return AssembledGraphResources(
            observation: observation,
            provenance: provenance,
            children: children
        )
    }

    private static func applyChildRelationships(
        _ children: [GraphChildOutput],
        primaryURL: String,
        observation: inout Observation,
        provenance: inout Provenance
    ) throws {
        let members = children.filter { $0.primaryRelationship == .hasMember }
        if !members.isEmpty {
            observation.hasMember = try members.map { member in
                Reference(reference: try member.identity.fullURLString.asFHIRStringPrimitive())
            }
        }
        provenance.target = [Reference(reference: primaryURL.asFHIRStringPrimitive())]
            + (try children.map { child in
                Reference(reference: try child.identity.fullURLString.asFHIRStringPrimitive())
            })
    }
}

#endif
