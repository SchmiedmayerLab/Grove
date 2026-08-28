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
import Foundation
public import GroveFHIRContract
import GroveHealthKit
public import HealthKit
public import ModelsR4


/// Profile-aware HealthKit-to-FHIR R4 facade.
///
/// The converter consumes already-fetched `HKSample` values. It does not query HealthKit,
/// authorize data access, synchronize anchors, persist resources, or upload anything.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitConverter: Sendable {
    public init() {}

    /// Converts one sample only when the closed catalog admits its exact published contract.
    public func convert(
        _ sample: HKSample,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversion {
        do {
            return try Self.convertSample(sample, context: context)
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    /// Converts one sample for a subject, deriving the rest of the context from the running app.
    ///
    /// Equivalent to building a ``HealthKitConversionContext`` with only its subject. Use the
    /// context form to set a study reference, a disclosure policy, or a fixed conversion instant.
    ///
    /// ```swift
    /// let conversion = try HealthKitConverter().convert(sample, for: patient)
    /// ```
    public func convert(
        _ sample: HKSample,
        for subject: Reference
    ) throws(HealthKitConversionError) -> HealthKitConversion {
        try convert(sample, context: HealthKitConversionContext(subject: subject))
    }

    /// Converts every input for a subject, deriving the rest of the context from the running app.
    public func convert<S: Sequence>(
        _ samples: S,
        for subject: Reference
    ) -> HealthKitBatchResult where S.Element == HKSample {
        convert(samples, context: HealthKitConversionContext(subject: subject))
    }

    /// Converts every input and returns a typed failure for every record that was not emitted.
    public func convert<S: Sequence>(
        _ samples: S,
        context: HealthKitConversionContext
    ) -> HealthKitBatchResult where S.Element == HKSample {
        var conversions: [HealthKitConversion] = []
        var failures: [HealthKitRecordFailure] = []
        for sample in samples {
            do {
                conversions.append(try convert(sample, context: context))
            } catch {
                failures.append(HealthKitRecordFailure(
                    sourceUUID: sample.uuid,
                    sourceTypeIdentifier: sample.sampleType.identifier,
                    reason: error
                ))
            }
        }
        return HealthKitBatchResult(conversions: conversions, failures: failures)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    struct IdentifiedDevice {
        var resource: Device
        let identity: BusinessIdentifier
    }

    /// The identity, device, and provenance surroundings every emitted graph shares.
    ///
    /// Resolved from the source sample before the record's own resource exists, so an Observation
    /// graph and a recording-document graph agree on identity by construction rather than through
    /// two implementations that have to be kept in step.
    struct GraphEnvelope {
        let sourceUUID: String
        let primary: BusinessIdentifier
        let converter: BusinessIdentifier
        let bundle: BusinessIdentifier
        let provenance: BusinessIdentifier
        let converterApplication: Device
        let recordingDevice: IdentifiedDevice?
        let sourceAuthor: IdentifiedDevice?
        let sourceAuthorUsesConverter: Bool
        let primaryURL: String
        let converterURL: String
        let recordingDeviceURL: String?
        let sourceAuthorURL: String?
    }

    private struct HealthKitSleepStage {
        let sharedCode: String
        let sharedDisplay: String
        let sourceCode: String
        let sourceDisplay: String
    }

    static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
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
        context: HealthKitConversionContext
    ) throws -> HealthKitConversion {
        try validate(context: context)
        if sample is HKElectrocardiogram {
            throw HealthKitConversionError.missingECGEvidence
        }
        guard let binding = HealthKitCatalog.binding(for: sample) else {
            throw unconvertibleSampleError(forSourceTypeIdentifier: sample.sampleType.identifier)
        }
        let workoutMembers: ((String) throws -> [(identity: BusinessIdentifier, observation: Observation)])?
        if let workout = sample as? HKWorkout {
            workoutMembers = { sourceUUID in
                try workoutSegments(workout, context: context, sourceUUID: sourceUUID)
            }
        } else {
            workoutMembers = nil
        }
        return try assembleGraph(
            for: sample,
            context: context,
            memberBuilder: workoutMembers
        ) { recordingDeviceURL, converterURL in
            try observation(
                for: sample,
                binding: binding,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        }
    }

    // Resolution is intentionally one atomic, reviewable identity transaction.
    // swiftlint:disable:next function_body_length
    static func graphEnvelope(
        for sample: HKSample,
        context: HealthKitConversionContext
    ) throws -> GraphEnvelope {
        let sourceUUID = sample.uuid.uuidString.lowercased()
        let primaryIdentity = try BusinessIdentifier(
            system: Canonicals.healthKitObjectIdentifierSystem,
            value: sourceUUID
        )
        let converterIdentity = try BusinessIdentifier(
            system: Canonicals.appleBundleIdentifierSystem,
            value: context.converter.bundleIdentifier
        )

        var converterApplication = applicationDevice(context.converter)
        converterApplication.id = context.repositoryIDs.converterApplication?.primitive
        var recordingDevice = try Self.recordingDevice(
            for: sample.device,
            context: context,
            sourceUUID: sourceUUID
        )
        recordingDevice?.resource.id = context.repositoryIDs.recordingDevice?.primitive
        var sourceAuthor = try Self.sourceAuthor(
            for: sample.sourceRevision,
            classification: context.sourceActor,
            context: context,
            sourceUUID: sourceUUID
        )
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

        let sourceAuthorUsesConverter = sourceAuthor?.identity == converterIdentity
        if sourceAuthorUsesConverter {
            if let sourceID = context.repositoryIDs.sourceAuthor,
               let converterID = context.repositoryIDs.converterApplication,
               sourceID != converterID {
                throw HealthKitConversionError.invalidExchangeIdentity(
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

        return GraphEnvelope(
            sourceUUID: sourceUUID,
            primary: primaryIdentity,
            converter: converterIdentity,
            bundle: try derivedIdentity(context: context, sourceUUID: sourceUUID, role: "exchange-bundle"),
            provenance: try derivedIdentity(context: context, sourceUUID: sourceUUID, role: "conversion-provenance"),
            converterApplication: converterApplication,
            recordingDevice: recordingDevice,
            sourceAuthor: sourceAuthor,
            sourceAuthorUsesConverter: sourceAuthorUsesConverter,
            primaryURL: try ExchangeIdentity.fullURL(for: primaryIdentity),
            converterURL: try ExchangeIdentity.fullURL(for: converterIdentity),
            recordingDeviceURL: try recordingDevice.map { try ExchangeIdentity.fullURL(for: $0.identity) },
            sourceAuthorURL: try sourceAuthor.map { try ExchangeIdentity.fullURL(for: $0.identity) }
        )
    }

    /// The exchange Bundle for one record: its own resource first, then everything the graph needs
    /// to stand on its own.
    static func exchangeBundle(
        envelope: GraphEnvelope,
        primary: ResourceProxy,
        members: [(identity: BusinessIdentifier, resource: ResourceProxy)] = [],
        provenance: Provenance,
        context: HealthKitConversionContext
    ) throws -> ModelsR4.Bundle {
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
            identifier: envelope.converter,
            resource: ResourceProxy(with: envelope.converterApplication)
        ))
        if let sourceAuthor = envelope.sourceAuthor, !envelope.sourceAuthorUsesConverter {
            entries.append(try ExchangeIdentity.entry(
                identifier: sourceAuthor.identity,
                resource: ResourceProxy(with: sourceAuthor.resource)
            ))
        }
        entries.append(try ExchangeIdentity.entry(
            identifier: envelope.provenance,
            resource: ResourceProxy(with: provenance)
        ))
        try ExchangeIdentity.validate(entries: entries)

        var bundle = Bundle(
            entry: entries,
            identifier: envelope.bundle.fhirIdentifier,
            meta: Meta(profile: [Profile.groveMobileExchangeBundle]),
            timestamp: FHIRPrimitive(try Instant(date: context.conversionInstant)),
            type: FHIRPrimitive(.collection)
        )
        bundle.id = context.repositoryIDs.bundle?.primitive
        return bundle
    }

    static func assembleGraph(
        for sample: HKSample,
        context: HealthKitConversionContext,
        memberBuilder: ((_ sourceUUID: String) throws -> [(identity: BusinessIdentifier, observation: Observation)])? = nil,
        observationBuilder: (_ recordingDeviceURL: String?, _ converterURL: String) throws -> Observation
    ) throws -> HealthKitConversion {
        let envelope = try graphEnvelope(for: sample, context: context)
        var observation = try observationBuilder(envelope.recordingDeviceURL, envelope.converterURL)
        observation.id = context.repositoryIDs.observation?.primitive
        observation.identifier = [envelope.primary.fhirIdentifier]
        try Self.applySyncIdentity(of: sample, to: &observation)
        let retained = Self.retainedMetadataComponents(of: sample, policy: context.linkableMetadataPolicy)
        if !retained.isEmpty {
            observation.component = (observation.component ?? []) + retained
        }

        var provenance = try Self.provenance(
            sourceIdentifier: envelope.primary.fhirIdentifier,
            targetURL: envelope.primaryURL,
            converterURL: envelope.converterURL,
            sourceAuthorURL: envelope.sourceAuthorURL,
            recordedAt: context.conversionInstant
        )
        provenance.id = context.repositoryIDs.provenance?.primitive

        // Members are built before the session entry so the session can reference them: a segment
        // that is carried but unreferenced would be an orphan in the graph.
        let members = try memberBuilder?(envelope.sourceUUID) ?? []
        if !members.isEmpty {
            observation.hasMember = try members.map { member in
                Reference(reference: FHIRPrimitive(FHIRString(
                    stringLiteral: try ExchangeIdentity.fullURL(for: member.identity)
                )))
            }
        }

        return HealthKitConversion(
            sourceIdentifier: envelope.primary.fhirIdentifier,
            graphIdentifiers: HealthKitGraphIdentifiers(
                bundle: envelope.bundle,
                observation: envelope.primary,
                recordingDevice: envelope.recordingDevice?.identity,
                converterApplication: envelope.converter,
                sourceAuthor: envelope.sourceAuthor?.identity,
                provenance: envelope.provenance
            ),
            observation: observation,
            recordingDevice: envelope.recordingDevice?.resource,
            converterApplication: envelope.converterApplication,
            sourceAuthor: envelope.sourceAuthor?.resource,
            provenance: provenance,
            bundle: try exchangeBundle(
                envelope: envelope,
                primary: ResourceProxy(with: observation),
                members: members.map { ($0.identity, ResourceProxy(with: $0.observation)) },
                provenance: provenance,
                context: context
            )
        )
    }

    /// The catalog-driven reason a sample without a binding fails closed.
    static func unconvertibleSampleError(
        forSourceTypeIdentifier identifier: String
    ) -> HealthKitConversionError {
        guard let entry = HealthKitCatalog.entry(forSourceTypeIdentifier: identifier) else {
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
        case .supported:
            return .unsupportedSampleType(identifier)
        }
    }

    static func derivedIdentity(
        context: HealthKitConversionContext,
        sourceUUID: String,
        role: String
    ) throws -> BusinessIdentifier {
        try BusinessIdentifier(
            system: try context.resolvedGraphIdentifierSystem,
            value: "\(sourceUUID)|\(role)"
        )
    }

    /// Adds the writer's logical identity for the sample, when it declares one.
    ///
    /// HealthKit replaces a sample when a writer saves one carrying the same sync identifier and a
    /// higher sync version, and the replacement is a new object with a new UUID. The object
    /// identifier alone therefore counts a revised measurement twice; the sync identifier names the
    /// measurement across those revisions and the version orders them.
    private static func applySyncIdentity(
        of sample: HKSample,
        to observation: inout Observation
    ) throws {
        guard let syncIdentifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
              !syncIdentifier.isEmpty else {
            return
        }
        // A sync identifier is unique only within the app that wrote it, so the writer is part of
        // the identity. Without it two apps that both chose "weighin-2026-08-19" would look like
        // one measurement, and a receiver applying the supersession rule would drop one of them.
        let writer = sample.sourceRevision.source.bundleIdentifier
        guard !writer.isEmpty else {
            // Nothing names the writer, so the identifier cannot be scoped to one. The sample is
            // still convertible; it just carries the object identifier as its only identity,
            // exactly as a sample that declares no sync identity does.
            return
        }
        guard !writer.contains("|"), !syncIdentifier.contains("|") else {
            throw HealthKitConversionError.invalidMetadataValue(key: HKMetadataKeySyncIdentifier)
        }
        let identity = try BusinessIdentifier(
            system: Canonicals.writerRecordIdentifierSystem,
            value: "v1:\(writer)|\(syncIdentifier)"
        )
        observation.identifier = (observation.identifier ?? []) + [identity.fhirIdentifier]

        // A writer that sets a sync identifier without a version is at version zero, which is what
        // HealthKit compares the next save against, so it is stated rather than left out. A value
        // of the wrong type is a defect in the writer's metadata, not a version zero.
        let version: String
        switch sample.metadata?[HKMetadataKeySyncVersion] {
        case nil:
            version = "0"
        case let number as NSNumber:
            version = number.stringValue
        default:
            throw HealthKitConversionError.invalidMetadataValue(key: HKMetadataKeySyncVersion)
        }
        observation.extension = (observation.extension ?? []) + [
            Extension(
                url: Canonicals.writerRecordVersion,
                value: .string(version.asFHIRStringPrimitive())
            )
        ]
    }

    private static func observation(
        for sample: HKSample,
        binding: HealthKitFHIRBinding,
        context: HealthKitConversionContext,
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
                    display: HealthKitCatalog.entry(for: sample)?.title.asFHIRStringPrimitive(),
                    system: Canonicals.healthKitSourceType
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: contract.profiles)
        observation.subject = context.subject
        // `issued` is deliberately absent. It states when this version of the record became
        // available, and HealthKit keeps no per-object modification time to answer that; a wall
        // clock would make an unchanged sample convert differently on every run. The conversion
        // instant is recorded once, on Provenance.
        observation.category = category(for: contract.id).map { [CodeableConcept(coding: [$0])] }
        observation.method = contract.method.map { method in
            CodeableConcept(coding: [Coding(
                code: method.code.asFHIRStringPrimitive(),
                display: method.display.asFHIRStringPrimitive(),
                system: Canonicals.aggregationMethodCodeSystem
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
                throw HealthKitConversionError.invalidValue
            }
            observation.component = try bloodPressureComponents(correlation, contract: contract)
            return
        }
        // A workout's totals and a reflection's coded axes are components alongside the value, not
        // instead of it: the activity and the valence remain the Observation's own result.
        switch binding {
        case .workout:
            observation.component = try workoutComponents(try workoutSample(sample))
        case .stateOfMind:
            observation.component = try stateOfMindComponents(try stateOfMindSample(sample))
        default:
            break
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
        case let .notification(_, values):
            .codeableConcept(try notificationValue(sample, values: values, contract: contract))
        case .sexualActivity:
            .codeableConcept(try sexualActivityValue(sample, contract: contract))
        case .bloodPressure:
            throw HealthKitConversionError.invalidValue
        case .workout:
            .codeableConcept(try workoutValue(try workoutSample(sample)))
        case .stateOfMind:
            .quantity(try stateOfMindValue(try stateOfMindSample(sample)))
        }
    }

    static func workoutSample(_ sample: HKSample) throws -> HKWorkout {
        guard let workout = sample as? HKWorkout else {
            throw HealthKitConversionError.invalidValue
        }
        return workout
    }

    static func stateOfMindSample(_ sample: HKSample) throws -> HKStateOfMind {
        guard let stateOfMind = sample as? HKStateOfMind else {
            throw HealthKitConversionError.invalidValue
        }
        return stateOfMind
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
            throw HealthKitConversionError.invalidValue
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
                system: Canonicals.healthKitSleepAnalysis
            )
        ])
    }

    static func quantitySample(_ sample: HKSample) throws -> HKQuantitySample {
        guard let quantitySample = sample as? HKQuantitySample else {
            throw HealthKitConversionError.invalidValue
        }
        return quantitySample
    }

    static func categorySample(_ sample: HKSample) throws -> HKCategorySample {
        guard let categorySample = sample as? HKCategorySample else {
            throw HealthKitConversionError.invalidValue
        }
        return categorySample
    }

    static func quantityContract(
        _ contract: HealthKitFHIRObservationContract
    ) throws -> QuantityContract {
        guard let quantity = contract.quantity else {
            throw HealthKitConversionError.invalidValue
        }
        return quantity
    }

    static func resultCodeSystem(_ contract: HealthKitFHIRObservationContract) throws -> String {
        guard let resultCodeSystem = contract.resultCodeSystem else {
            throw HealthKitConversionError.missingNormativeCode(contract.id)
        }
        return resultCodeSystem
    }

    private static func applyObservationGraphContext(
        to observation: inout Observation,
        sample: HKSample,
        context: HealthKitConversionContext,
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
            observation.effective = .dateTime(FHIRPrimitive(try HealthKitMobileCanonicalization.effectiveDateTime(
                sample.startDate,
                timeZone: timeZone
            )))
        case .period:
            guard sample.endDate > sample.startDate else {
                throw HealthKitConversionError.invalidEffectivePeriod(sampleType: sample.sampleType.identifier)
            }
            observation.effective = .period(Period(
                end: FHIRPrimitive(try HealthKitMobileCanonicalization.effectiveDateTime(
                    sample.endDate,
                    timeZone: timeZone
                )),
                start: FHIRPrimitive(try HealthKitMobileCanonicalization.effectiveDateTime(
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
            url: Canonicals.timezone,
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
        contract: QuantityContract
    ) throws -> Quantity {
        Quantity(
            code: contract.code.asFHIRStringPrimitive(),
            system: FHIRPrimitive(FHIRURI(stringLiteral: contract.system)),
            unit: contract.unit.asFHIRStringPrimitive(),
            value: try HealthKitMobileCanonicalization.scalarDecimal(value)
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
                throw HealthKitConversionError.missingRequiredComponent(
                    sampleType: correlation.correlationType.identifier,
                    component: component.id
                )
            }
            guard let componentQuantity = component.quantity else {
                throw HealthKitConversionError.invalidValue
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
            throw HealthKitConversionError.unsupportedSampleValue(
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
            Coding(code: "not-set", display: "Not Set", system: Canonicals.healthKitHeartRateMotionContext)
        case 1:
            Coding(code: "sedentary", display: "Sedentary", system: Canonicals.healthKitHeartRateMotionContext)
        case 2:
            Coding(code: "active", display: "Active", system: Canonicals.healthKitHeartRateMotionContext)
        default:
            throw HealthKitConversionError.unsupportedMetadataValue(
                key: HKMetadataKeyHeartRateMotionContext,
                value: raw.stringValue
            )
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: HKMetadataKeyHeartRateMotionContext.asFHIRStringPrimitive(),
                display: "Heart Rate Motion Context".asFHIRStringPrimitive(),
                system: Canonicals.healthKitMetadataKey
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
            throw HealthKitConversionError.missingRequiredMetadata(
                sampleType: sample.sampleType.identifier,
                key: HKMetadataKeyInsulinDeliveryReason
            )
        }
        let coding: Coding = switch raw.intValue {
        case HKInsulinDeliveryReason.basal.rawValue:
            Coding(code: "basal", display: "Basal", system: Canonicals.healthKitInsulinDeliveryReason)
        case HKInsulinDeliveryReason.bolus.rawValue:
            Coding(code: "bolus", display: "Bolus", system: Canonicals.healthKitInsulinDeliveryReason)
        default:
            throw HealthKitConversionError.unsupportedMetadataValue(
                key: HKMetadataKeyInsulinDeliveryReason,
                value: raw.stringValue
            )
        }
        let component = ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: HKMetadataKeyInsulinDeliveryReason.asFHIRStringPrimitive(),
                display: "Insulin Delivery Reason".asFHIRStringPrimitive(),
                system: Canonicals.healthKitMetadataKey
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
            throw HealthKitConversionError.missingRequiredComponent(
                sampleType: sampleType,
                component: "cycleStart"
            )
        }
        let cycleStart: Bool
        switch metadata[HKMetadataKeyMenstrualCycleStart] {
        case nil:
            throw HealthKitConversionError.missingRequiredMetadata(
                sampleType: sampleType,
                key: HKMetadataKeyMenstrualCycleStart
            )
        case let value as Bool:
            cycleStart = value
        case let other?:
            throw HealthKitConversionError.unsupportedMetadataValue(
                key: HKMetadataKeyMenstrualCycleStart,
                value: String(describing: other)
            )
        }
        let code = cycleStart ? "cycle-start" : "not-cycle-start"
        guard let resultCode = contractComponent.resultCodes.first(where: { $0.code == code }) else {
            throw HealthKitConversionError.missingNormativeCode(contract.id)
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
                url: Canonicals.recordingMethod,
                value: .coding(Coding(
                    code: "manual-entry",
                    display: "Manual entry",
                    system: Canonicals.recordingMethodCodeSystem
                ))
            ),
            behaviour: .replace
        )
    }
}

#endif
