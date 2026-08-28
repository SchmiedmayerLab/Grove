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
public struct SensorKitRepositoryIDs: Hashable, Sendable {
    public let bundle: RepositoryID?
    public let structuredOutput: RepositoryID?
    public let rawOutput: RepositoryID?
    public let recordingDevice: RepositoryID?
    public let converterApplication: RepositoryID?
    public let provenance: RepositoryID?

    public init(
        bundle: RepositoryID? = nil,
        structuredOutput: RepositoryID? = nil,
        rawOutput: RepositoryID? = nil,
        recordingDevice: RepositoryID? = nil,
        converterApplication: RepositoryID? = nil,
        provenance: RepositoryID? = nil
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
public struct SensorKitConversionContext: Sendable {
    public let subject: Reference
    public let converter: SensorApplication
    public let graphIdentifierSystem: IdentifierSystem
    public let recordingDevice: SensorRecordingDevice?
    public let converterWasGateway: Bool
    public let sourceTimeZone: TimeZone
    public let issuedAt: Date
    public let recordedAt: Date
    /// Whether identifiers that recur across records may be disclosed.
    public let linkableIdentifierPolicy: SensorKitLinkableIdentifierPolicy
    public let researchStudies: [Reference]
    public let repositoryIDs: SensorKitRepositoryIDs

    public init(
        subject: Reference,
        converter: SensorApplication,
        graphIdentifierSystem: IdentifierSystem,
        recordingDevice: SensorRecordingDevice? = nil,
        converterWasGateway: Bool = false,
        sourceTimeZone: TimeZone,
        issuedAt: Date,
        recordedAt: Date,
        linkableIdentifierPolicy: SensorKitLinkableIdentifierPolicy = .omit,
        researchStudies: [Reference] = [],
        repositoryIDs: SensorKitRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem
        self.recordingDevice = recordingDevice
        self.converterWasGateway = converterWasGateway
        self.sourceTimeZone = sourceTimeZone
        self.issuedAt = issuedAt
        self.recordedAt = recordedAt
        self.linkableIdentifierPolicy = linkableIdentifierPolicy
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// One complete SensorKit structured, raw, or hybrid FHIR graph.
public struct SensorKitConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let sourceTypeToken: String
    public let outputIdentifiers: [BusinessIdentifier]
    public let observations: [Observation]
    public let recordingDocument: DocumentReference?
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let provenance: Provenance
    public let bundle: ModelsR4.Bundle
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
        context: SensorKitConversionContext
    ) -> SensorKitBatchResult where S.Element == SensorKitRecord {
        var conversions: [SensorKitConversion] = []
        var failures: [SensorKitRecordFailure] = []
        for record in records {
            do {
                conversions.append(try convert(record, context: context))
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
        case .wristTemperature: ("wrist-temperature-recording-summary", "wrist-temperature-samples")
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
        let fullURL: String
    }

    private static func convertRecord(
        _ record: SensorKitRecord,
        context: SensorKitConversionContext
    ) throws -> SensorKitConversion {
        try validate(record: record, context: context)
        let sourceIdentifier = try record.sourceRecordID.businessIdentifier
        let descriptors = record.discriminators
        let structuredNode = try descriptors.structured.map {
            try outputNode(source: record.sourceRecordID, discriminator: $0)
        }
        let rawNode = try descriptors.raw.map {
            try outputNode(source: record.sourceRecordID, discriminator: $0)
        }
        let converterURL = try ExchangeIdentity.fullURL(for: context.converter.identifier)
        let recordingDeviceURL = try context.recordingDevice.map {
            try ExchangeIdentity.fullURL(for: $0.identifier)
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
                throw SensorKitConversionError.repositoryIDWithoutStructuredOutput
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
                throw SensorKitConversionError.repositoryIDWithoutRawOutput
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
            identifier: provenanceIdentifier,
            resource: ResourceProxy(with: provenance)
        ))
        try ExchangeIdentity.validate(entries: entries)

        let bundleIdentifier = try graphIdentifier(
            role: "sensorkit-exchange",
            source: record.sourceRecordID,
            system: context.graphIdentifierSystem
        )
        var bundle = Bundle(
            entry: entries,
            identifier: bundleIdentifier.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try exactInstant(context.recordedAt, timeZone: context.sourceTimeZone)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive
        return SensorKitConversion(
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
        source: SensorKitSourceRecordID,
        discriminator: String
    ) throws -> OutputNode {
        let identifier = try SensorKitOutputIdentity.businessIdentifier(
            source: source,
            discriminator: discriminator
        )
        return OutputNode(
            identifier: identifier,
            fullURL: try ExchangeIdentity.fullURL(for: identifier)
        )
    }

    private static func graphIdentifier(
        role: String,
        source: SensorKitSourceRecordID,
        system: IdentifierSystem
    ) throws -> BusinessIdentifier {
        try BusinessIdentifier(system: system, value: "\(role):\(source.value)")
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
            case .unboundBundleUUID:
                throw .invalidIdentity(
                    "\(field) contains a UUID URN that is not an entry in the emitted Bundle"
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
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SensorKitConversionError.invalidConverterApplication("name")
        }
        if context.converter.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw SensorKitConversionError.invalidConverterApplication("version")
        }
        _ = try validatedReference(context.subject, field: "subject", expectedResourceType: .patient)
        var identities: Set<TypedReferenceIdentity> = []
        for study in context.researchStudies {
            let identity = try validatedReference(
                study,
                field: "researchStudies",
                expectedResourceType: .researchStudy
            )
            guard identities.insert(identity).inserted else {
                throw SensorKitConversionError.duplicateResearchStudyReference
            }
        }
        if context.repositoryIDs.recordingDevice != nil, context.recordingDevice == nil {
            throw SensorKitConversionError.repositoryIDWithoutRecordingDevice
        }
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

    private static func recordingDevice(_ source: SensorRecordingDevice) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveRecordingDevice])
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
