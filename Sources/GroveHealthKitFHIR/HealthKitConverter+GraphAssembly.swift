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
    struct SourceAuthorDevices {
        var author: IdentifiedDevice
        var host: IdentifiedDevice?
    }

    private struct GraphIdentities {
        let sourceUUID: String
        let sourceRecord: BusinessIdentifier
        let primary: BusinessIdentifier
        let provenanceNode: ExchangeNodeKey
    }

    private struct AssembledGraphResources {
        let observation: Observation
        let provenance: Provenance
        let children: [GraphChildOutput]
    }

    /// The identity, device, and provenance surroundings every emitted graph shares.
    ///
    /// Resolved from the source sample before the record's own resource exists, so an Observation
    /// graph and a recording-document graph agree on identity by construction rather than through
    /// two implementations that have to be kept in step.
    struct GraphEnvelope {
        let sourceUUID: String
        let sourceRecord: BusinessIdentifier
        let primary: BusinessIdentifier
        let provenanceNode: ExchangeNodeKey
        let converterApplication: IdentifiedDevice
        let converterHost: IdentifiedDevice
        let recordingDevice: IdentifiedDevice?
        let sourceAuthor: SourceAuthorDevices?
        let primaryURL: String
        let converterURL: String
        let recordingDeviceURL: String?
        let sourceAuthorURL: String?
    }

    /// One secondary source output and the relationship, if any, the primary output publishes.
    struct GraphChildOutput {
        enum PrimaryRelationship: Equatable {
            case hasMember
            case none
        }

        let identity: BusinessIdentifier
        let observation: Observation
        let primaryRelationship: PrimaryRelationship
    }

    /// Resolves all graph identities and device snapshots as one transaction.
    static func graphEnvelope(
        for sample: HKSample,
        context: HealthKitConversionContext,
        outputRole: String,
        outputDiscriminator: String = "single"
    ) throws -> GraphEnvelope {
        let identities = try graphIdentities(
            for: sample,
            context: context,
            outputRole: outputRole,
            outputDiscriminator: outputDiscriminator
        )
        let converterHost = try converterHost(context: context)
        let converterHostURL = try ExchangeIdentity.fullURL(for: converterHost.identity)
        let converterApplication = try converterApplication(context: context, hostURL: converterHostURL)
        var recordingDevice = try Self.recordingDevice(for: sample.device, context: context)
        var sourceAuthor = try Self.sourceAuthor(
            for: sample.sourceRevision,
            classification: context.sourceActor,
            context: context
        )
        try applySupportRepositoryIDs(
            recordingDevice: &recordingDevice,
            sourceAuthor: &sourceAuthor,
            context: context
        )
        let recordingDeviceURL = try recordingDevice.map { try ExchangeIdentity.fullURL(for: $0.identity) }
        let sourceAuthorURL = try resolvedSourceAuthorURL(
            sourceAuthor,
            sourceActor: context.sourceActor,
            recordingDeviceURL: recordingDeviceURL
        )
        return GraphEnvelope(
            sourceUUID: identities.sourceUUID,
            sourceRecord: identities.sourceRecord,
            primary: identities.primary,
            provenanceNode: identities.provenanceNode,
            converterApplication: converterApplication,
            converterHost: converterHost,
            recordingDevice: recordingDevice,
            sourceAuthor: sourceAuthor,
            primaryURL: try ExchangeIdentity.fullURL(for: identities.primary),
            converterURL: try ExchangeIdentity.fullURL(for: converterApplication.identity),
            recordingDeviceURL: recordingDeviceURL,
            sourceAuthorURL: sourceAuthorURL
        )
    }

    private static func graphIdentities(
        for sample: HKSample,
        context: HealthKitConversionContext,
        outputRole: String,
        outputDiscriminator: String
    ) throws -> GraphIdentities {
        let sourceUUID = sample.uuid.uuidString.lowercased()
        let sourceType = sample.sampleType.identifier
        let sourceRecord = try context.identityScope.sourceRecord(
            adapterID: HealthKitConverter.adapterID,
            sourceType: sourceType,
            repositoryScope: context.repositoryScope,
            nativeRecordID: sourceUUID
        )
        let primaryIdentity = try context.identityScope.sourceOutput(
            adapterID: HealthKitConverter.adapterID,
            sourceType: sourceType,
            repositoryScope: context.repositoryScope,
            nativeRecordID: sourceUUID,
            outputRole: outputRole,
            outputDiscriminator: outputDiscriminator
        )
        let provenanceNode = try ExchangeNodeKey(
            system: context.entryNodeIdentifierSystem,
            eventIdentifier: context.eventIdentifier,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        return GraphIdentities(
            sourceUUID: sourceUUID,
            sourceRecord: sourceRecord,
            primary: primaryIdentity,
            provenanceNode: provenanceNode
        )
    }

    private static func converterHost(
        context: HealthKitConversionContext
    ) throws -> IdentifiedDevice {
        let converterHostIdentity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .host,
            sourceDeviceToken: context.converterHost.sourceDeviceToken
        )
        var converterHostResource = hostDevice(context.converterHost)
        converterHostResource.id = context.repositoryIDs.converterHost?.primitive
        converterHostResource.identifier = [converterHostIdentity.fhirIdentifier]
        let converterHost = IdentifiedDevice(
            resource: converterHostResource,
            identity: converterHostIdentity
        )
        return converterHost
    }

    private static func converterApplication(
        context: HealthKitConversionContext,
        hostURL: String
    ) throws -> IdentifiedDevice {
        let converterIdentity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .application,
            sourceDeviceToken: context.converter.bundleIdentifier
        )
        var converterApplicationResource = applicationDevice(context.converter)
        converterApplicationResource.id = context.repositoryIDs.converterApplication?.primitive
        converterApplicationResource.identifier = [converterIdentity.fhirIdentifier]
            + (converterApplicationResource.identifier ?? [])
        converterApplicationResource.parent = Reference(reference: hostURL.asFHIRStringPrimitive())
        return IdentifiedDevice(
            resource: converterApplicationResource,
            identity: converterIdentity
        )
    }

    private static func applySupportRepositoryIDs(
        recordingDevice: inout IdentifiedDevice?,
        sourceAuthor: inout SourceAuthorDevices?,
        context: HealthKitConversionContext
    ) throws {
        recordingDevice?.resource.id = context.repositoryIDs.recordingDevice?.primitive
        if context.repositoryIDs.recordingDevice != nil, recordingDevice == nil {
            throw HealthKitConversionError.invalidExchangeIdentity(
                "a recording-device repository id was supplied, but this record has no recording device"
            )
        }
        if context.repositoryIDs.sourceAuthor != nil, sourceAuthor == nil {
            throw HealthKitConversionError.invalidExchangeIdentity(
                "a source-author repository id was supplied, but this record's source carries no describable identity"
            )
        }
        if context.repositoryIDs.sourceAuthorHost != nil, sourceAuthor?.host == nil {
            throw HealthKitConversionError.invalidExchangeIdentity(
                "a source-author-host repository id was supplied, but this source actor has no host snapshot"
            )
        }

        sourceAuthor?.author.resource.id = context.repositoryIDs.sourceAuthor?.primitive
        sourceAuthor?.host?.resource.id = context.repositoryIDs.sourceAuthorHost?.primitive
    }

    private static func resolvedSourceAuthorURL(
        _ sourceAuthor: SourceAuthorDevices?,
        sourceActor: HealthKitSourceActor,
        recordingDeviceURL: String?
    ) throws -> String? {
        if let sourceAuthor {
            return try ExchangeIdentity.fullURL(for: sourceAuthor.author.identity)
        }
        return sourceActor == .device ? recordingDeviceURL : nil
    }

    /// Builds the self-contained exchange Bundle for one source record.
    static func exchangeBundle(
        envelope: GraphEnvelope,
        primary: ResourceProxy,
        members: [(identity: BusinessIdentifier, resource: ResourceProxy)] = [],
        provenance: Provenance,
        context: HealthKitConversionContext
    ) throws -> ExchangeGraph {
        var entries = [try ExchangeIdentity.entry(identifier: envelope.primary, resource: primary)]
        for member in members {
            entries.append(try ExchangeIdentity.entry(identifier: member.identity, resource: member.resource))
        }
        if let recordingDevice = envelope.recordingDevice {
            entries.append(try ExchangeIdentity.entry(
                identifier: recordingDevice.identity,
                resource: ResourceProxy(with: recordingDevice.resource)
            ))
        }
        entries.append(try ExchangeIdentity.entry(
            identifier: envelope.converterHost.identity,
            resource: ResourceProxy(with: envelope.converterHost.resource)
        ))
        entries.append(try ExchangeIdentity.entry(
            identifier: envelope.converterApplication.identity,
            resource: ResourceProxy(with: envelope.converterApplication.resource)
        ))
        if let sourceAuthor = envelope.sourceAuthor {
            if let host = sourceAuthor.host {
                entries.append(try ExchangeIdentity.entry(
                    identifier: host.identity,
                    resource: ResourceProxy(with: host.resource)
                ))
            }
            entries.append(try ExchangeIdentity.entry(
                identifier: sourceAuthor.author.identity,
                resource: ResourceProxy(with: sourceAuthor.author.resource)
            ))
        }
        entries.append(try ExchangeIdentity.entry(
            nodeKey: envelope.provenanceNode,
            resource: ResourceProxy(with: provenance)
        ))

        var bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.businessIdentifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.conversionInstant)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive
        return try ExchangeGraph(
            kind: .active,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )
    }

    static func assembleGraph(
        for sample: HKSample,
        context: HealthKitConversionContext,
        outputRole: String,
        outputDiscriminator: String = "single",
        childBuilder: ((_ envelope: GraphEnvelope) throws -> [GraphChildOutput])? = nil,
        observationBuilder: (_ recordingDeviceURL: String?, _ converterURL: String) throws -> Observation
    ) throws -> HealthKitConversion {
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
        return HealthKitConversion(
            localSourceUUID: sample.uuid,
            localSourceTypeIdentifier: sample.sampleType.identifier,
            subjectIdentity: context.subjectIdentity,
            repositoryScope: context.repositoryScope,
            sourceIdentifier: envelope.sourceRecord.fhirIdentifier,
            graphIdentifiers: HealthKitGraphIdentifiers(
                event: context.eventIdentifier.businessIdentifier,
                sourceRecord: envelope.sourceRecord,
                primaryOutput: envelope.primary,
                childOutputs: resources.children.map(\.identity),
                recordingDeviceSnapshot: envelope.recordingDevice?.identity,
                converterApplicationSnapshot: envelope.converterApplication.identity,
                converterHostSnapshot: envelope.converterHost.identity,
                sourceAuthorSnapshot: envelope.sourceAuthor?.author.identity,
                sourceAuthorHostSnapshot: envelope.sourceAuthor?.host?.identity,
                provenance: envelope.provenanceNode.identifier
            ),
            observation: resources.observation,
            recordingDevice: envelope.recordingDevice?.resource,
            converterApplication: envelope.converterApplication.resource,
            converterHost: envelope.converterHost.resource,
            sourceAuthor: envelope.sourceAuthor?.author.resource,
            sourceAuthorHost: envelope.sourceAuthor?.host?.resource,
            provenance: resources.provenance,
            graph: graph
        )
    }

    private static func assembledGraphResources(
        sample: HKSample,
        envelope: GraphEnvelope,
        context: HealthKitConversionContext,
        childBuilder: ((_ envelope: GraphEnvelope) throws -> [GraphChildOutput])?,
        observationBuilder: (_ recordingDeviceURL: String?, _ converterURL: String) throws -> Observation
    ) throws -> AssembledGraphResources {
        var observation = try observationBuilder(envelope.recordingDeviceURL, envelope.converterURL)
        observation.id = context.repositoryIDs.observation?.primitive
        observation.identifier = [
            envelope.sourceRecord.fhirIdentifier,
            envelope.primary.fhirIdentifier
        ] + nativeIdentifiers(for: sample, policy: context.nativeIdentifierDisclosurePolicy)
        try applySyncIdentity(of: sample, to: &observation, context: context)

        var provenance = try Self.provenance(
            sourceIdentifier: envelope.sourceRecord.fhirIdentifier,
            targetURL: envelope.primaryURL,
            converterURL: envelope.converterURL,
            sourceAuthorURL: envelope.sourceAuthorURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryIDs.provenance?.primitive
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
                Reference(reference: FHIRPrimitive(FHIRString(
                    stringLiteral: try ExchangeIdentity.fullURL(for: member.identity)
                )))
            }
        }
        provenance.target = [Reference(reference: primaryURL.asFHIRStringPrimitive())]
            + (try children.map { child in
                Reference(reference: FHIRPrimitive(FHIRString(
                    stringLiteral: try ExchangeIdentity.fullURL(for: child.identity)
                )))
            })
    }
}

#endif
