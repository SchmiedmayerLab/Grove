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


/// Product identity of the application performing a Sensor-to-FHIR conversion.
public struct SensorApplication: Hashable, Sendable {
    public let identifier: BusinessIdentifier
    public let name: String
    public let version: String?

    public init(identifier: BusinessIdentifier, name: String, version: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.version = version
    }
}


/// Identity and descriptive fields of the physical recording device, when known.
public struct SensorRecordingDevice: Hashable, Sendable {
    public let identifier: BusinessIdentifier
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    public init(
        identifier: BusinessIdentifier,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) {
        self.identifier = identifier
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
    public let provenance: RepositoryID?

    public init(
        bundle: RepositoryID? = nil,
        record: RepositoryID? = nil,
        recordingDevice: RepositoryID? = nil,
        converterApplication: RepositoryID? = nil,
        provenance: RepositoryID? = nil
    ) {
        self.bundle = bundle
        self.record = record
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.provenance = provenance
    }
}


/// Explicit deployment and audit inputs used to build one reproducible graph.
public struct SensorConversionContext: Sendable {
    public let subject: Reference
    public let converter: SensorApplication
    public let graphIdentifierSystem: IdentifierSystem
    public let recordingDevice: SensorRecordingDevice?
    public let converterWasGateway: Bool
    public let issuedAt: Date
    public let recordedAt: Date
    public let researchStudies: [Reference]
    public let repositoryIDs: SensorRepositoryIDs

    public init(
        subject: Reference,
        converter: SensorApplication,
        graphIdentifierSystem: IdentifierSystem,
        recordingDevice: SensorRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        issuedAt: Date,
        recordedAt: Date,
        researchStudies: [Reference] = [],
        repositoryIDs: SensorRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem
        self.recordingDevice = recordingDevice
        self.converterWasGateway = converterWasGateway
        self.issuedAt = issuedAt
        self.recordedAt = recordedAt
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// Complete business identities of one emitted Sensor exchange graph.
public struct SensorGraphIdentifiers: Hashable, Sendable {
    public let bundle: BusinessIdentifier
    public let record: BusinessIdentifier
    public let recordingDevice: BusinessIdentifier?
    public let converterApplication: BusinessIdentifier
    public let provenance: BusinessIdentifier?
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
    public let provenance: Provenance?
    public let bundle: ModelsR4.Bundle
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
        context: SensorConversionContext
    ) -> SensorBatchResult where S.Element == SensorRecord {
        var conversions: [SensorConversion] = []
        var failures: [SensorRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: context))
            } catch {
                failures.append(SensorRecordFailure(
                    sourceIdentifier: record.identifier,
                    sourceTypeIdentifier: record.sourceTypeIdentifier,
                    reason: error
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
        let bundleIdentity = try derivedIdentity(
            role: "exchange-bundle",
            record: record.identifier,
            system: context.graphIdentifierSystem
        )
        let provenanceIdentity = try derivedIdentity(
            role: "conversion-provenance",
            record: record.identifier,
            system: context.graphIdentifierSystem
        )

        let recordURL = try ExchangeIdentity.fullURL(for: record.identifier)
        let converterURL = try ExchangeIdentity.fullURL(for: context.converter.identifier)
        let recordingDeviceURL = try context.recordingDevice.map {
            try ExchangeIdentity.fullURL(for: $0.identifier)
        }

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        var recordingDevice = context.recordingDevice.map(recordingDevice)
        recordingDevice?.id = context.repositoryIDs.recordingDevice?.primitive

        let primaryResource = try primaryResource(
            record,
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
            sourceIdentifier: record.identifier.fhirIdentifier,
            targetURL: recordURL,
            converterURL: converterURL,
            recordedAt: context.recordedAt
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        var entries = [
            try ExchangeIdentity.entry(identifier: record.identifier, resource: primaryProxy)
        ]
        if let recordingDevice, let identity = context.recordingDevice?.identifier {
            entries.append(try ExchangeIdentity.entry(
                identifier: identity,
                resource: ResourceProxy(with: recordingDevice)
            ))
        }
        entries.append(try ExchangeIdentity.entry(
            identifier: context.converter.identifier,
            resource: ResourceProxy(with: converterApplication)
        ))
        entries.append(try ExchangeIdentity.entry(
            identifier: provenanceIdentity,
            resource: ResourceProxy(with: provenance)
        ))
        try ExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: bundleIdentity.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.recordedAt)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive

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
            sourceIdentifier: record.identifier.fhirIdentifier,
            sourceTypeIdentifier: record.sourceTypeIdentifier,
            graphIdentifiers: SensorGraphIdentifiers(
                bundle: bundleIdentity,
                record: record.identifier,
                recordingDevice: context.recordingDevice?.identifier,
                converterApplication: context.converter.identifier,
                provenance: provenanceIdentity
            ),
            primaryResource: retainedPrimary,
            recordingDevice: recordingDevice,
            converterApplication: converterApplication,
            provenance: provenance,
            bundle: bundle
        )
    }

    private static func validate(context: SensorConversionContext) throws {
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorConversionError.invalidConverterApplication("name")
        }
        if context.converter.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw SensorConversionError.invalidConverterApplication("version")
        }
        if context.repositoryIDs.recordingDevice != nil, context.recordingDevice == nil {
            throw SensorConversionError.repositoryIDWithoutRecordingDevice
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
            case .unboundBundleUUID:
                throw .invalidExchangeIdentity(
                    "\(field) contains a UUID URN that is not an entry in the emitted Bundle"
                )
            case .invalidReference:
                throw .invalidReference(field: field, expectedResourceType: expectedResourceType)
            }
        }
    }

    private static func derivedIdentity(
        role: String,
        record: BusinessIdentifier,
        system: IdentifierSystem
    ) throws -> BusinessIdentifier {
        let recordURL = try ExchangeIdentity.fullURL(for: record)
        let recordUUID = recordURL.dropFirst("urn:uuid:".count)
        return try BusinessIdentifier(system: system, value: "\(role):\(recordUUID)")
    }
}
