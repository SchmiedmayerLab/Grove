//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The converter keeps the complete graph transaction together; literal formatting follows FHIR shape.
// swiftlint:disable file_length multiline_literal_brackets

#if canImport(HealthKit)

import FHIRModelsExtensions
public import Foundation
public import GroveFHIRContract
import GroveHealthKit
public import HealthKit
public import ModelsR4


/// Product identity of the application performing a HealthKit-to-FHIR conversion.
public struct HealthKitFHIRApplication: Hashable, Sendable {
    /// The identity of the running application, read from its main bundle.
    ///
    /// Requires a bundle identifier, so it is unavailable in bare test runners; pass explicit
    /// values there instead.
    public static var main: HealthKitFHIRApplication {
        let bundle = Bundle.main
        guard let identifier = bundle.bundleIdentifier else {
            preconditionFailure("Bundle.main carries no bundle identifier; supply an explicit HealthKitFHIRApplication.")
        }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? identifier
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = (info["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        return HealthKitFHIRApplication(name: name, bundleIdentifier: identifier, version: version + build)
    }

    public let name: String
    public let bundleIdentifier: String
    public let version: String

    /// The identifier namespace this application owns for graph nodes it mints.
    ///
    /// A bundle identifier is globally unique and stable across releases, so it is a valid
    /// default namespace for a deployment that does not yet own a server URL. Override it with
    /// ``HealthKitFHIRConversionContext/graphIdentifierSystem`` once one exists.
    public var graphIdentifierSystem: String {
        "urn:grove:healthkit-graph:\(bundleIdentifier)"
    }

    public init(name: String, bundleIdentifier: String, version: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
    }
}


/// Explicit interpretation of `HKSourceRevision.source` for one conversion.
///
/// HealthKit exposes no reliable application/device discriminator. The converter never
/// guesses from a name, identifier shape, or product type.
public enum HealthKitFHIRSourceActor: Hashable, Sendable {
    /// Omit the source author from Provenance.
    case omit
    /// The caller has established that the source is an application.
    case application
    /// The caller has established that the source is a device. The opaque HealthKit
    /// source identifier is disclosed only when explicitly authorized.
    case device(discloseIdentifier: Bool)
}


/// Controls disclosure of globally identifying recording-device information.
///
/// Selecting ``authorizedUDI`` is an explicit caller attestation that disclosing the
/// HealthKit UDI is necessary for the deployment and has been authorized. This is
/// independent of the deployment-local identifier namespace configured on
/// ``HealthKitFHIRConversionContext``.
public enum HealthKitFHIRUDIDisclosurePolicy: Hashable, Sendable {
    /// Omit globally identifying device information. This is the privacy-preserving default.
    case omit
    /// Disclose the UDI supplied by HealthKit after the caller has established necessity
    /// and authorization.
    case authorizedUDI
}


/// Controls disclosure of the complete source revision attached to a correlated ECG symptom.
///
/// The bundle identifier, product type, software version, and operating-system version can
/// be linkable. This policy is therefore independent of recording-device and UDI disclosure.
public enum HealthKitFHIRSourceDisclosurePolicy: Hashable, Sendable {
    /// Do not disclose correlated-symptom source revision fields. This is the default.
    /// Because the ECG contract requires those fields, correlated symptoms fail closed.
    case omit
    /// The caller has established necessity and authorization to disclose every required
    /// correlated-symptom `HKSourceRevision` field.
    case authorized
}


/// Optional logical ids already assigned by a FHIR repository.
///
/// These are never derived from HealthKit identities or Bundle UUID URNs.
public struct HealthKitFHIRRepositoryIDs: Hashable, Sendable {
    public let bundle: GroveFHIRRepositoryID?
    public let observation: GroveFHIRRepositoryID?
    public let recordingDevice: GroveFHIRRepositoryID?
    public let converterApplication: GroveFHIRRepositoryID?
    public let sourceAuthor: GroveFHIRRepositoryID?
    public let provenance: GroveFHIRRepositoryID?

    public init(
        bundle: GroveFHIRRepositoryID? = nil,
        observation: GroveFHIRRepositoryID? = nil,
        recordingDevice: GroveFHIRRepositoryID? = nil,
        converterApplication: GroveFHIRRepositoryID? = nil,
        sourceAuthor: GroveFHIRRepositoryID? = nil,
        provenance: GroveFHIRRepositoryID? = nil
    ) {
        self.bundle = bundle
        self.observation = observation
        self.recordingDevice = recordingDevice
        self.converterApplication = converterApplication
        self.sourceAuthor = sourceAuthor
        self.provenance = provenance
    }
}


/// Explicit inputs needed to make a reproducible, auditable FHIR graph.
public struct HealthKitFHIRConversionContext: Sendable {
    public let subject: Reference
    public let converter: HealthKitFHIRApplication
    /// Deployment-owned identifier namespace for graph nodes that have no natural identity.
    ///
    /// A sample's Observation is identified by its HealthKit object UUID, but the Bundle, the
    /// conversion Provenance, and derived Device resources exist only because of this export.
    /// Their business identifiers are minted deterministically inside this namespace, so the
    /// same conversion always produces the same graph and re-sends deduplicate on the server.
    ///
    /// Defaults to ``HealthKitFHIRApplication/graphIdentifierSystem``, which is derived from the
    /// converting app's bundle identifier. Pass one stable URL you own once the deployment has a
    /// server namespace, for example `https://mystudy.example.org/fhir/identifiers/mobile-graph`.
    ///
    /// - Note: See <doc:ConfiguringAConversion> for what an identifier namespace is in FHIR.
    public let graphIdentifierSystem: String
    public let sourceActor: HealthKitFHIRSourceActor
    public let converterWasGateway: Bool
    /// The instant of this conversion event.
    ///
    /// Written to `Observation.issued`, `Provenance.occurred`/`recorded`, and `Bundle.timestamp`;
    /// each sample's own measurement time always comes from the sample and lands in
    /// `Observation.effective`. Defaults to the wall clock; pass a fixed instant to make a
    /// conversion reproducible.
    public let conversionInstant: Date
    /// Deployment-owned namespace that authorizes disclosure of an opaque, local
    /// `HKDevice.localIdentifier`. It does not authorize UDI disclosure.
    public let recordingDeviceIdentifierSystem: String?
    /// Opaque deployment-owned scope that lets one physical recorder deduplicate across samples.
    ///
    /// Without it every sample carries its own recording `Device`, so one watch is stored once
    /// per reading. Supplying a stable scope switches the recorder to the published
    /// `GroveFHIRRecordingDeviceIdentity` digest, which yields one Device per recorder
    /// configuration instead. The scope is hashed into the identifier and never serialized.
    ///
    /// Fix it once per deployment and keep it: changing it re-mints every recording Device, so
    /// graphs exported before the change no longer deduplicate against later ones.
    public let deviceIdentityScope: String?
    /// Explicit UDI disclosure policy. The default omits the UDI even when HealthKit
    /// supplies one.
    public let udiDisclosurePolicy: HealthKitFHIRUDIDisclosurePolicy
    /// Explicit policy for the linkable source-revision evidence required by correlated
    /// ECG symptoms.
    public let sourceRevisionDisclosurePolicy: HealthKitFHIRSourceDisclosurePolicy
    public let researchStudies: [Reference]
    public let repositoryIDs: HealthKitFHIRRepositoryIDs

    /// Creates a conversion context, deriving everything that can be read from the running app.
    ///
    /// Only ``subject`` has no local answer: nothing on the device knows who the receiving
    /// system thinks this data is about. See <doc:ConfiguringAConversion>.
    ///
    /// ```swift
    /// let context = HealthKitFHIRConversionContext(subject: Reference(reference: "Patient/example"))
    /// ```
    public init(
        subject: Reference,
        converter: HealthKitFHIRApplication = .main,
        graphIdentifierSystem: String? = nil,
        sourceActor: HealthKitFHIRSourceActor = .omit,
        converterWasGateway: Bool = false,
        conversionInstant: Date = .now,
        recordingDeviceIdentifierSystem: String? = nil,
        deviceIdentityScope: String? = nil,
        udiDisclosurePolicy: HealthKitFHIRUDIDisclosurePolicy = .omit,
        sourceRevisionDisclosurePolicy: HealthKitFHIRSourceDisclosurePolicy = .omit,
        researchStudies: [Reference] = [],
        repositoryIDs: HealthKitFHIRRepositoryIDs = .init()
    ) {
        self.subject = subject
        self.converter = converter
        self.graphIdentifierSystem = graphIdentifierSystem ?? converter.graphIdentifierSystem
        self.sourceActor = sourceActor
        self.converterWasGateway = converterWasGateway
        self.conversionInstant = conversionInstant
        self.recordingDeviceIdentifierSystem = recordingDeviceIdentifierSystem
        self.deviceIdentityScope = deviceIdentityScope
        self.udiDisclosurePolicy = udiDisclosurePolicy
        self.sourceRevisionDisclosurePolicy = sourceRevisionDisclosurePolicy
        self.researchStudies = researchStudies
        self.repositoryIDs = repositoryIDs
    }
}


/// Complete business identities of one emitted exchange graph.
public struct HealthKitFHIRGraphIdentifiers: Hashable, Sendable {
    public let bundle: GroveFHIRBusinessIdentifier
    public let observation: GroveFHIRBusinessIdentifier
    public let recordingDevice: GroveFHIRBusinessIdentifier?
    public let converterApplication: GroveFHIRBusinessIdentifier
    public let sourceAuthor: GroveFHIRBusinessIdentifier?
    public let provenance: GroveFHIRBusinessIdentifier
}


/// One complete conversion graph.
///
/// Resources have no logical `Resource.id` unless the caller supplied a repository id.
/// Deterministic UUIDv5 Bundle fullUrls connect graph entries.
public struct HealthKitFHIRConversion: Sendable {
    public let sourceIdentifier: Identifier
    public let graphIdentifiers: HealthKitFHIRGraphIdentifiers
    public let observation: Observation
    public let recordingDevice: Device?
    public let converterApplication: Device
    public let sourceAuthor: Device?
    public let provenance: Provenance
    public let bundle: ModelsR4.Bundle
}


/// Failure for one record in a batch. The original source identity and typed reason are
/// retained; batch conversion never drops a record silently.
public struct HealthKitFHIRRecordFailure: Error, Equatable, Sendable {
    public let sourceUUID: UUID
    public let sourceTypeIdentifier: String
    public let reason: GroveHealthKitFHIRError
}


/// Explicit successes and failures from a batch conversion.
public struct HealthKitFHIRBatchResult: Sendable {
    public let conversions: [HealthKitFHIRConversion]
    public let failures: [HealthKitFHIRRecordFailure]
}


/// Profile-aware HealthKit-to-FHIR R4 facade.
///
/// The converter consumes already-fetched `HKSample` values. It does not query HealthKit,
/// authorize data access, synchronize anchors, persist resources, or upload anything.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitFHIRConverter: Sendable {
    public init() {}

    /// Converts one sample only when the closed catalog admits its exact published contract.
    public func convert(
        _ sample: HKSample,
        context: HealthKitFHIRConversionContext
    ) throws(GroveHealthKitFHIRError) -> HealthKitFHIRConversion {
        do {
            return try Self.convertSample(sample, context: context)
        } catch {
            throw GroveHealthKitFHIRError(conversionFailure: error)
        }
    }

    /// Converts one sample for a subject, deriving the rest of the context from the running app.
    ///
    /// Equivalent to building a ``HealthKitFHIRConversionContext`` with only its subject. Use the
    /// context form to set a study reference, a disclosure policy, or a fixed conversion instant.
    ///
    /// ```swift
    /// let conversion = try HealthKitFHIRConverter().convert(sample, for: patient)
    /// ```
    public func convert(
        _ sample: HKSample,
        for subject: Reference
    ) throws(GroveHealthKitFHIRError) -> HealthKitFHIRConversion {
        try convert(sample, context: HealthKitFHIRConversionContext(subject: subject))
    }

    /// Converts every input for a subject, deriving the rest of the context from the running app.
    public func convert<S: Sequence>(
        _ samples: S,
        for subject: Reference
    ) -> HealthKitFHIRBatchResult where S.Element == HKSample {
        convert(samples, context: HealthKitFHIRConversionContext(subject: subject))
    }

    /// Converts every input and returns a typed failure for every record that was not emitted.
    public func convert<S: Sequence>(
        _ samples: S,
        context: HealthKitFHIRConversionContext
    ) -> HealthKitFHIRBatchResult where S.Element == HKSample {
        var conversions: [HealthKitFHIRConversion] = []
        var failures: [HealthKitFHIRRecordFailure] = []
        for sample in samples {
            do {
                conversions.append(try convert(sample, context: context))
            } catch {
                failures.append(HealthKitFHIRRecordFailure(
                    sourceUUID: sample.uuid,
                    sourceTypeIdentifier: sample.sampleType.identifier,
                    reason: error
                ))
            }
        }
        return HealthKitFHIRBatchResult(conversions: conversions, failures: failures)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRConverter {
    private struct IdentifiedDevice {
        var resource: Device
        let identity: GroveFHIRBusinessIdentifier
    }

    private struct HealthKitSleepStage {
        let sharedCode: String
        let sharedDisplay: String
        let sourceCode: String
        let sourceDisplay: String
    }

    private static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    private static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    private static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"
    private static let observationCategory: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/observation-category"
    /// Displays for the measurements whose generated contract carries no code display.
    private static let measurementDisplays = [
        "blood-pressure": "Blood pressure panel with all children optional",
        "body-height": "Body height",
        "body-mass-index": "Body mass index (BMI) [Ratio]",
        "body-temperature": "Body temperature",
        "body-weight": "Body weight",
        "distance": "Distance traveled",
        "heart-rate": "Heart rate",
        "oxygen-saturation": "Oxygen saturation in Arterial blood",
        "respiratory-rate": "Respiratory rate"
    ]

    private static func convertSample(
        _ sample: HKSample,
        context: HealthKitFHIRConversionContext
    ) throws -> HealthKitFHIRConversion {
        try validate(context: context)
        if sample is HKElectrocardiogram {
            throw GroveHealthKitFHIRError.missingECGEvidence
        }
        guard let binding = HealthKitFHIRCatalog.binding(for: sample) else {
            throw unconvertibleSampleError(forSourceTypeIdentifier: sample.sampleType.identifier)
        }
        return try assembleGraph(for: sample, context: context) { recordingDeviceURL, converterURL in
            try observation(
                for: sample,
                binding: binding,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        }
    }

    // Assembly is intentionally one atomic, reviewable graph transaction.
    // swiftlint:disable:next function_body_length
    static func assembleGraph(
        for sample: HKSample,
        context: HealthKitFHIRConversionContext,
        observationBuilder: (_ recordingDeviceURL: String?, _ converterURL: String) throws -> Observation
    ) throws -> HealthKitFHIRConversion {
        let sourceUUID = sample.uuid
        let sourceUUIDString = sourceUUID.uuidString.lowercased()
        let observationIdentity = try GroveFHIRBusinessIdentifier(
            system: GroveFHIRCanonical.healthKitObjectIdentifierSystem,
            value: sourceUUIDString
        )
        let converterIdentity = try GroveFHIRBusinessIdentifier(
            system: GroveFHIRCanonical.appleBundleIdentifierSystem,
            value: context.converter.bundleIdentifier
        )
        let bundleIdentity = try derivedIdentity(
            context: context,
            sourceUUID: sourceUUIDString,
            role: "exchange-bundle"
        )
        let provenanceIdentity = try derivedIdentity(
            context: context,
            sourceUUID: sourceUUIDString,
            role: "conversion-provenance"
        )

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        var recordingDevice = try recordingDevice(
            for: sample.device,
            context: context,
            sourceUUID: sourceUUIDString
        )
        recordingDevice?.resource.id = context.repositoryIDs.recordingDevice?.primitive
        var sourceAuthor = try sourceAuthor(
            for: sample.sourceRevision,
            classification: context.sourceActor,
            context: context,
            sourceUUID: sourceUUIDString
        )
        if context.repositoryIDs.recordingDevice != nil, recordingDevice == nil {
            throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                "a recording-device repository id was supplied, but this record has no recording device"
            )
        }
        if context.repositoryIDs.sourceAuthor != nil, sourceAuthor == nil {
            throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                "a source-author repository id was supplied, but source authoring is omitted or unavailable"
            )
        }

        let sourceAuthorUsesConverter = sourceAuthor?.identity == converterIdentity
        if sourceAuthorUsesConverter {
            if let sourceID = context.repositoryIDs.sourceAuthor,
               let converterID = context.repositoryIDs.converterApplication,
               sourceID != converterID {
                throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                    "one application cannot have two repository ids in the same graph"
                )
            }
            converterApplication.id = (
                context.repositoryIDs.converterApplication ?? context.repositoryIDs.sourceAuthor
            )?.primitive
            sourceAuthor = IdentifiedDevice(resource: converterApplication, identity: converterIdentity)
        } else {
            sourceAuthor?.resource.id = context.repositoryIDs.sourceAuthor?.primitive
        }

        let observationURL = try GroveFHIRExchangeIdentity.fullURL(for: observationIdentity)
        let converterURL = try GroveFHIRExchangeIdentity.fullURL(for: converterIdentity)
        let recordingDeviceURL = try recordingDevice.map { try GroveFHIRExchangeIdentity.fullURL(for: $0.identity) }
        let sourceAuthorURL = try sourceAuthor.map { try GroveFHIRExchangeIdentity.fullURL(for: $0.identity) }
        var observation = try observationBuilder(recordingDeviceURL, converterURL)
        observation.id = context.repositoryIDs.observation?.primitive
        observation.identifier = [observationIdentity.fhirIdentifier]

        var provenance = try provenance(
            sourceIdentifier: observationIdentity.fhirIdentifier,
            targetURL: observationURL,
            converterURL: converterURL,
            sourceAuthorURL: sourceAuthorURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        var entries = [
            try GroveFHIRExchangeIdentity.entry(
                identifier: observationIdentity,
                resource: ResourceProxy(with: observation)
            )
        ]
        if let recordingDevice {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: recordingDevice.identity,
                resource: ResourceProxy(with: recordingDevice.resource)
            ))
        }
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: converterIdentity,
            resource: ResourceProxy(with: converterApplication)
        ))
        if let sourceAuthor, !sourceAuthorUsesConverter {
            entries.append(try GroveFHIRExchangeIdentity.entry(
                identifier: sourceAuthor.identity,
                resource: ResourceProxy(with: sourceAuthor.resource)
            ))
        }
        entries.append(try GroveFHIRExchangeIdentity.entry(
            identifier: provenanceIdentity,
            resource: ResourceProxy(with: provenance)
        ))
        try GroveFHIRExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: bundleIdentity.fhirIdentifier,
            meta: Meta(profile: [GroveFHIRProfile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.conversionInstant)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive

        return HealthKitFHIRConversion(
            sourceIdentifier: observationIdentity.fhirIdentifier,
            graphIdentifiers: HealthKitFHIRGraphIdentifiers(
                bundle: bundleIdentity,
                observation: observationIdentity,
                recordingDevice: recordingDevice?.identity,
                converterApplication: converterIdentity,
                sourceAuthor: sourceAuthor?.identity,
                provenance: provenanceIdentity
            ),
            observation: observation,
            recordingDevice: recordingDevice?.resource,
            converterApplication: converterApplication,
            sourceAuthor: sourceAuthor?.resource,
            provenance: provenance,
            bundle: bundle
        )
    }

    /// The catalog-driven reason a sample without a binding fails closed.
    static func unconvertibleSampleError(
        forSourceTypeIdentifier identifier: String
    ) -> GroveHealthKitFHIRError {
        guard let entry = HealthKitFHIRCatalog.entry(forSourceTypeIdentifier: identifier) else {
            return .unsupportedSampleType(identifier)
        }
        switch entry.implementationStatus {
        case .intentionallyUnsupported:
            return .intentionallyUnsupported(sampleType: identifier, reason: entry.requirement ?? "")
        case .platformExclusive:
            return .platformExclusiveDocument(sampleType: identifier)
        case .supported where identifier == HKWorkoutType.workoutType().identifier:
            return .notYetConvertible(sampleType: identifier)
        case .supported where identifier == HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
            || identifier == HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return .componentSampleRequiresCorrelation(sampleType: identifier)
        case .supported, .deferred:
            return .unsupportedSampleType(identifier)
        }
    }

    static func validate(context: HealthKitFHIRConversionContext) throws {
        guard !context.converter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveHealthKitFHIRError.invalidConverterApplication("name")
        }
        guard !context.converter.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveHealthKitFHIRError.invalidConverterApplication("bundleIdentifier")
        }
        guard !context.converter.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroveHealthKitFHIRError.invalidConverterApplication("version")
        }
        _ = try GroveFHIRBusinessIdentifier(system: context.graphIdentifierSystem, value: "validation")
        if let system = context.recordingDeviceIdentifierSystem {
            _ = try GroveFHIRBusinessIdentifier(system: system, value: "validation")
        }
        _ = try validateReference(
            reference: context.subject,
            field: "subject",
            expectedResourceType: "Patient"
        )
        var studyIdentities: Set<GroveFHIRTypedReferenceIdentity> = []
        for study in context.researchStudies {
            let identity = try validateReference(
                reference: study,
                field: "researchStudies",
                expectedResourceType: "ResearchStudy"
            )
            guard studyIdentities.insert(identity).inserted else {
                throw GroveHealthKitFHIRError.duplicateReference(field: "researchStudies")
            }
        }
    }

    private static func validateReference(
        reference: Reference,
        field: String,
        expectedResourceType: String
    ) throws -> GroveFHIRTypedReferenceIdentity {
        do {
            return try GroveFHIRTypedReference.validate(
                reference,
                expectedResourceType: expectedResourceType
            )
        } catch let error as GroveFHIRTypedReferenceError {
            switch error {
            case .unboundBundleUUID:
                throw GroveHealthKitFHIRError.invalidExchangeIdentity(
                    "\(field) contains a UUID URN that is not an entry in the emitted Bundle"
                )
            case .invalidReference:
                throw GroveHealthKitFHIRError.invalidReference(
                    field: field,
                    expectedResourceType: expectedResourceType
                )
            }
        } catch {
            throw GroveHealthKitFHIRError.invalidReference(
                field: field,
                expectedResourceType: expectedResourceType
            )
        }
    }

    private static func derivedIdentity(
        context: HealthKitFHIRConversionContext,
        sourceUUID: String,
        role: String
    ) throws -> GroveFHIRBusinessIdentifier {
        try GroveFHIRBusinessIdentifier(
            system: context.graphIdentifierSystem,
            value: "\(sourceUUID)|\(role)"
        )
    }

    private static func observation(
        for sample: HKSample,
        binding: HealthKitFHIRBinding,
        context: HealthKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let contract = binding.contract
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(
                    code: contract.code.code.asFHIRStringPrimitive(),
                    display: measurementDisplay(contract).asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: contract.code.system))
                ),
                Coding(
                    code: sample.sampleType.identifier.asFHIRStringPrimitive(),
                    display: HealthKitFHIRCatalog.entry(for: sample)?.title.asFHIRStringPrimitive(),
                    system: GroveFHIRCanonical.healthKitSourceType
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: contract.profiles)
        observation.subject = context.subject
        observation.issued = FHIRPrimitive(try Instant(date: context.conversionInstant))
        observation.category = category(for: contract.id).map { [CodeableConcept(coding: [$0])] }
        observation.method = contract.method.map { method in
            CodeableConcept(coding: [Coding(
                code: method.code.asFHIRStringPrimitive(),
                display: method.display.asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.aggregationMethodCodeSystem
            )])
        }
        try applyEffective(to: &observation, sample: sample, contract: contract)
        try applyResult(to: &observation, sample: sample, binding: binding, contract: contract)
        try applyHeartRateMotionContext(to: &observation, sample: sample)
        try applyInsulinDeliveryReason(to: &observation, sample: sample)
        try applyMenstrualCycleStart(to: &observation, sample: sample, contract: contract)
        applyObservationGraphContext(
            to: &observation,
            sample: sample,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        return observation
    }

    private static func applyResult(
        to observation: inout Observation,
        sample: HKSample,
        binding: HealthKitFHIRBinding,
        contract: HealthKitFHIRObservationContract
    ) throws {
        if case .bloodPressure = binding {
            guard let correlation = sample as? HKCorrelation else {
                throw GroveHealthKitFHIRError.invalidValue
            }
            observation.component = try bloodPressureComponents(correlation, contract: contract)
            return
        }
        observation.value = try result(for: binding, sample: sample, contract: contract)
    }

    // The closed binding dispatch is intentionally spelled as a single exhaustive switch.
    // swiftlint:disable:next cyclomatic_complexity
    private static func result(
        for binding: HealthKitFHIRBinding,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Observation.ValueX {
        switch binding {
        case let .quantity(_, unit):
            .quantity(try fhirQuantity(
                value: try quantitySample(sample).quantity.doubleValue(for: unit),
                contract: quantityContract(contract)
            ))
        case .percent:
            .quantity(try fhirQuantity(
                value: try quantitySample(sample).quantity.doubleValue(for: .percent()) * 100,
                contract: quantityContract(contract)
            ))
        case .sessionRate:
            .quantity(try sessionRateValue(sample, contract: contract))
        case .sessionDuration:
            .quantity(try sessionDurationValue(sample, contract: contract))
        case .assessmentScore:
            .quantity(try assessmentScoreValue(sample, contract: contract))
        case .sleepStage:
            .codeableConcept(try sleepStageValue(sample, contract: contract))
        case .severity:
            .codeableConcept(try severityValue(sample, contract: contract))
        case .presence:
            .codeableConcept(try presenceValue(sample, contract: contract))
        case let .categoryValue(_, absorption):
            .codeableConcept(try absorbedCategoryValue(sample, absorption: absorption, contract: contract))
        case .fixedCode:
            .codeableConcept(try fixedCodeValue(sample, contract: contract))
        case .sexualActivity:
            .codeableConcept(try sexualActivityValue(sample, contract: contract))
        case .bloodPressure:
            throw GroveHealthKitFHIRError.invalidValue
        }
    }

    private static func sessionRateValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        let quantitySample = try quantitySample(sample)
        let hours = quantitySample.endDate.timeIntervalSince(quantitySample.startDate) / 3_600
        return try fhirQuantity(
            value: quantitySample.quantity.doubleValue(for: .count()) / hours,
            contract: quantityContract(contract)
        )
    }

    private static func assessmentScoreValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> Quantity {
        guard let assessment = sample as? HKScoredAssessment else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return try fhirQuantity(value: Double(assessment.score), contract: quantityContract(contract))
    }

    private static func sleepStageValue(
        _ sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws -> CodeableConcept {
        let stage = try sleepStage(try categorySample(sample).value, sampleType: sample.sampleType.identifier)
        return CodeableConcept(coding: [
            Coding(
                code: stage.sharedCode.asFHIRStringPrimitive(),
                display: stage.sharedDisplay.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: try resultCodeSystem(contract)))
            ),
            Coding(
                code: stage.sourceCode.asFHIRStringPrimitive(),
                display: stage.sourceDisplay.asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.healthKitSleepAnalysis
            )
        ])
    }

    static func quantitySample(_ sample: HKSample) throws -> HKQuantitySample {
        guard let quantitySample = sample as? HKQuantitySample else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return quantitySample
    }

    static func categorySample(_ sample: HKSample) throws -> HKCategorySample {
        guard let categorySample = sample as? HKCategorySample else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return categorySample
    }

    static func quantityContract(
        _ contract: HealthKitFHIRObservationContract
    ) throws -> GroveFHIRQuantityContract {
        guard let quantity = contract.quantity else {
            throw GroveHealthKitFHIRError.invalidValue
        }
        return quantity
    }

    static func resultCodeSystem(_ contract: HealthKitFHIRObservationContract) throws -> String {
        guard let resultCodeSystem = contract.resultCodeSystem else {
            throw GroveHealthKitFHIRError.missingNormativeCode(contract.id)
        }
        return resultCodeSystem
    }

    private static func applyObservationGraphContext(
        to observation: inout Observation,
        sample: HKSample,
        context: HealthKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) {
        applyGraphContext(
            to: &observation,
            context: context,
            graphContext: HealthKitECGGraphContext(
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            ),
            wasUserEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
        )
    }

    private static func applyEffective(
        to observation: inout Observation,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws {
        let timeZone = try healthKitTimeZone(for: sample)
        switch contract.effective {
        case .dateTime:
            observation.effective = .dateTime(FHIRPrimitive(try HealthKitFHIRMobileCanonicalization.effectiveDateTime(
                sample.startDate,
                timeZone: timeZone
            )))
        case .period:
            guard sample.endDate > sample.startDate else {
                throw GroveHealthKitFHIRError.invalidEffectivePeriod(sampleType: sample.sampleType.identifier)
            }
            observation.effective = .period(Period(
                end: FHIRPrimitive(try HealthKitFHIRMobileCanonicalization.effectiveDateTime(
                    sample.endDate,
                    timeZone: timeZone
                )),
                start: FHIRPrimitive(try HealthKitFHIRMobileCanonicalization.effectiveDateTime(
                    sample.startDate,
                    timeZone: timeZone
                ))
            ))
        }
        if sample.metadata?[HKMetadataKeyTimeZone] != nil {
            attachTimeZoneExtension(to: &observation, identifier: timeZone.identifier)
        }
    }

    private static func attachTimeZoneExtension(to observation: inout Observation, identifier: String) {
        let timeZoneExtension = Extension(
            url: GroveFHIRCanonical.timezone,
            value: .code(identifier.asFHIRStringPrimitive())
        )
        switch observation.effective {
        case .dateTime(var dateTime):
            dateTime.append(extension: timeZoneExtension, behaviour: .replace)
            observation.effective = .dateTime(dateTime)
        case .period(var period):
            if var start = period.start {
                start.append(extension: timeZoneExtension, behaviour: .replace)
                period.start = start
            }
            if var end = period.end {
                end.append(extension: timeZoneExtension, behaviour: .replace)
                period.end = end
            }
            observation.effective = .period(period)
        default:
            break
        }
    }

    static func fhirQuantity(
        value: Double,
        contract: GroveFHIRQuantityContract
    ) throws -> Quantity {
        Quantity(
            code: contract.code.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: contract.system)),
            unit: contract.unit.asFHIRStringPrimitive(),
            value: try HealthKitFHIRMobileCanonicalization.scalarDecimal(value)
        )
    }

    private static func bloodPressureComponents(
        _ correlation: HKCorrelation,
        contract: HealthKitFHIRObservationContract
    ) throws -> [ObservationComponent] {
        try contract.components.map { component in
            let healthKitIdentifier: HKQuantityTypeIdentifier = component.id == "systolic"
                ? .bloodPressureSystolic
                : .bloodPressureDiastolic
            guard let sample = correlation.objects
                .compactMap({ $0 as? HKQuantitySample })
                .first(where: { $0.quantityType.identifier == healthKitIdentifier.rawValue }) else {
                throw GroveHealthKitFHIRError.missingRequiredComponent(
                    sampleType: correlation.correlationType.identifier,
                    component: component.id
                )
            }
            guard let componentQuantity = component.quantity else {
                throw GroveHealthKitFHIRError.invalidValue
            }
            return ObservationComponent(
                code: CodeableConcept(coding: [Coding(
                    code: component.code.asFHIRStringPrimitive(),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
                )]),
                value: .quantity(try fhirQuantity(
                    value: sample.quantity.doubleValue(for: .millimeterOfMercury()),
                    contract: componentQuantity
                ))
            )
        }
    }

    private static func sleepStage(
        _ value: Int,
        sampleType: String
    ) throws -> HealthKitSleepStage {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            HealthKitSleepStage(
                sharedCode: "in-bed",
                sharedDisplay: "In bed",
                sourceCode: "inBed",
                sourceDisplay: "In bed"
            )
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            HealthKitSleepStage(
                sharedCode: "asleep-unspecified",
                sharedDisplay: "Asleep, unspecified stage",
                sourceCode: "asleepUnspecified",
                sourceDisplay: "Asleep, unspecified"
            )
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            HealthKitSleepStage(
                sharedCode: "awake",
                sharedDisplay: "Awake",
                sourceCode: "awake",
                sourceDisplay: "Awake"
            )
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            HealthKitSleepStage(
                sharedCode: "light",
                sharedDisplay: "Light sleep",
                sourceCode: "asleepCore",
                sourceDisplay: "Asleep, core"
            )
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            HealthKitSleepStage(
                sharedCode: "deep",
                sharedDisplay: "Deep sleep",
                sourceCode: "asleepDeep",
                sourceDisplay: "Asleep, deep"
            )
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            HealthKitSleepStage(
                sharedCode: "rem",
                sharedDisplay: "REM sleep",
                sourceCode: "asleepREM",
                sourceDisplay: "Asleep, REM"
            )
        default:
            throw GroveHealthKitFHIRError.unsupportedSampleValue(
                sampleType: sampleType,
                value: value
            )
        }
    }

    private static func measurementDisplay(_ contract: HealthKitFHIRObservationContract) -> String {
        contract.code.display ?? measurementDisplays[contract.id, default: contract.id]
    }

    private static func category(for id: String) -> Coding? {
        let code: (String, String)? = switch id {
        case "heart-rate", "body-weight", "blood-pressure", "body-temperature",
             "respiratory-rate", "oxygen-saturation", "body-height", "body-mass-index":
            ("vital-signs", "Vital Signs")
        case "step-count", "distance", "active-energy", "sleep-stage":
            ("activity", "Activity")
        default:
            nil
        }
        return code.map { code, display in
            Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: observationCategory
            )
        }
    }

    private static func applyHeartRateMotionContext(
        to observation: inout Observation,
        sample: HKSample
    ) throws {
        guard sample.sampleType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue,
              let raw = sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber else {
            return
        }
        let coding: Coding = switch raw.intValue {
        case 0:
            Coding(code: "not-set", display: "Not Set", system: GroveFHIRCanonical.healthKitHeartRateMotionContext)
        case 1:
            Coding(code: "sedentary", display: "Sedentary", system: GroveFHIRCanonical.healthKitHeartRateMotionContext)
        case 2:
            Coding(code: "active", display: "Active", system: GroveFHIRCanonical.healthKitHeartRateMotionContext)
        default:
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyHeartRateMotionContext,
                value: raw.stringValue
            )
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: HKMetadataKeyHeartRateMotionContext.asFHIRStringPrimitive(),
                display: "Heart Rate Motion Context".asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.healthKitMetadataKey
            )]),
            value: .codeableConcept(CodeableConcept(coding: [coding]))
        )
        observation.component = (observation.component ?? []) + [component]
    }

    private static func applyInsulinDeliveryReason(
        to observation: inout Observation,
        sample: HKSample
    ) throws {
        guard sample.sampleType.identifier == HKQuantityTypeIdentifier.insulinDelivery.rawValue else {
            return
        }
        guard let raw = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? NSNumber else {
            throw GroveHealthKitFHIRError.missingRequiredMetadata(
                sampleType: sample.sampleType.identifier,
                key: HKMetadataKeyInsulinDeliveryReason
            )
        }
        let coding: Coding = switch raw.intValue {
        case HKInsulinDeliveryReason.basal.rawValue:
            Coding(code: "basal", display: "Basal", system: GroveFHIRCanonical.healthKitInsulinDeliveryReason)
        case HKInsulinDeliveryReason.bolus.rawValue:
            Coding(code: "bolus", display: "Bolus", system: GroveFHIRCanonical.healthKitInsulinDeliveryReason)
        default:
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyInsulinDeliveryReason,
                value: raw.stringValue
            )
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: HKMetadataKeyInsulinDeliveryReason.asFHIRStringPrimitive(),
                display: "Insulin Delivery Reason".asFHIRStringPrimitive(),
                system: GroveFHIRCanonical.healthKitMetadataKey
            )]),
            value: .codeableConcept(CodeableConcept(coding: [coding]))
        )
        observation.component = (observation.component ?? []) + [component]
    }

    private static func applyMenstrualCycleStart(
        to observation: inout Observation,
        sample: HKSample,
        contract: HealthKitFHIRObservationContract
    ) throws {
        guard sample.sampleType.identifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue else {
            return
        }
        let component = try menstrualCycleStartComponent(
            metadata: sample.metadata ?? [:],
            sampleType: sample.sampleType.identifier,
            contract: contract
        )
        observation.component = (observation.component ?? []) + [component]
    }

    /// HealthKit makes cycle-start metadata mandatory on every menstrual-flow sample, so its absence fails closed.
    ///
    /// HealthKit rejects a sample without the key at construction, so only this guard can prove the
    /// converter never silently drops it.
    static func menstrualCycleStartComponent(
        metadata: [String: Any],
        sampleType: String,
        contract: HealthKitFHIRObservationContract
    ) throws -> ObservationComponent {
        guard let contractComponent = contract.components.first(where: { $0.id == "cycleStart" }),
              let resultCodeSystem = contractComponent.resultCodeSystem else {
            throw GroveHealthKitFHIRError.missingRequiredComponent(
                sampleType: sampleType,
                component: "cycleStart"
            )
        }
        let cycleStart: Bool
        switch metadata[HKMetadataKeyMenstrualCycleStart] {
        case nil:
            throw GroveHealthKitFHIRError.missingRequiredMetadata(
                sampleType: sampleType,
                key: HKMetadataKeyMenstrualCycleStart
            )
        case let value as Bool:
            cycleStart = value
        case let other?:
            throw GroveHealthKitFHIRError.unsupportedMetadataValue(
                key: HKMetadataKeyMenstrualCycleStart,
                value: String(describing: other)
            )
        }
        let code = cycleStart ? "cycle-start" : "not-cycle-start"
        guard let resultCode = contractComponent.resultCodes.first(where: { $0.code == code }) else {
            throw GroveHealthKitFHIRError.missingNormativeCode(contract.id)
        }
        return ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: contractComponent.code.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: contractComponent.system))
            )]),
            value: .codeableConcept(CodeableConcept(coding: [Coding(
                code: resultCode.code.asFHIRStringPrimitive(),
                display: resultCode.display.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: resultCodeSystem))
            )]))
        )
    }


    static func applyManualRecordingMethod(to observation: inout Observation) {
        observation.append(
            extension: Extension(
                url: GroveFHIRCanonical.recordingMethod,
                value: .coding(Coding(
                    code: "manual-entry",
                    display: "Manual entry",
                    system: GroveFHIRCanonical.recordingMethodCodeSystem
                ))
            ),
            behaviour: .replace
        )
    }

    private static func applicationDevice(_ application: HealthKitFHIRApplication) -> Device {
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveApplicationDevice])
        device.identifier = [Identifier(
            system: GroveFHIRCanonical.appleBundleIdentifier,
            value: application.bundleIdentifier.asFHIRStringPrimitive()
        )]
        device.deviceName = [DeviceDeviceName(
            name: application.name.asFHIRStringPrimitive(),
            type: FHIRPrimitive(.userFriendlyName)
        )]
        device.version = [DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: "531975",
                display: "MDC_ID_PROD_SPEC_SW",
                system: mdc
            )]),
            value: application.version.asFHIRStringPrimitive()
        )]
        return device
    }

    private static func recordingDevice(
        for healthKitDevice: HKDevice?,
        context: HealthKitFHIRConversionContext,
        sourceUUID: String
    ) throws -> IdentifiedDevice? {
        guard let healthKitDevice else {
            return nil
        }
        var device = Device()
        device.meta = Meta(profile: [GroveFHIRProfile.groveRecordingDevice])
        if let name = healthKitDevice.name?.nonEmpty {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.manufacturer = healthKitDevice.manufacturer?.nonEmpty?.asFHIRStringPrimitive()
        device.modelNumber = healthKitDevice.model?.nonEmpty?.asFHIRStringPrimitive()
        var versions: [DeviceVersion] = []
        versions.appendVersion(healthKitDevice.hardwareVersion, code: "531974", display: "MDC_ID_PROD_SPEC_HW")
        versions.appendVersion(healthKitDevice.firmwareVersion, code: "531976", display: "MDC_ID_PROD_SPEC_FW")
        versions.appendVersion(healthKitDevice.softwareVersion, code: "531975", display: "MDC_ID_PROD_SPEC_SW")
        device.version = versions.isEmpty ? nil : versions

        let localIdentity: GroveFHIRBusinessIdentifier?
        if let system = context.recordingDeviceIdentifierSystem,
           let localIdentifier = healthKitDevice.localIdentifier?.nonEmpty {
            let identifier = try GroveFHIRBusinessIdentifier(system: system, value: localIdentifier)
            device.identifier = [identifier.fhirIdentifier]
            localIdentity = identifier
        } else {
            localIdentity = nil
        }
        if context.udiDisclosurePolicy == .authorizedUDI,
           let udi = healthKitDevice.udiDeviceIdentifier?.nonEmpty {
            device.udiCarrier = [DeviceUdiCarrier(deviceIdentifier: udi.asFHIRStringPrimitive())]
        }
        // Published precedence: an authorized local identifier, then the deduplicating digest a
        // device-identity scope unlocks, then the per-sample identity that asserts no shared
        // device at all.
        let identity: GroveFHIRBusinessIdentifier
        if let localIdentity {
            identity = localIdentity
        } else if let value = deduplicatingIdentity(for: healthKitDevice, context: context) {
            identity = try GroveFHIRBusinessIdentifier(
                system: context.graphIdentifierSystem,
                value: value
            )
        } else {
            identity = try derivedIdentity(
                context: context,
                sourceUUID: sourceUUID,
                role: "recording-device"
            )
        }
        return IdentifiedDevice(resource: device, identity: identity)
    }

    /// The published recording-device digest, or `nil` when the deployment has not opted in or
    /// the platform states too little to identify a recorder.
    private static func deduplicatingIdentity(
        for healthKitDevice: HKDevice,
        context: HealthKitFHIRConversionContext
    ) -> String? {
        guard let scope = context.deviceIdentityScope else {
            return nil
        }
        return GroveFHIRRecordingDeviceIdentity.value(
            scope: scope,
            adapter: "healthkit",
            recorder: GroveFHIRRecordingDeviceIdentity.Recorder(
                manufacturer: healthKitDevice.manufacturer?.nonEmpty,
                model: healthKitDevice.model?.nonEmpty,
                hardwareVersion: healthKitDevice.hardwareVersion?.nonEmpty,
                firmwareVersion: healthKitDevice.firmwareVersion?.nonEmpty,
                softwareVersion: healthKitDevice.softwareVersion?.nonEmpty,
                localIdentifier: healthKitDevice.localIdentifier?.nonEmpty
            )
        )
    }

    private static func sourceAuthor(
        for revision: HKSourceRevision,
        classification: HealthKitFHIRSourceActor,
        context: HealthKitFHIRConversionContext,
        sourceUUID: String
    ) throws -> IdentifiedDevice? {
        switch classification {
        case .omit:
            return nil
        case .application:
            return try sourceApplicationAuthor(for: revision)
        case .device(let discloseIdentifier):
            return try sourceDeviceAuthor(
                for: revision,
                discloseIdentifier: discloseIdentifier,
                context: context,
                sourceUUID: sourceUUID
            )
        }
    }

    private static func sourceApplicationAuthor(
        for revision: HKSourceRevision
    ) throws -> IdentifiedDevice? {
        guard let name = revision.source.name.nonEmpty,
              let bundleIdentifier = revision.source.bundleIdentifier.nonEmpty else {
            return nil
        }
        var device = applicationDevice(HealthKitFHIRApplication(
            name: name,
            bundleIdentifier: bundleIdentifier,
            version: revision.version?.nonEmpty ?? "unknown"
        ))
        if revision.version?.nonEmpty == nil {
            device.version = nil
        }
        return IdentifiedDevice(
            resource: device,
            identity: try GroveFHIRBusinessIdentifier(
                system: GroveFHIRCanonical.appleBundleIdentifierSystem,
                value: bundleIdentifier
            )
        )
    }

    private static func sourceDeviceAuthor(
        for revision: HKSourceRevision,
        discloseIdentifier: Bool,
        context: HealthKitFHIRConversionContext,
        sourceUUID: String
    ) throws -> IdentifiedDevice? {
        var device = Device()
        if let name = revision.source.name.nonEmpty {
            device.deviceName = [DeviceDeviceName(
                name: name.asFHIRStringPrimitive(),
                type: FHIRPrimitive(.userFriendlyName)
            )]
        }
        device.modelNumber = revision.productType?.nonEmpty?.asFHIRStringPrimitive()
        let identity: GroveFHIRBusinessIdentifier
        if discloseIdentifier, let identifier = revision.source.bundleIdentifier.nonEmpty {
            identity = try GroveFHIRBusinessIdentifier(
                system: GroveFHIRCanonical.healthKitSourceDeviceIdentifierSystem,
                value: identifier
            )
            device.identifier = [identity.fhirIdentifier]
        } else {
            identity = try derivedIdentity(
                context: context,
                sourceUUID: sourceUUID,
                role: "source-author-device"
            )
        }
        guard device.deviceName != nil || device.identifier != nil || device.modelNumber != nil else {
            return nil
        }
        return IdentifiedDevice(resource: device, identity: identity)
    }

    private static func provenance(
        sourceIdentifier: Identifier,
        targetURL: String,
        converterURL: String,
        sourceAuthorURL: String?,
        recordedAt: Date
    ) throws -> Provenance {
        let author = sourceAuthorURL.map { url in
            ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "author",
                    display: "Author",
                    system: participantType
                )]),
                who: Reference(reference: url.asFHIRStringPrimitive())
            )
        }
        var entity = ProvenanceEntity(
            role: FHIRPrimitive(.source),
            what: Reference(identifier: sourceIdentifier)
        )
        entity.agent = author.map { [$0] }
        return Provenance(
            activity: CodeableConcept(coding: [Coding(
                code: "transform",
                display: "Transform/Translate Record Lifecycle Event",
                system: lifecycleEvent
            )]),
            agent: [ProvenanceAgent(
                type: CodeableConcept(coding: [Coding(
                    code: "assembler",
                    display: "Assembler",
                    system: participantType
                )]),
                who: Reference(reference: converterURL.asFHIRStringPrimitive())
            )],
            entity: [entity],
            meta: Meta(profile: [GroveFHIRHealthKitCatalog.conversionProvenanceProfile]),
            occurred: .dateTime(FHIRPrimitive(try DateTime(date: recordedAt))),
            recorded: FHIRPrimitive(try Instant(date: recordedAt)),
            target: [Reference(reference: targetURL.asFHIRStringPrimitive())]
        )
    }
}


extension Array where Element == DeviceVersion {
    fileprivate mutating func appendVersion(_ value: String?, code: String, display: String) {
        guard let value = value?.nonEmpty else {
            return
        }
        append(DeviceVersion(
            type: CodeableConcept(coding: [Coding(
                code: code.asFHIRStringPrimitive(),
                display: display.asFHIRStringPrimitive(),
                system: "urn:iso:std:iso:11073:10101"
            )]),
            value: value.asFHIRStringPrimitive()
        ))
    }
}


extension String {
    fileprivate var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

#endif
