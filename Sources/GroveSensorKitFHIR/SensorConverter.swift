//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The graph assembly keeps one complete exchange transaction together.
// swiftlint:disable function_body_length file_length large_tuple

import CryptoKit
import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Product identity of the application performing a Sensor-to-FHIR conversion.
public struct SensorApplication: Hashable, Sendable {
    /// Source-local application token used only inside the event-scoped HMAC preimage.
    public let sourceDeviceToken: String
    public let name: String
    public let version: String?
    public let build: String?

    public init(
        sourceDeviceToken: String,
        name: String,
        version: String? = nil,
        build: String? = nil
    ) {
        self.sourceDeviceToken = sourceDeviceToken
        self.name = name
        self.version = version
        self.build = build
    }
}


/// Event-time host facts kept separate from the converting application release.
public struct SensorHostDevice: Hashable, Sendable {
    public let sourceDeviceToken: String
    public let operatingSystemVersion: String
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    public init(
        sourceDeviceToken: String,
        operatingSystemVersion: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) {
        self.sourceDeviceToken = sourceDeviceToken
        self.operatingSystemVersion = operatingSystemVersion
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
    }
}


/// Identity and descriptive fields of the physical recording device, when known.
public struct SensorRecordingDevice: Hashable, Sendable {
    /// A source-local token that remains stable for the same physical unit.
    ///
    /// The token is never emitted. Adapter converters feed it to the deployment-scoped
    /// `recording-device` HMAC instead of disclosing a platform identifier.
    public let stableUnitToken: String
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    public init(
        stableUnitToken: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) {
        self.stableUnitToken = stableUnitToken
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
    }
}


/// Optional repository-assigned logical ids for one Sensor exchange graph.
public struct SensorRepositoryIDs: Hashable, Sendable {
    public let bundle: RepositoryID?
    public let record: RepositoryID?
    public let recordingDevice: RepositoryID?
    public let converterApplication: RepositoryID?
    public let converterHost: RepositoryID?
    public let provenance: RepositoryID?

    public init(
        bundle: RepositoryID? = nil,
        record: RepositoryID? = nil,
        recordingDevice: RepositoryID? = nil,
        converterApplication: RepositoryID? = nil,
        converterHost: RepositoryID? = nil,
        provenance: RepositoryID? = nil
    ) {
        self.bundle = bundle
        self.record = record
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.converterHost = converterHost
        self.provenance = provenance
    }
}


/// Explicit deployment and audit inputs used to build one reproducible graph.
public struct SensorConversionContext: Sendable {
    public let subject: Reference
    /// Stable deployment identity of `subject`, used only as an HMAC component.
    public let subjectIdentity: BusinessIdentifier
    public let converter: SensorApplication
    public let converterHost: SensorHostDevice
    /// Closed adapter token included in every source identity.
    public let adapterID: String
    public let eventIdentifier: ExchangeEventIdentifier
    public let entryNodeIdentifierSystem: IdentifierSystem
    public let identityScope: PseudonymousIdentityScope
    public let repositoryScope: BusinessIdentifier
    public let recordingDevice: SensorRecordingDevice?
    public let converterWasGateway: Bool
    public let recordedAt: Date
    public let researchStudies: [Reference]
    public let repositoryIDs: SensorRepositoryIDs

    public init(
        subject: Reference,
        subjectIdentity: BusinessIdentifier,
        converter: SensorApplication,
        converterHost: SensorHostDevice,
        adapterID: String,
        eventIdentifier: ExchangeEventIdentifier,
        entryNodeIdentifierSystem: IdentifierSystem,
        identityScope: PseudonymousIdentityScope,
        repositoryScope: BusinessIdentifier,
        recordingDevice: SensorRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        recordedAt: Date,
        researchStudies: [Reference] = [],
        repositoryIDs: SensorRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.subjectIdentity = subjectIdentity
        self.converter = converter
        self.converterHost = converterHost
        self.adapterID = adapterID
        self.eventIdentifier = eventIdentifier
        self.entryNodeIdentifierSystem = entryNodeIdentifierSystem
        self.identityScope = identityScope
        self.repositoryScope = repositoryScope
        self.recordingDevice = recordingDevice
        self.converterWasGateway = converterWasGateway
        self.recordedAt = recordedAt
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// Complete business identities of one emitted Sensor exchange graph.
public struct SensorGraphIdentifiers: Hashable, Sendable {
    public let event: BusinessIdentifier
    public let sourceRecord: BusinessIdentifier
    public let sourceOutput: BusinessIdentifier
    public let sourceArtifact: BusinessIdentifier?
    public let recordingDevice: BusinessIdentifier?
    public let recordingDeviceSnapshot: BusinessIdentifier?
    public let converterApplicationSnapshot: BusinessIdentifier
    public let converterHostSnapshot: BusinessIdentifier
    public let provenance: BusinessIdentifier
}


/// The typed primary FHIR resource emitted for a Sensor record.
public enum SensorPrimaryResource: Sendable {
    case observation(Observation)
    case recordingDocument(DocumentReference)
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
    static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"
    static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"

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
        let sourceOutput = try context.identityScope.sourceOutput(
            adapterID: context.adapterID,
            sourceType: record.sourceTypeIdentifier,
            repositoryScope: context.repositoryScope,
            nativeRecordID: record.nativeRecordID,
            outputRole: outputDescriptor.role,
            outputDiscriminator: outputDescriptor.discriminator
        )
        let sourceArtifact = try (record.recordingFormat).map { format in
            try context.identityScope.sourceArtifact(
                adapterID: context.adapterID,
                sourceType: record.sourceTypeIdentifier,
                repositoryScope: context.repositoryScope,
                nativeRecordID: record.nativeRecordID,
                formatCode: format.rawValue,
                partIndex: 0
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
        let provenanceNode = try ExchangeNodeKey(
            system: context.entryNodeIdentifierSystem,
            eventIdentifier: context.eventIdentifier,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        let recordingDeviceIdentity = try context.recordingDevice.map { device in
            try context.identityScope.recordingDevice(
                adapterID: context.adapterID,
                subject: context.subjectIdentity,
                stableUnitToken: device.stableUnitToken
            )
        }
        let recordingDeviceSnapshot = try context.recordingDevice.map { device in
            try context.identityScope.deviceSnapshot(
                eventIdentifier: context.eventIdentifier,
                deviceRole: .recordingDevice,
                sourceDeviceToken: device.stableUnitToken
            )
        }

        let recordURL = try ExchangeIdentity.fullURL(for: sourceOutput)
        let converterURL = try ExchangeIdentity.fullURL(for: converterApplicationIdentity)
        let converterHostURL = try ExchangeIdentity.fullURL(for: converterHostIdentity)
        let recordingDeviceURL = try recordingDeviceSnapshot.map(ExchangeIdentity.fullURL(for:))

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        converterApplication.identifier = [converterApplicationIdentity.fhirIdentifier]
        converterApplication.parent = Reference(reference: converterHostURL.asFHIRStringPrimitive())
        var converterHost = hostDevice(context.converterHost)
        converterHost.id = context.repositoryIDs.converterHost?.primitive
        converterHost.identifier = [converterHostIdentity.fhirIdentifier]
        var recordingDevice = zip(
            context.recordingDevice,
            recordingDeviceIdentity,
            recordingDeviceSnapshot
        ).map { source, identity, snapshot in
            recordingDevice(source, identity: identity, snapshot: snapshot)
        }
        recordingDevice?.id = context.repositoryIDs.recordingDevice?.primitive

        let primaryResource = try primaryResource(
            record,
            sourceRecord: sourceRecord,
            sourceOutput: sourceOutput,
            sourceArtifact: sourceArtifact,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        let primaryProxy: ResourceProxy
        switch primaryResource {
        case .observation(var observation):
            observation.id = context.repositoryIDs.record?.primitive
            primaryProxy = ResourceProxy(with: observation)
        case .recordingDocument(var document):
            document.id = context.repositoryIDs.record?.primitive
            primaryProxy = ResourceProxy(with: document)
        }

        var provenance = try provenance(
            sourceIdentifier: sourceRecord.fhirIdentifier,
            targetURL: recordURL,
            converterURL: converterURL,
            recordedAt: context.recordedAt
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        var entries = [
            try ExchangeIdentity.entry(identifier: sourceOutput, resource: primaryProxy)
        ]
        if let recordingDevice, let recordingDeviceSnapshot {
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
            nodeKey: provenanceNode,
            resource: ResourceProxy(with: provenance)
        ))
        try ExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: context.eventIdentifier.businessIdentifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.recordedAt)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive
        let graph = try ExchangeGraph(
            kind: .active,
            eventIdentifier: context.eventIdentifier,
            bundle: bundle
        )

        let retainedPrimary: SensorPrimaryResource
        switch primaryResource {
        case .observation(var observation):
            observation.id = context.repositoryIDs.record?.primitive
            retainedPrimary = .observation(observation)
        case .recordingDocument(var document):
            document.id = context.repositoryIDs.record?.primitive
            retainedPrimary = .recordingDocument(document)
        }
        return SensorConversion(
            sourceIdentifier: sourceRecord.fhirIdentifier,
            sourceTypeIdentifier: record.sourceTypeIdentifier,
            graphIdentifiers: SensorGraphIdentifiers(
                event: context.eventIdentifier.businessIdentifier,
                sourceRecord: sourceRecord,
                sourceOutput: sourceOutput,
                sourceArtifact: sourceArtifact,
                recordingDevice: recordingDeviceIdentity,
                recordingDeviceSnapshot: recordingDeviceSnapshot,
                converterApplicationSnapshot: converterApplicationIdentity,
                converterHostSnapshot: converterHostIdentity,
                provenance: provenanceNode.identifier
            ),
            primaryResource: retainedPrimary,
            recordingDevice: recordingDevice,
            converterApplication: converterApplication,
            converterHost: converterHost,
            provenance: provenance,
            graph: graph
        )
    }

    private static func validate(context: SensorConversionContext) throws {
        guard !context.adapterID.isEmpty else {
            throw SensorConversionError.invalidExchangeIdentity("adapterID is empty")
        }
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorConversionError.invalidConverterApplication("name")
        }
        guard !context.converter.sourceDeviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorConversionError.invalidConverterApplication("sourceDeviceToken")
        }
        guard !context.converterHost.sourceDeviceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorConversionError.invalidConverterApplication("converterHost.sourceDeviceToken")
        }
        guard !context.converterHost.operatingSystemVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorConversionError.invalidConverterApplication("converterHost.operatingSystemVersion")
        }
        if context.converter.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw SensorConversionError.invalidConverterApplication("version")
        }
        if context.repositoryIDs.recordingDevice != nil, context.recordingDevice == nil {
            throw SensorConversionError.repositoryIDWithoutRecordingDevice
        }
        if context.recordingDevice?.stableUnitToken.isEmpty == true {
            throw SensorConversionError.invalidExchangeIdentity("recordingDevice.stableUnitToken is empty")
        }
        _ = try validateReference(context.subject, field: "subject", expectedResourceType: .patient)
        var studyIdentities: Set<TypedReferenceIdentity> = []
        for study in context.researchStudies {
            let identity = try validateReference(
                study,
                field: "researchStudies",
                expectedResourceType: .researchStudy
            )
            guard studyIdentities.insert(identity).inserted else {
                throw SensorConversionError.duplicateReference(field: "researchStudies")
            }
        }
    }

    private static func validateReference(
        _ reference: Reference,
        field: String,
        expectedResourceType: ResourceType
    ) throws(SensorConversionError) -> TypedReferenceIdentity {
        do {
            return try TypedReference.validate(
                reference,
                expectedResourceType: expectedResourceType
            )
        } catch {
            switch error {
            case .literalRequiresBundleEntry:
                throw .invalidExchangeIdentity(
                    "\(field) must use an identifier-only logical Reference; literals require a Bundle entry"
                )
            case .invalidReference:
                throw .invalidReference(field: field, expectedResourceType: expectedResourceType)
            }
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


private func zip<A, B, C>(_ first: A?, _ second: B?, _ third: C?) -> (A, B, C)? {
    guard let first, let second, let third else {
        return nil
    }
    return (first, second, third)
}
