//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// One graph assembly transaction remains contiguous so identifiers, references, and repository ids
// can be reviewed as a single deterministic operation against the exchange contract.
// swiftlint:disable function_body_length file_length

import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// The shared event context plus SensorKit's own: the visit-location namespace, the governed
/// disclosure of the native record identifier, the physical recorder and the source time zone.
public struct SensorKitConversionContext: Sendable {
    public let event: ExchangeEventContext
    /// Deployment/source-store namespace for the exact native `SRVisit.locationId` value.
    ///
    /// This is intentionally distinct from every Grove opaque identity system: the location id is
    /// a governed lineage identifier on a logical Location, never a graph key.
    public let visitLocationIdentifierSystem: IdentifierSystem
    /// Optional governed disclosure of the exact `SensorKitSourceRecordID.value` on the designated
    /// primary output. Grove opaque identifiers remain the only graph/business keys.
    public let sourceIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy
    public let recordingDevice: RecordingDevice?
    public let sourceTimeZone: TimeZone

    var identityScope: OpaqueIdentityScope { event.identityScope }
    var eventIdentifier: ExchangeEventIdentifier { event.event }
    var repositoryScope: BusinessIdentifier { event.repositoryScope }
    var entryNodeIdentifierSystem: IdentifierSystem { event.entryNodeIdentifierSystem }
    var conversionInstant: Date { event.conversionInstant }
    var subjectIdentity: BusinessIdentifier { event.subject.identifier }
    var subject: Reference { get throws { try event.subjectReference() } }
    var researchStudies: [Reference] { get throws { try event.studyReferences() } }

    public init(
        event: ExchangeEventContext,
        visitLocationIdentifierSystem: IdentifierSystem,
        sourceIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy = .omit,
        recordingDevice: RecordingDevice? = nil,
        sourceTimeZone: TimeZone
    ) {
        self.event = event
        self.visitLocationIdentifierSystem = visitLocationIdentifierSystem
        self.sourceIdentifierDisclosurePolicy = sourceIdentifierDisclosurePolicy
        self.recordingDevice = recordingDevice
        self.sourceTimeZone = sourceTimeZone
    }

    func repositoryID(_ node: ExchangeGraphNode) -> RepositoryID? {
        event.repositoryIDs[node]
    }
}


/// One complete SensorKit structured, raw, or hybrid FHIR graph.
public struct SensorKitConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let sourceTypeToken: String
    /// The designated 1:1 primary representation of this source record.
    public let primaryOutputIdentifier: RoledIdentifier
    public let outputIdentifiers: [RoledIdentifier]
    /// Exact wire-visible identities of any recording payloads carried by the graph.
    public let artifactIdentifiers: [RoledIdentifier]
    public let converterApplicationSnapshot: RoledIdentifier
    public let converterHostSnapshot: RoledIdentifier
    public let observations: [Observation]
    public let recordingDocument: DocumentReference?
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let converterHost: Device
    public let provenance: Provenance
    /// The authoritative graph. Upload and persistence code must serialize this value.
    public let graph: ExchangeGraph

    public var bundle: ModelsR4.Bundle { graph.bundle }
}


public struct SensorKitRecordFailure: Error, Equatable, Sendable {
    public let sourceRecordID: SensorKitSourceRecordID
    public let reason: SensorKitConversionError
}


public struct SensorKitBatchResult: Sendable {
    public let conversions: [SensorKitConversion]
    public let failures: [SensorKitRecordFailure]
}


/// A no-fetch SensorKit adapter that emits only catalog-admitted R4 graph shapes.
public struct SensorKitConverter: Sendable {
    /// The closed adapter token every SensorKit identity preimage carries.
    static let adapterID = "sensorkit"

    public init() {}

    public func convert(
        _ record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws(SensorKitConversionError) -> SensorKitConversion {
        do {
            return try Self.convertRecord(record, context: context)
        } catch {
            throw SensorKitConversionError(conversionFailure: error)
        }
    }

    public func convert<S: Sequence>(
        _ records: S,
        contextForRecord: (SensorKitRecord) throws -> SensorKitConversionContext
    ) -> SensorKitBatchResult where S.Element == SensorKitRecord {
        var conversions: [SensorKitConversion] = []
        var failures: [SensorKitRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: contextForRecord(record)))
            } catch let reason as SensorKitConversionError {
                failures.append(.init(sourceRecordID: record.sourceRecordID, reason: reason))
            } catch {
                failures.append(.init(
                    sourceRecordID: record.sourceRecordID,
                    reason: SensorKitConversionError(conversionFailure: error)
                ))
            }
        }
        return SensorKitBatchResult(conversions: conversions, failures: failures)
    }
}


extension SensorKitRecord {
    /// Source coverage supplied for raw-only documents; structured records derive their own timing.
    var rawEffectivePeriod: DateInterval? {
        guard case .raw(let record) = self else {
            return nil
        }
        return record.effectivePeriod
    }
}


extension SensorKitRecord {
    var sourceRecordID: SensorKitSourceRecordID {
        switch self {
        case .rotationRate(let record): record.sourceRecordID
        case .electrocardiogram(let record): record.sourceRecordID
        case .onWrist(let record): record.sourceRecordID
        case .deviceUsage(let record): record.sourceRecordID
        case .visit(let record): record.sourceRecordID
        case .messagesUsage(let record): record.sourceRecordID
        case .phoneUsage(let record): record.sourceRecordID
        case .keyboardMetrics(let record): record.sourceRecordID
        case .sleepSession(let record): record.sourceRecordID
        case .accelerometer(let record): record.sourceRecordID
        case .wristTemperature(let record): record.sourceRecordID
        case .ppg(let record): record.sourceRecordID
        case .raw(let record): record.sourceRecordID
        }
    }

    var sourceToken: String {
        switch self {
        case .rotationRate: "SRSensor.rotationRate"
        case .electrocardiogram: "SRSensor.electrocardiogram"
        case .onWrist: "SRSensor.onWristState"
        case .deviceUsage: "SRSensor.deviceUsageReport"
        case .visit: "SRSensor.visits"
        case .messagesUsage: "SRSensor.messagesUsageReport"
        case .phoneUsage: "SRSensor.phoneUsageReport"
        case .keyboardMetrics: "SRSensor.keyboardMetrics"
        case .sleepSession: "SRSensor.sleepSessions"
        case .accelerometer: "SRSensor.accelerometer"
        case .wristTemperature: "SRSensor.wristTemperature"
        case .ppg: "SRSensor.photoplethysmogram"
        case .raw(let record): record.sourceToken
        }
    }

    var discriminators: (structured: String?, raw: String?) {
        switch self {
        case .rotationRate: ("sampled-data", nil)
        case .electrocardiogram: ("ecg-waveform", "native-recording")
        case .onWrist: ("on-wrist", nil)
        case .deviceUsage: ("device-usage-summary", "native-recording")
        case .visit: ("visit-summary", nil)
        case .messagesUsage(let record):
            ("messages-usage-summary", record.nativeRecording.map { _ in "native-recording" })
        case .phoneUsage(let record):
            ("phone-usage-summary", record.nativeRecording.map { _ in "native-recording" })
        case .keyboardMetrics: ("keyboard-metrics-summary", "native-recording")
        case .sleepSession: ("sleep-session", nil)
        case .accelerometer: ("accelerometer-recording-summary", "native-recording")
        case .wristTemperature: ("wrist-temperature-recording-summary", "native-recording")
        case .ppg: ("ppg-recording-summary", "native-recording")
        case .raw: (nil, "native-recording")
        }
    }

    var nativeRecording: SensorKitNativeRecording? {
        switch self {
        case .rotationRate, .onWrist, .visit, .sleepSession: nil
        case .electrocardiogram(let record): record.nativeRecording
        case .deviceUsage(let record): record.nativeRecording
        case .messagesUsage(let record): record.nativeRecording
        case .phoneUsage(let record): record.nativeRecording
        case .keyboardMetrics(let record): record.nativeRecording
        case .accelerometer(let record): record.nativeRecording
        case .wristTemperature(let record): record.nativeRecording
        case .ppg(let record): record.nativeRecording
        case .raw(let record): record.nativeRecording
        }
    }
}


extension SensorKitConverter {
    struct OutputNode {
        let identifier: RoledIdentifier
        let artifactIdentifier: RoledIdentifier?
        let fullURL: String
    }

    private static func convertRecord(
        _ record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws -> SensorKitConversion {
        try validate(record: record, context: context)
        let sourceIdentifier = try context.identityScope.sourceRecord(
            adapterID: Self.adapterID,
            sourceType: record.sourceToken,
            repositoryScope: context.repositoryScope,
            nativeRecordID: record.sourceRecordID.value
        )
        let descriptors = record.discriminators
        let structuredNode = try descriptors.structured.map {
            try outputNode(
                record: record,
                discriminator: $0,
                outputRole: "structured",
                includesArtifact: false,
                context: context
            )
        }
        let rawNode = try descriptors.raw.map { _ in
            try outputNode(
                record: record,
                discriminator: "single",
                outputRole: "native-recording",
                includesArtifact: true,
                context: context
            )
        }
        let converterApplicationIdentity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: context.event.application.bundleIdentifier
        )
        let converterHostIdentity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .host,
            sourceDeviceToken: "converter-host"
        )
        let converterURL = try converterApplicationIdentity.fullURLString
        let converterHostURL = try converterHostIdentity.fullURLString
        let studyContext = try context.event.studyContext()
        let gateway = try gatewayApplication(context: context)
        let recordingDeviceIdentity = try context.recordingDevice.map {
            try context.identityScope.recordingDevice(
                adapterID: Self.adapterID,
                subject: context.subjectIdentity,
                stableUnitToken: $0.stableUnitToken
            )
        }
        let recordingDeviceSnapshot = try context.recordingDevice.map {
            try context.identityScope.deviceSnapshot(
                event: context.eventIdentifier,
                role: .recordingDevice,
                sourceDeviceToken: $0.stableUnitToken
            )
        }
        let recordingDeviceURL = try recordingDeviceSnapshot.map {
            try $0.fullURLString
        }

        var observations = try buildObservations(
            record,
            sourceIdentifier: sourceIdentifier,
            outputNode: structuredNode,
            rawURL: rawNode?.fullURL,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        var document = try buildDocument(
            record,
            sourceIdentifier: sourceIdentifier,
            outputNode: rawNode,
            relatedURLs: structuredNode.map { [$0.fullURL] } ?? [],
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        try applyOutputIdentities(
            record: record,
            structuredNode: structuredNode,
            context: context,
            observations: &observations,
            document: &document
        )

        var converterApplication = SensorConverter.applicationDevice(context.event.application)
        converterApplication.id = context.repositoryID(.applicationDevice)?.primitive
        converterApplication.identifier = [converterApplicationIdentity.fhirIdentifier]
        converterApplication.parent = Reference(reference: converterHostURL.asFHIRStringPrimitive())
        var converterHost = SensorConverter.hostDevice(context.event.host)
        converterHost.id = context.repositoryID(.hostDevice)?.primitive
        converterHost.identifier = [converterHostIdentity.fhirIdentifier]
        var recordingDeviceResource = try recordingDeviceResource(
            context: context,
            identity: recordingDeviceIdentity,
            snapshot: recordingDeviceSnapshot
        )
        recordingDeviceResource?.id = context.repositoryID(.recordingDevice)?.primitive

        let outputNodes = [structuredNode, rawNode].compactMap { $0 }
        guard let primaryOutputIdentifier = structuredNode?.identifier ?? rawNode?.identifier else {
            throw SensorKitConversionError.invalidIdentity("record has no catalog-admitted output")
        }
        let provenanceNodeKey = try EntryNodeKey(
            system: context.entryNodeIdentifierSystem,
            event: context.eventIdentifier,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        var provenance = try conversionProvenance(
            sourceIdentifier: sourceIdentifier.fhirIdentifier,
            targetURLs: outputNodes.map(\.fullURL),
            converterURL: converterURL,
            recordedAt: context.conversionInstant,
            timeZone: context.sourceTimeZone
        )
        provenance.id = context.repositoryID(.provenance)?.primitive

        var entries: [BundleEntry] = []
        if let structuredNode, let observation = observations.first {
            entries.append(try BundleEntry(
                identifier: structuredNode.identifier,
                resource: ResourceProxy(with: observation)
            ))
        }
        if let rawNode, let document {
            entries.append(try BundleEntry(
                identifier: rawNode.identifier,
                resource: ResourceProxy(with: document)
            ))
        }
        entries.append(contentsOf: studyContext.allEntries)
        if let recordingDevice = recordingDeviceResource, let recordingDeviceSnapshot {
            entries.append(try BundleEntry(
                identifier: recordingDeviceSnapshot,
                resource: ResourceProxy(with: recordingDevice)
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
            identifier: provenanceNodeKey.identifier,
            resource: ResourceProxy(with: provenance)
        ))

        var bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.identifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try exactInstant(context.conversionInstant, timeZone: context.sourceTimeZone)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryID(.bundle)?.primitive
        let graph = try ExchangeGraph(
            kind: .active,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )
        return SensorKitConversion(
            sourceIdentifier: sourceIdentifier.fhirIdentifier,
            sourceTypeToken: record.sourceToken,
            primaryOutputIdentifier: primaryOutputIdentifier,
            outputIdentifiers: outputNodes.map(\.identifier),
            artifactIdentifiers: outputNodes.compactMap(\.artifactIdentifier),
            converterApplicationSnapshot: converterApplicationIdentity,
            converterHostSnapshot: converterHostIdentity,
            observations: observations,
            recordingDocument: document,
            recordingDevice: recordingDeviceResource,
            converterApplication: converterApplication,
            converterHost: converterHost,
            provenance: provenance,
            graph: graph
        )
    }

    private static func applyOutputIdentities(
        record: SensorKitRecord,
        structuredNode: OutputNode?,
        context: SensorKitConversionContext,
        observations: inout [Observation],
        document: inout DocumentReference?
    ) throws {
        if let id = context.repositoryID(.primaryOutput) {
            guard !observations.isEmpty else {
                throw SensorKitConversionError.repositoryIDWithoutStructuredOutput
            }
            observations[0].id = id.primitive
        }
        if let governedIdentifier = context.sourceIdentifierDisclosurePolicy.identifier(
            for: record.sourceRecordID.value
        ) {
            if structuredNode != nil {
                guard !observations.isEmpty else {
                    throw SensorKitConversionError.invalidIdentity(
                        "the designated structured primary output is missing"
                    )
                }
                observations[0].identifier?.append(governedIdentifier)
            } else {
                guard document != nil else {
                    throw SensorKitConversionError.invalidIdentity(
                        "the designated raw primary output is missing"
                    )
                }
                document?.identifier?.append(governedIdentifier)
            }
        }
        if let id = context.repositoryID(.sourceArtifact) {
            guard document != nil else {
                throw SensorKitConversionError.repositoryIDWithoutRawOutput
            }
            document?.id = id.primitive
        }
    }

    private static func recordingDeviceResource(
        context: SensorKitConversionContext,
        identity: RoledIdentifier?,
        snapshot: RoledIdentifier?
    ) throws -> Device? {
        guard let source = context.recordingDevice else {
            return nil
        }
        guard let identity, let snapshot else {
            throw SensorKitConversionError.invalidIdentity(
                "recording-device identity and event snapshot must be derived together"
            )
        }
        return SensorConverter.recordingDevice(source, identity: identity, snapshot: snapshot)
    }

    private static func outputNode(
        record: SensorKitRecord,
        discriminator: String,
        outputRole: String,
        includesArtifact: Bool,
        context: SensorKitConversionContext
    ) throws -> OutputNode {
        let identifier = try context.identityScope.sourceOutput(
            adapterID: Self.adapterID,
            sourceType: record.sourceToken,
            repositoryScope: context.repositoryScope,
            nativeRecordID: record.sourceRecordID.value,
            outputRole: outputRole,
            outputDiscriminator: discriminator
        )
        let artifactIdentifier = try record.nativeRecording.map { recording in
            try context.identityScope.sourceArtifact(
                adapterID: Self.adapterID,
                sourceType: record.sourceToken,
                repositoryScope: context.repositoryScope,
                nativeRecordID: record.sourceRecordID.value,
                formatCode: recording.format.rawValue,
                partIndex: 0
            )
        }
        return OutputNode(
            identifier: identifier,
            artifactIdentifier: includesArtifact ? artifactIdentifier : nil,
            fullURL: try identifier.fullURLString
        )
    }

    private static func validate(
        record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws {
        try validateIdentifierSystems(context)
        try validateRecordingDevice(context)
        try validateCatalogContract(record)
    }

    /// A distinct gateway application travels as a second application snapshot.
    static func gatewayApplication(context: SensorKitConversionContext) throws -> IdentifiedDevice? {
        guard case .gatewayApplication(let application) = context.event.converterRole else {
            return nil
        }
        let identity = try context.identityScope.deviceSnapshot(
            event: context.eventIdentifier,
            role: .application,
            sourceDeviceToken: application.bundleIdentifier
        )
        var resource = SensorConverter.applicationDevice(application)
        resource.identifier = [identity.fhirIdentifier]
        return IdentifiedDevice(resource: resource, identity: identity)
    }

    private static func validateIdentifierSystems(_ context: SensorKitConversionContext) throws {
        let systems = context.identityScope.systems
        let opaqueSystems = systems.opaque.all + [systems.event, systems.entryNode]
        guard !opaqueSystems.contains(context.visitLocationIdentifierSystem) else {
            throw SensorKitConversionError.invalidIdentity(
                "visitLocationIdentifierSystem must not reuse a Grove opaque-identity namespace"
            )
        }
        if case let .authorized(nativeSystem, _) = context.sourceIdentifierDisclosurePolicy,
           opaqueSystems.contains(nativeSystem) {
            throw SensorKitConversionError.invalidIdentity(
                "governed SensorKit source identifier system must not reuse a Grove opaque-identity namespace"
            )
        }
    }

    private static func validateRecordingDevice(_ context: SensorKitConversionContext) throws {
        if context.repositoryID(.recordingDevice) != nil, context.recordingDevice == nil {
            throw SensorKitConversionError.repositoryIDWithoutRecordingDevice
        }
    }

    private static func validateCatalogContract(_ record: SensorKitRecord) throws {
        guard let entry = SensorKitCatalog.current.entry(sourceToken: record.sourceToken) else {
            throw SensorKitRecordError.sourceTypeNotAdmitted(record.sourceToken)
        }
        if case .raw = record, entry.rawProfiles.isEmpty {
            throw SensorKitRecordError.sourceTypeHasNoRawContract(record.sourceToken)
        }
    }
}
