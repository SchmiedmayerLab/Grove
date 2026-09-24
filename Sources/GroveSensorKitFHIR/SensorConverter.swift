//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The graph assembly keeps one complete exchange transaction together.
// swiftlint:disable function_body_length

import CryptoKit
import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// The shared event context plus what the Sensor adapter needs of its own: the adapter token every
/// identity preimage carries, the physical recorder and the source's time zone, when known.
public struct SensorConversionContext: Sendable {
    public let event: ExchangeEventContext
    /// Closed adapter token included in every source identity.
    public let adapterID: String
    public let recordingDevice: RecordingDevice?
    /// The zone the source recorded in, whose offset every effective bound states; without one the bounds
    /// are serialized in UTC and the conversion warns.
    public let sourceTimeZone: TimeZone?

    var identityScope: OpaqueIdentityScope { event.identityScope }
    var eventIdentifier: ExchangeEventIdentifier { event.event }
    var repositoryScope: BusinessIdentifier { event.repositoryScope }
    var entryNodeIdentifierSystem: IdentifierSystem { event.entryNodeIdentifierSystem }
    var conversionInstant: Date { event.conversionInstant }
    var subjectIdentifier: BusinessIdentifier { event.subject.identifier }
    var subject: Reference { get throws { try event.subjectReference() } }
    var researchStudies: [Reference] { get throws { try event.studyReferences() } }

    public init(
        event: ExchangeEventContext,
        adapterID: String,
        recordingDevice: RecordingDevice? = nil,
        sourceTimeZone: TimeZone? = nil
    ) {
        self.event = event
        self.adapterID = adapterID
        self.recordingDevice = recordingDevice
        self.sourceTimeZone = sourceTimeZone
    }

    func repositoryID(_ node: ExchangeGraphNode) -> RepositoryID? {
        event.repositoryIDs[node]
    }
}


/// Complete business identities of one emitted Sensor exchange graph.
public struct SensorGraphIdentifiers: Hashable, Sendable {
    public let event: RoledIdentifier
    public let sourceRecord: RoledIdentifier
    public let sourceOutput: RoledIdentifier
    public let sourceArtifact: RoledIdentifier?
    public let recordingDevice: RoledIdentifier?
    public let recordingDeviceSnapshot: RoledIdentifier?
    public let converterApplicationSnapshot: RoledIdentifier
    public let converterHostSnapshot: RoledIdentifier
    public let provenance: RoledIdentifier
}


/// The typed primary FHIR resource emitted for a Sensor record.
public enum SensorPrimaryResource: Sendable {
    case observation(Observation)
    case recordingDocument(DocumentReference)
}


/// Something an accepted Sensor record carried that its graph does not; each case is one registered
/// `mobile-omission` rule.
public enum SensorConversionWarning: Hashable, Sendable {
    /// The context stated no time zone, so the effective element `field`, such as
    /// `Observation.effectivePeriod.start`, is serialized in UTC.
    case sourceOffsetUnavailable(field: String)

    /// The registered diagnostic, located at the element that lost its offset.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .sourceOffsetUnavailable(let field):
            ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at: field)
        }
    }
}


/// One complete Sensor conversion graph and collection Bundle.
public struct SensorConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let sourceTypeIdentifier: String
    public let graphIdentifiers: SensorGraphIdentifiers
    public let primaryResource: SensorPrimaryResource
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let converterHost: Device
    public let provenance: Provenance
    /// The authoritative graph. Upload and persistence code must serialize this value.
    public let graph: ExchangeGraph
    /// Empty when the graph carries everything the record supplied.
    public let warnings: [SensorConversionWarning]

    public var bundle: ModelsR4.Bundle { graph.bundle }
}


/// Explicit successes and failures from a batch conversion.
public struct SensorBatchResult: Sendable {
    public let conversions: [SensorConversion]
    public let failures: [SensorRecordFailure]
}


/// Builds source-neutral R4 graphs for sampled data, ECG, and native recordings.
public struct SensorConverter: Sendable {
    public init() {}

    public func convert(
        _ record: SensorRecord,
        context: SensorConversionContext
    ) throws(SensorConversionError) -> SensorConversion {
        do {
            return try Self.convertRecord(record, context: context)
        } catch {
            throw SensorConversionError(conversionFailure: error)
        }
    }

    /// Converts every input and returns a typed failure for every record that was not emitted.
    public func convert<S: Sequence>(
        _ records: S,
        contextForRecord: (SensorRecord) throws -> SensorConversionContext
    ) -> SensorBatchResult where S.Element == SensorRecord {
        var conversions: [SensorConversion] = []
        var failures: [SensorRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: contextForRecord(record)))
            } catch let error as SensorConversionError {
                failures.append(SensorRecordFailure(
                    nativeRecordID: record.nativeRecordID,
                    sourceTypeIdentifier: record.sourceTypeIdentifier,
                    reason: error
                ))
            } catch {
                failures.append(SensorRecordFailure(
                    nativeRecordID: record.nativeRecordID,
                    sourceTypeIdentifier: record.sourceTypeIdentifier,
                    reason: SensorConversionError(conversionFailure: error)
                ))
            }
        }
        return SensorBatchResult(conversions: conversions, failures: failures)
    }
}


extension SensorConverter {
    private static func convertRecord(
        _ record: SensorRecord,
        context: SensorConversionContext
    ) throws -> SensorConversion {
        try validate(context: context)
        let sourceRecord = try context.identityScope.sourceRecord(
            adapterID: context.adapterID,
            sourceType: record.sourceTypeIdentifier,
            repositoryScope: context.repositoryScope,
            nativeRecordID: record.nativeRecordID
        )
        let outputDescriptor: (role: String, discriminator: String) = switch record {
        case .sampledData, .electrocardiogram:
            ("structured", "single")
        case .recordingDocument:
            ("native-recording", "single")
        }
        let sourceOutput = try sourceRecord.output(role: outputDescriptor.role, discriminator: outputDescriptor.discriminator)
        let sourceArtifact = try record.recordingFormat.map { format in
            try sourceRecord.artifact(formatCode: format.rawValue, partIndex: 0)
        }
        let converterApplicationIdentity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: context.event.application.sourceDeviceToken
        )
        let converterHostIdentity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .host,
            sourceDeviceToken: context.event.host.sourceDeviceToken
        )
        let provenanceNode = try EntryNodeKey(
            system: context.entryNodeIdentifierSystem,
            event: context.eventIdentifier,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        let recordingDeviceIdentity = try context.recordingDevice.map { device in
            try context.identityScope.recordingDevice(
                adapterID: context.adapterID,
                subject: context.subjectIdentifier,
                stableUnitToken: device.stableUnitToken
            )
        }
        let recordingDeviceSnapshot = try context.recordingDevice.map { device in
            try context.identityScope.deviceSnapshot(
                event: context.eventIdentifier,
                role: .recordingDevice,
                sourceDeviceToken: device.stableUnitToken
            )
        }

        let recordURL = try sourceOutput.fullURLString
        let converterURL = try converterApplicationIdentity.fullURLString
        let converterHostURL = try converterHostIdentity.fullURLString
        let recordingDeviceURL = try recordingDeviceSnapshot.map { try $0.fullURLString }
        let studyContext = try context.event.studyContext()
        let gateway = try gatewayApplication(context: context)

        var converterApplication = applicationDevice(context.event.application)
        converterApplication.id = context.repositoryID(.applicationDevice)?.primitive
        converterApplication.identifier = [converterApplicationIdentity.fhirIdentifier]
        converterApplication.parent = Reference(reference: converterHostURL.asFHIRStringPrimitive())
        var converterHost = hostDevice(context.event.host)
        converterHost.id = context.repositoryID(.hostDevice)?.primitive
        converterHost.identifier = [converterHostIdentity.fhirIdentifier]
        var recordingDeviceResource: Device?
        if let source = context.recordingDevice,
           let identity = recordingDeviceIdentity,
           let snapshot = recordingDeviceSnapshot {
            recordingDeviceResource = recordingDevice(source, identity: identity, snapshot: snapshot)
        }
        recordingDeviceResource?.id = context.repositoryID(.recordingDevice)?.primitive

        let primaryResource = try primaryResource(
            record,
            sourceRecord: sourceRecord.identifier,
            sourceOutput: sourceOutput,
            sourceArtifact: sourceArtifact,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        // The repository id is applied once; the proxy and the retained value are the same resource.
        let retainedPrimary: SensorPrimaryResource
        let primaryProxy: ResourceProxy
        switch primaryResource {
        case .observation(var observation):
            observation.id = context.repositoryID(.primaryOutput)?.primitive
            retainedPrimary = .observation(observation)
            primaryProxy = ResourceProxy(with: observation)
        case .recordingDocument(var document):
            document.id = context.repositoryID(.primaryOutput)?.primitive
            retainedPrimary = .recordingDocument(document)
            primaryProxy = ResourceProxy(with: document)
        }

        var provenance = try provenance(
            sourceIdentifier: sourceRecord.identifier.fhirIdentifier,
            targetURL: recordURL,
            converterURL: converterURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryID(.provenance)?.primitive

        var entries = [
            try BundleEntry(identifier: sourceOutput, resource: primaryProxy)
        ]
        entries.append(contentsOf: studyContext.allEntries)
        if let recordingDeviceResource, let recordingDeviceSnapshot {
            entries.append(try BundleEntry(
                identifier: recordingDeviceSnapshot,
                resource: ResourceProxy(with: recordingDeviceResource)
            ))
        }
        entries.append(try BundleEntry(
            identifier: converterHostIdentity,
            resource: ResourceProxy(with: converterHost)
        ))
        entries.append(try BundleEntry(
            identifier: converterApplicationIdentity,
            resource: ResourceProxy(with: converterApplication)
        ))
        if let gateway {
            entries.append(try BundleEntry(identifier: gateway.identity, resource: ResourceProxy(with: gateway.resource)))
        }
        entries.append(try BundleEntry(
            identifier: provenanceNode.identifier,
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
        let graph = try ExchangeGraph(
            kind: .active,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )

        return SensorConversion(
            sourceIdentifier: sourceRecord.identifier.fhirIdentifier,
            sourceTypeIdentifier: record.sourceTypeIdentifier,
            graphIdentifiers: SensorGraphIdentifiers(
                event: context.eventIdentifier.identifier,
                sourceRecord: sourceRecord.identifier,
                sourceOutput: sourceOutput,
                sourceArtifact: sourceArtifact,
                recordingDevice: recordingDeviceIdentity,
                recordingDeviceSnapshot: recordingDeviceSnapshot,
                converterApplicationSnapshot: converterApplicationIdentity,
                converterHostSnapshot: converterHostIdentity,
                provenance: provenanceNode.identifier
            ),
            primaryResource: retainedPrimary,
            recordingDevice: recordingDeviceResource,
            converterApplication: converterApplication,
            converterHost: converterHost,
            provenance: provenance,
            graph: graph,
            warnings: sourceOffsetWarnings(for: retainedPrimary, context: context)
        )
    }

    /// The effective bounds an Observation serialized in UTC because the context named no time zone.
    private static func sourceOffsetWarnings(
        for primary: SensorPrimaryResource,
        context: SensorConversionContext
    ) -> [SensorConversionWarning] {
        guard case .observation = primary, context.sourceTimeZone == nil else {
            return []
        }
        return ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"].map { .sourceOffsetUnavailable(field: $0) }
    }

    /// A distinct gateway application travels as a second application snapshot; the converter
    /// itself as gateway needs no further entry.
    static func gatewayApplication(context: SensorConversionContext) throws -> IdentifiedDevice? {
        guard case .gatewayApplication(let application) = context.event.converterRole else {
            return nil
        }
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: application.sourceDeviceToken
        )
        var resource = applicationDevice(application)
        resource.identifier = [identity.fhirIdentifier]
        return IdentifiedDevice(resource: resource, identity: identity)
    }

    private static func validate(context: SensorConversionContext) throws {
        guard !context.adapterID.isEmpty else {
            throw SensorConversionError.invalidExchangeIdentity("adapterID is empty")
        }
        if context.repositoryID(.recordingDevice) != nil, context.recordingDevice == nil {
            throw SensorConversionError.repositoryIDWithoutRecordingDevice
        }
    }
}


extension SensorRecord {
    fileprivate var recordingFormat: RegisteredRecordingFormat? {
        guard case .recordingDocument(let document) = self else {
            return nil
        }
        return document.format
    }
}
