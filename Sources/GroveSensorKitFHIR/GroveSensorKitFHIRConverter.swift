//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// One graph assembly transaction remains contiguous so identifiers, references, and repository ids
// can be reviewed as a single deterministic operation against the exchange contract.
// swiftlint:disable function_body_length multiline_literal_brackets

import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// Optional repository-assigned logical ids for one SensorKit conversion graph.
public struct GroveSensorKitFHIRRepositoryIDs: Hashable, Sendable {
    public let bundle: GroveFHIRRepositoryID?
    public let structuredOutput: GroveFHIRRepositoryID?
    public let rawOutput: GroveFHIRRepositoryID?
    public let recordingDevice: GroveFHIRRepositoryID?
    public let converterApplication: GroveFHIRRepositoryID?
    public let provenance: GroveFHIRRepositoryID?

    public init(
        bundle: GroveFHIRRepositoryID? = nil,
        structuredOutput: GroveFHIRRepositoryID? = nil,
        rawOutput: GroveFHIRRepositoryID? = nil,
        recordingDevice: GroveFHIRRepositoryID? = nil,
        converterApplication: GroveFHIRRepositoryID? = nil,
        provenance: GroveFHIRRepositoryID? = nil
    ) {
        self.bundle = bundle
        self.structuredOutput = structuredOutput
        self.rawOutput = rawOutput
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.provenance = provenance
    }
}


/// Explicit deployment, formatting, and audit inputs for one deterministic graph.
public struct GroveSensorKitFHIRConversionContext: Sendable {
    public let subject: Reference
    public let converter: GroveSensorFHIRApplication
    public let graphIdentifierSystem: String
    public let recordingDevice: GroveSensorFHIRRecordingDevice?
    public let converterWasGateway: Bool
    public let sourceTimeZone: TimeZone
    public let issuedAt: Date
    public let recordedAt: Date
    public let researchStudies: [Reference]
    public let repositoryIDs: GroveSensorKitFHIRRepositoryIDs

    public init(
        subject: Reference,
        converter: GroveSensorFHIRApplication,
        graphIdentifierSystem: String,
        recordingDevice: GroveSensorFHIRRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        sourceTimeZone: TimeZone,
        issuedAt: Date,
        recordedAt: Date,
        researchStudies: [Reference] = [],
        repositoryIDs: GroveSensorKitFHIRRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem
        self.recordingDevice = recordingDevice
        self.converterWasGateway = converterWasGateway
        self.sourceTimeZone = sourceTimeZone
        self.issuedAt = issuedAt
        self.recordedAt = recordedAt
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// One complete SensorKit structured, raw, or hybrid FHIR graph.
public struct GroveSensorKitFHIRConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let sourceTypeToken: String
    public let outputIdentifiers: [GroveFHIRBusinessIdentifier]
    public let observations: [Observation]
    public let recordingDocument: DocumentReference?
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let provenance: Provenance
    public let bundle: ModelsR4.Bundle
}


public enum GroveSensorKitFHIRConversionError: Error, Equatable, Sendable {
    case invalidRecord(GroveSensorKitFHIRRecordError)
    case invalidConverterApplication(String)
    case invalidReference(String)
    case duplicateResearchStudyReference
    case invalidIdentity(String)
    case repositoryIDWithoutStructuredOutput
    case repositoryIDWithoutRawOutput
    case repositoryIDWithoutRecordingDevice
    case payloadTooLarge(byteCount: Int)
}


public struct GroveSensorKitFHIRRecordFailure: Error, Equatable, Sendable {
    public let sourceRecordID: GroveSensorKitSourceRecordID
    public let reason: GroveSensorKitFHIRConversionError
}


public struct GroveSensorKitFHIRBatchResult: Sendable {
    public let conversions: [GroveSensorKitFHIRConversion]
    public let failures: [GroveSensorKitFHIRRecordFailure]
}


/// A no-fetch SensorKit adapter that emits only catalog-admitted R4 graph shapes.
public struct GroveSensorKitFHIRConverter: Sendable {
    public init() {}

    public func convert(
        _ record: GroveSensorKitFHIRRecord,
        context: GroveSensorKitFHIRConversionContext
    ) throws -> GroveSensorKitFHIRConversion {
        do {
            return try Self.convertRecord(record, context: context)
        } catch let error as GroveSensorKitFHIRConversionError {
            throw error
        } catch let error as GroveSensorKitFHIRRecordError {
            throw GroveSensorKitFHIRConversionError.invalidRecord(error)
        } catch {
            throw GroveSensorKitFHIRConversionError.invalidIdentity(String(describing: error))
        }
    }

    public func convert<S: Sequence>(
        _ records: S,
        context: GroveSensorKitFHIRConversionContext
    ) -> GroveSensorKitFHIRBatchResult where S.Element == GroveSensorKitFHIRRecord {
        var conversions: [GroveSensorKitFHIRConversion] = []
        var failures: [GroveSensorKitFHIRRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: context))
            } catch let reason as GroveSensorKitFHIRConversionError {
                failures.append(.init(sourceRecordID: record.sourceRecordID, reason: reason))
            } catch {
                failures.append(.init(
                    sourceRecordID: record.sourceRecordID,
                    reason: .invalidIdentity(String(describing: error))
                ))
            }
        }
        return GroveSensorKitFHIRBatchResult(conversions: conversions, failures: failures)
    }
}


extension GroveSensorKitFHIRRecord {
    var sourceRecordID: GroveSensorKitSourceRecordID {
        switch self {
        case .rotationRate(let record): record.sourceRecordID
        case .electrocardiogram(let record): record.sourceRecordID
        case .onWrist(let record): record.sourceRecordID
        case .deviceUsage(let record): record.sourceRecordID
        case .visit(let record): record.sourceRecordID
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
        case .raw: (nil, "native-recording")
        }
    }
}


extension GroveSensorKitFHIRConverter {
    struct OutputNode {
        let discriminator: String
        let identifier: GroveFHIRBusinessIdentifier
        let fullURL: String
    }

    private static func convertRecord(
        _ record: GroveSensorKitFHIRRecord,
        context: GroveSensorKitFHIRConversionContext
    ) throws -> GroveSensorKitFHIRConversion {
        try validate(record: record, context: context)
        let sourceIdentifier = try record.sourceRecordID.businessIdentifier
        let descriptors = record.discriminators
        let structuredNode = try descriptors.structured.map {
            try outputNode(source: record.sourceRecordID, discriminator: $0)
        }
        let rawNode = try descriptors.raw.map {
            try outputNode(source: record.sourceRecordID, discriminator: $0)
        }
        let converterURL = try GroveFHIRExchangeIdentity.fullURL(for: context.converter.identifier)
        let recordingDeviceURL = try context.recordingDevice.map {
            try GroveFHIRExchangeIdentity.fullURL(for: $0.identifier)
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
        if let id = context.repositoryIDs.structuredOutput {
            guard !observations.isEmpty else {
                throw GroveSensorKitFHIRConversionError.repositoryIDWithoutStructuredOutput
            }
            observations[0].id = id.primitive
        }
        var document = try buildDocument(
            record,
            sourceIdentifier: sourceIdentifier,
            outputNode: rawNode,
            relatedURLs: structuredNode.map { [$0.fullURL] } ?? [],
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        if let id = context.repositoryIDs.rawOutput {
            guard document != nil else {
                throw GroveSensorKitFHIRConversionError.repositoryIDWithoutRawOutput
            }
            document?.id = id.primitive
        }

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        var recordingDevice = context.recordingDevice.map(recordingDevice)
        recordingDevice?.id = context.repositoryIDs.recordingDevice?.primitive

        let outputNodes = [structuredNode, rawNode].compactMap { $0 }
        let provenanceIdentifier = try graphIdentifier(
            role: "sensorkit-provenance",
            source: record.sourceRecordID,
            system: context.graphIdentifierSystem
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
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: structuredNode.identifier,
                resource: ResourceProxy(with: observation)
            ))
        }
        if let rawNode, let document {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: rawNode.identifier,
                resource: ResourceProxy(with: document)
            ))
        }
        if let recordingDevice, let identity = context.recordingDevice?.identifier {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: identity,
                resource: ResourceProxy(with: recordingDevice)
            ))
        }
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: context.converter.identifier,
            resource: ResourceProxy(with: converterApplication)
        ))
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: provenanceIdentifier,
            resource: ResourceProxy(with: provenance)
        ))
        try GroveFHIRExchangeIdentity.validate(entries: entries)

        let bundleIdentifier = try graphIdentifier(
            role: "sensorkit-exchange",
            source: record.sourceRecordID,
            system: context.graphIdentifierSystem
        )
        var bundle = Bundle(
            entry: entries,
            identifier: bundleIdentifier.fhirIdentifier,
            meta: Meta(profile: [GroveFHIRProfile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try exactInstant(context.recordedAt, timeZone: context.sourceTimeZone)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive
        return GroveSensorKitFHIRConversion(
            sourceIdentifier: sourceIdentifier.fhirIdentifier,
            sourceTypeToken: record.sourceToken,
            outputIdentifiers: outputNodes.map(\.identifier),
            observations: observations,
            recordingDocument: document,
            recordingDevice: recordingDevice,
            converterApplication: converterApplication,
            provenance: provenance,
            bundle: bundle
        )
    }

    private static func outputNode(
        source: GroveSensorKitSourceRecordID,
        discriminator: String
    ) throws -> OutputNode {
        let identifier = try GroveSensorKitOutputIdentity.businessIdentifier(
            source: source,
            discriminator: discriminator
        )
        return OutputNode(
            discriminator: discriminator,
            identifier: identifier,
            fullURL: try GroveFHIRExchangeIdentity.fullURL(for: identifier)
        )
    }

    private static func graphIdentifier(
        role: String,
        source: GroveSensorKitSourceRecordID,
        system: String
    ) throws -> GroveFHIRBusinessIdentifier {
        try GroveFHIRBusinessIdentifier(system: system, value: "\(role):\(source.value)")
    }

    private static func validate(
        record: GroveSensorKitFHIRRecord,
        context: GroveSensorKitFHIRConversionContext
    ) throws {
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveSensorKitFHIRConversionError.invalidConverterApplication("name")
        }
        if context.converter.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw GroveSensorKitFHIRConversionError.invalidConverterApplication("version")
        }
        _ = try GroveFHIRBusinessIdentifier(system: context.graphIdentifierSystem, value: "validation")
        do {
            _ = try GroveFHIRTypedReference.validate(context.subject, expectedResourceType: "Patient")
            var identities: Set<GroveFHIRTypedReferenceIdentity> = []
            for study in context.researchStudies {
                let identity = try GroveFHIRTypedReference.validate(study, expectedResourceType: "ResearchStudy")
                guard identities.insert(identity).inserted else {
                    throw GroveSensorKitFHIRConversionError.duplicateResearchStudyReference
                }
            }
        } catch let error as GroveSensorKitFHIRConversionError {
            throw error
        } catch {
            throw GroveSensorKitFHIRConversionError.invalidReference(String(describing: error))
        }
        if context.repositoryIDs.recordingDevice != nil, context.recordingDevice == nil {
            throw GroveSensorKitFHIRConversionError.repositoryIDWithoutRecordingDevice
        }
        guard let entry = SensorKitFHIRCatalog.current.entries.first(where: {
            $0.sourceToken == record.sourceToken
        }) else {
            throw GroveSensorKitFHIRRecordError.sourceTypeNotAdmitted(record.sourceToken)
        }
        if case .raw = record, entry.rawProfiles.isEmpty {
            throw GroveSensorKitFHIRRecordError.sourceTypeHasNoRawContract(record.sourceToken)
        }
    }

    private static func applicationDevice(_ application: GroveSensorFHIRApplication) -> Device {
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveApplicationDevice])
        device.identifier = [application.identifier.fhirIdentifier]
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
        return device
    }

    private static func recordingDevice(_ source: GroveSensorFHIRRecordingDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveRecordingDevice])
        device.identifier = [source.identifier.fhirIdentifier]
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
