//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// One graph assembly transaction remains contiguous so identifiers, references, and repository ids
// can be reviewed as a single deterministic operation against the exchange contract.
// swiftlint:disable function_body_length multiline_literal_brackets file_length

import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Optional repository-assigned logical ids for one SensorKit conversion graph.
public struct SensorKitRepositoryIDs: Hashable, Sendable {
    public let bundle: RepositoryID?
    public let structuredOutput: RepositoryID?
    public let rawOutput: RepositoryID?
    public let recordingDevice: RepositoryID?
    public let converterApplication: RepositoryID?
    public let converterHost: RepositoryID?
    public let provenance: RepositoryID?

    public init(
        bundle: RepositoryID? = nil,
        structuredOutput: RepositoryID? = nil,
        rawOutput: RepositoryID? = nil,
        recordingDevice: RepositoryID? = nil,
        converterApplication: RepositoryID? = nil,
        converterHost: RepositoryID? = nil,
        provenance: RepositoryID? = nil
    ) {
        self.bundle = bundle
        self.structuredOutput = structuredOutput
        self.rawOutput = rawOutput
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.converterHost = converterHost
        self.provenance = provenance
    }
}


/// Explicit deployment, formatting, and audit inputs for one deterministic graph.
public struct SensorKitConversionContext: Sendable {
    public let subject: Reference
    /// Stable deployment identity of `subject`, used only as an HMAC component.
    public let subjectIdentity: BusinessIdentifier
    public let converter: SensorApplication
    public let converterHost: SensorHostDevice
    public let eventIdentifier: ExchangeEventIdentifier
    public let entryNodeIdentifierSystem: IdentifierSystem
    public let identityScope: PseudonymousIdentityScope
    public let repositoryScope: BusinessIdentifier
    /// Deployment/source-store namespace for the exact native `SRVisit.locationId` value.
    ///
    /// This is intentionally distinct from every Grove opaque identity system: the location id is
    /// a governed lineage identifier on a logical Location, never a graph key.
    public let visitLocationIdentifierSystem: IdentifierSystem
    /// Optional governed disclosure of the exact `SensorKitSourceRecordID.value` on the designated
    /// primary output. Grove opaque identifiers remain the only graph/business keys.
    public let sourceIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy
    public let recordingDevice: SensorRecordingDevice?
    public let converterWasGateway: Bool
    public let sourceTimeZone: TimeZone
    public let recordedAt: Date
    public let researchStudies: [Reference]
    public let repositoryIDs: SensorKitRepositoryIDs

    public init(
        subject: Reference,
        subjectIdentity: BusinessIdentifier,
        converter: SensorApplication,
        converterHost: SensorHostDevice,
        eventIdentifier: ExchangeEventIdentifier,
        entryNodeIdentifierSystem: IdentifierSystem,
        identityScope: PseudonymousIdentityScope,
        repositoryScope: BusinessIdentifier,
        visitLocationIdentifierSystem: IdentifierSystem,
        sourceIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy = .omit,
        recordingDevice: SensorRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        sourceTimeZone: TimeZone,
        recordedAt: Date,
        researchStudies: [Reference] = [],
        repositoryIDs: SensorKitRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.subjectIdentity = subjectIdentity
        self.converter = converter
        self.converterHost = converterHost
        self.eventIdentifier = eventIdentifier
        self.entryNodeIdentifierSystem = entryNodeIdentifierSystem
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.visitLocationIdentifierSystem = visitLocationIdentifierSystem
        self.sourceIdentifierDisclosurePolicy = sourceIdentifierDisclosurePolicy
        self.recordingDevice = recordingDevice
        self.converterWasGateway = converterWasGateway
        self.sourceTimeZone = sourceTimeZone
        self.recordedAt = recordedAt
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// One complete SensorKit structured, raw, or hybrid FHIR graph.
public struct SensorKitConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let sourceTypeToken: String
    /// The designated 1:1 primary representation of this source record.
    public let primaryOutputIdentifier: BusinessIdentifier
    public let outputIdentifiers: [BusinessIdentifier]
    /// Exact wire-visible identities of any recording payloads carried by the graph.
    public let artifactIdentifiers: [BusinessIdentifier]
    public let converterApplicationSnapshot: BusinessIdentifier
    public let converterHostSnapshot: BusinessIdentifier
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
    public init() {}

    public func convert(
        _ record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws -> SensorKitConversion {
        do {
            return try Self.convertRecord(record, context: context)
        } catch let error as SensorKitConversionError {
            throw error
        } catch let error as SensorKitRecordError {
            throw SensorKitConversionError.invalidRecord(error)
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
        let identifier: BusinessIdentifier
        let artifactIdentifier: BusinessIdentifier?
        let fullURL: String
    }

    private static func convertRecord(
        _ record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws -> SensorKitConversion {
        try validate(record: record, context: context)
        let sourceIdentifier = try context.identityScope.sourceRecord(
            adapterID: "sensorkit",
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
            eventIdentifier: context.eventIdentifier,
            deviceRole: .application,
            sourceDeviceToken: context.converter.sourceDeviceToken
        )
        let converterHostIdentity = try context.identityScope.deviceSnapshot(
            eventIdentifier: context.eventIdentifier,
            deviceRole: .host,
            sourceDeviceToken: context.converterHost.sourceDeviceToken
        )
        let converterURL = try ExchangeIdentity.fullURL(for: converterApplicationIdentity)
        let converterHostURL = try ExchangeIdentity.fullURL(for: converterHostIdentity)
        let recordingDeviceIdentity = try context.recordingDevice.map {
            try context.identityScope.recordingDevice(
                adapterID: "sensorkit",
                subject: context.subjectIdentity,
                stableUnitToken: $0.stableUnitToken
            )
        }
        let recordingDeviceSnapshot = try context.recordingDevice.map {
            try context.identityScope.deviceSnapshot(
                eventIdentifier: context.eventIdentifier,
                deviceRole: .recordingDevice,
                sourceDeviceToken: $0.stableUnitToken
            )
        }
        let recordingDeviceURL = try recordingDeviceSnapshot.map {
            try ExchangeIdentity.fullURL(for: $0)
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

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        converterApplication.identifier = [converterApplicationIdentity.fhirIdentifier]
        converterApplication.parent = Reference(reference: converterHostURL.asFHIRStringPrimitive())
        var converterHost = hostDevice(context.converterHost)
        converterHost.id = context.repositoryIDs.converterHost?.primitive
        converterHost.identifier = [converterHostIdentity.fhirIdentifier]
        var recordingDeviceResource = try recordingDeviceResource(
            context: context,
            identity: recordingDeviceIdentity,
            snapshot: recordingDeviceSnapshot
        )
        recordingDeviceResource?.id = context.repositoryIDs.recordingDevice?.primitive

        let outputNodes = [structuredNode, rawNode].compactMap { $0 }
        guard let primaryOutputIdentifier = structuredNode?.identifier ?? rawNode?.identifier else {
            throw SensorKitConversionError.invalidIdentity("record has no catalog-admitted output")
        }
        let provenanceNodeKey = try ExchangeNodeKey(
            system: context.entryNodeIdentifierSystem,
            eventIdentifier: context.eventIdentifier,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        var provenance = try conversionProvenance(
            sourceIdentifier: sourceIdentifier.fhirIdentifier,
            targetURLs: outputNodes.map(\.fullURL),
            converterURL: converterURL,
            recordedAt: context.recordedAt,
            timeZone: context.sourceTimeZone
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        var entries: [BundleEntry] = []
        if let structuredNode, let observation = observations.first {
            entries.append(try ExchangeIdentity.entry(
                identifier: structuredNode.identifier,
                resource: ResourceProxy(with: observation)
            ))
        }
        if let rawNode, let document {
            entries.append(try ExchangeIdentity.entry(
                identifier: rawNode.identifier,
                resource: ResourceProxy(with: document)
            ))
        }
        if let recordingDevice = recordingDeviceResource, let recordingDeviceSnapshot {
            entries.append(try ExchangeIdentity.entry(
                identifier: recordingDeviceSnapshot,
                resource: ResourceProxy(with: recordingDevice)
            ))
        }
        entries.append(try ExchangeIdentity.entry(
            identifier: converterHostIdentity,
            resource: ResourceProxy(with: converterHost)
        ))
        entries.append(try ExchangeIdentity.entry(
            identifier: converterApplicationIdentity,
            resource: ResourceProxy(with: converterApplication)
        ))
        entries.append(try ExchangeIdentity.entry(
            nodeKey: provenanceNodeKey,
            resource: ResourceProxy(with: provenance)
        ))
        try ExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.businessIdentifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try exactInstant(context.recordedAt, timeZone: context.sourceTimeZone)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive
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
        if let id = context.repositoryIDs.structuredOutput {
            guard !observations.isEmpty else {
                throw SensorKitConversionError.repositoryIDWithoutStructuredOutput
            }
            observations[0].id = id.primitive
        }
        if let governedIdentifier = governedSourceIdentifier(
            value: record.sourceRecordID.value,
            policy: context.sourceIdentifierDisclosurePolicy
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
        if let id = context.repositoryIDs.rawOutput {
            guard document != nil else {
                throw SensorKitConversionError.repositoryIDWithoutRawOutput
            }
            document?.id = id.primitive
        }
    }

    private static func recordingDeviceResource(
        context: SensorKitConversionContext,
        identity: BusinessIdentifier?,
        snapshot: BusinessIdentifier?
    ) throws -> Device? {
        guard let source = context.recordingDevice else {
            return nil
        }
        guard let identity, let snapshot else {
            throw SensorKitConversionError.invalidIdentity(
                "recording-device identity and event snapshot must be derived together"
            )
        }
        return recordingDevice(source, identifier: identity, snapshot: snapshot)
    }

    private static func outputNode(
        record: SensorKitRecord,
        discriminator: String,
        outputRole: String,
        includesArtifact: Bool,
        context: SensorKitConversionContext
    ) throws -> OutputNode {
        let identifier = try context.identityScope.sourceOutput(
            adapterID: "sensorkit",
            sourceType: record.sourceToken,
            repositoryScope: context.repositoryScope,
            nativeRecordID: record.sourceRecordID.value,
            outputRole: outputRole,
            outputDiscriminator: discriminator
        )
        let artifactIdentifier = try record.nativeRecording.map { recording in
            try context.identityScope.sourceArtifact(
                adapterID: "sensorkit",
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
            fullURL: try ExchangeIdentity.fullURL(for: identifier)
        )
    }

    private static func governedSourceIdentifier(
        value: String,
        policy: GovernedSourceIdentifierDisclosurePolicy
    ) -> Identifier? {
        guard case let .authorized(system, type) = policy else {
            return nil
        }
        return Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: system.rawValue)),
            type: type.map { type in
                CodeableConcept(coding: [Coding(
                    code: type.code.asFHIRStringPrimitive(),
                    display: type.display?.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: type.system.rawValue))
                )])
            },
            value: value.asFHIRStringPrimitive()
        )
    }


    /// One typed mapping, so a new reference failure cannot be flattened into a description string.
    private static func validatedReference(
        _ reference: Reference,
        field: String,
        expectedResourceType: ResourceType
    ) throws(SensorKitConversionError) -> TypedReferenceIdentity {
        do {
            return try TypedReference.validate(
                reference,
                expectedResourceType: expectedResourceType
            )
        } catch {
            switch error {
            case .literalRequiresBundleEntry:
                throw .invalidIdentity(
                    "\(field) must use an identifier-only logical Reference; literals require a Bundle entry"
                )
            case .invalidReference:
                throw .invalidReference("\(field) must reference a \(expectedResourceType)")
            }
        }
    }

    private static func validate(
        record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws {
        try validateConverter(context)
        try validateIdentifierSystems(context)
        _ = try validatedReference(context.subject, field: "subject", expectedResourceType: .patient)
        try validateResearchStudies(context.researchStudies)
        try validateRecordingDevice(context)
        try validateCatalogContract(record)
    }

    private static func validateConverter(_ context: SensorKitConversionContext) throws {
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorKitConversionError.invalidConverterApplication("name")
        }
        guard !context.converter.sourceDeviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorKitConversionError.invalidConverterApplication("sourceDeviceToken")
        }
        guard !context.converterHost.sourceDeviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorKitConversionError.invalidConverterApplication("converterHost.sourceDeviceToken")
        }
        guard !context.converterHost.operatingSystemVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorKitConversionError.invalidConverterApplication("converterHost.operatingSystemVersion")
        }
        if context.converter.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw SensorKitConversionError.invalidConverterApplication("version")
        }
    }

    private static func validateIdentifierSystems(_ context: SensorKitConversionContext) throws {
        let opaqueSystems = [
            context.identityScope.systems.sourceRecord,
            context.identityScope.systems.sourceOutput,
            context.identityScope.systems.writerRecord,
            context.identityScope.systems.providerRecord,
            context.identityScope.systems.providerOutput,
            context.identityScope.systems.sourceArtifact,
            context.identityScope.systems.providerArtifact,
            context.identityScope.systems.sourceContext,
            context.identityScope.systems.recordingDevice,
            context.identityScope.systems.deviceSnapshot,
            context.eventIdentifier.businessIdentifier.system,
            context.entryNodeIdentifierSystem
        ]
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

    private static func validateResearchStudies(_ researchStudies: [Reference]) throws {
        var identities: Set<TypedReferenceIdentity> = []
        for study in researchStudies {
            let identity = try validatedReference(
                study,
                field: "researchStudies",
                expectedResourceType: .researchStudy
            )
            guard identities.insert(identity).inserted else {
                throw SensorKitConversionError.duplicateResearchStudyReference
            }
        }
    }

    private static func validateRecordingDevice(_ context: SensorKitConversionContext) throws {
        if context.repositoryIDs.recordingDevice != nil, context.recordingDevice == nil {
            throw SensorKitConversionError.repositoryIDWithoutRecordingDevice
        }
    }

    private static func validateCatalogContract(_ record: SensorKitRecord) throws {
        guard let entry = SensorKitCatalog.current.entries.first(where: {
            $0.sourceToken == record.sourceToken
        }) else {
            throw SensorKitRecordError.sourceTypeNotAdmitted(record.sourceToken)
        }
        if case .raw = record, entry.rawProfiles.isEmpty {
            throw SensorKitRecordError.sourceTypeHasNoRawContract(record.sourceToken)
        }
    }

    private static func applicationDevice(_ application: SensorApplication) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveApplicationDevice])
        device.status = FHIRPrimitive(.active)
        device.deviceName = [DeviceDeviceName(
            name: application.name.asFHIRStringPrimitive(),
            type: FHIRPrimitive(.userFriendlyName)
        )]
        if let version = application.version {
            device.version = [DeviceVersion(
                type: CodeableConcept(coding: [Coding(
                    code: "531975".asFHIRStringPrimitive(),
                    display: "MDC_ID_PROD_SPEC_SW".asFHIRStringPrimitive(),
                    system: "urn:iso:std:iso:11073:10101".asFHIRURIPrimitive()
                )]),
                value: version.asFHIRStringPrimitive()
            )]
        }
        if let build = application.build {
            device.version = (device.version ?? []) + [DeviceVersion(
                type: CodeableConcept(coding: [Coding(
                    code: "build".asFHIRStringPrimitive(),
                    display: "Build".asFHIRStringPrimitive(),
                    system: Canonicals.groveApplicationVersionType
                )]),
                value: build.asFHIRStringPrimitive()
            )]
        }
        return device
    }

    private static func hostDevice(_ host: SensorHostDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveHostDevice])
        device.status = FHIRPrimitive(.active)
        device.manufacturer = host.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = host.modelNumber?.asFHIRStringPrimitive()
        if let name = host.name {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.version = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: "os-version".asFHIRStringPrimitive(),
                display: "Operating system version".asFHIRStringPrimitive(),
                system: Canonicals.groveApplicationVersionType
            )]),
            value: host.operatingSystemVersion.asFHIRStringPrimitive()
        )]
        return device
    }

    private static func recordingDevice(
        _ source: SensorRecordingDevice,
        identifier: BusinessIdentifier,
        snapshot: BusinessIdentifier
    ) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveRecordingDevice])
        device.status = FHIRPrimitive(.active)
        device.identifier = [snapshot.fhirIdentifier, identifier.fhirIdentifier]
        if let name = source.name {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = source.manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = source.modelNumber?.asFHIRStringPrimitive()
        return device
    }
}
