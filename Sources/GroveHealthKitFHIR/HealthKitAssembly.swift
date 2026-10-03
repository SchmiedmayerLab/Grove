//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// The HealthKit adapter's graph assembly for one producer and one HealthKit store.
///
/// It turns a sample into the outputs its catalog contract names, resolves what the sample says about
/// its writer and recording device, and hands the draft to the shared ``ExchangeGraphAssembler``.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitAssembly: Sendable {
    /// What one record's conversion needs beyond the envelope: its event, and the policies in force.
    struct Request: Sendable {
        let event: ExchangeEventIdentifier
        let instant: Date
        let converterRole: ConverterRole
        let repositoryIDs: [ExchangeGraphNode: RepositoryID]
        let options: HealthKitConversionOptions

        init(
            event: ExchangeEventIdentifier,
            instant: Date,
            converterRole: ConverterRole = .assembler,
            repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:],
            options: HealthKitConversionOptions = .default
        ) {
            self.event = event
            self.instant = instant
            self.converterRole = converterRole
            self.repositoryIDs = repositoryIDs
            self.options = options
        }

        init(context: HealthKitConversionContext) {
            self.init(
                event: context.event.event,
                instant: context.event.conversionInstant,
                converterRole: context.event.converterRole,
                repositoryIDs: context.event.repositoryIDs,
                options: context.options
            )
        }
    }

    static let adapter = ExchangeAdapterContract(
        adapterID: "healthkit",
        provenanceProfile: HealthKitContract.conversionProvenanceProfile,
        applicationDeviceProfile: HealthKitContract.applicationDeviceProfile
    ) { application in
        let type = Coding(
            code: HealthKitContract.appleBundleIdentifierTypeCode.asFHIRStringPrimitive(),
            system: HealthKitContract.appleBundleIdentifierTypeSystem
        )
        return Identifier(
            system: HealthKitContract.appleBundleIdentifierSystem,
            type: CodeableConcept(coding: [type]),
            value: application.bundleIdentifier.asFHIRStringPrimitive()
        )
    }

    let assembler: ExchangeGraphAssembler

    var envelope: ExchangeEnvelope { assembler.envelope }

    init(envelope: ExchangeEnvelope) {
        self.assembler = ExchangeGraphAssembler(envelope: envelope)
    }

    init(context: ExchangeEventContext) {
        self.init(envelope: ExchangeEnvelope(
            adapter: Self.adapter,
            identityScope: context.identityScope,
            subject: context.subject,
            repositoryScope: context.repositoryScope,
            application: context.application,
            host: context.host,
            studies: context.studies
        ))
    }

    /// Converts one sample only when the closed catalog admits its exact published contract.
    func convert(_ sample: HKSample, request: Request) throws -> HealthKitConversionSet {
        guard let type = HealthKitSourceType(sample) else {
            throw HealthKitConversionError.unregisteredSourceType(sample.sampleType.identifier)
        }
        if sample is HKElectrocardiogram {
            throw HealthKitConversionError.ecgEvidence(.evidenceRequired)
        }
        #if !os(watchOS)
        if let record = sample as? HKClinicalRecord {
            return try convertClinicalRecord(record, request: request)
        }
        if let document = sample as? HKCDADocumentSample {
            return try convertClinicalDocument(document, request: request)
        }
        #endif
        guard let binding = HealthKitCatalog.binding(for: sample),
              let output = HealthKitCatalog.primaryOutput(for: type) else {
            throw HealthKitConverter.unconvertibleSampleError(for: type)
        }
        let primary = ExchangeOutputDraft(
            role: output.role,
            discriminator: output.discriminator,
            resource: .observation(try HealthKitConverter.observation(for: sample, binding: binding))
        )
        var outputs = [primary]
        if let workout = sample as? HKWorkout {
            outputs += try HealthKitConverter.workoutSegments(workout)
        }
        return HealthKitConversionSet(primary: try graph(for: sample, type: type, outputs: outputs, request: request))
    }

    /// One source record's graph: the outputs under the sample's envelope, with what the graph does not carry.
    func graph(
        for sample: HKSample,
        type: HealthKitSourceType,
        outputs: [ExchangeOutputDraft],
        request: Request
    ) throws -> HealthKitConversion {
        let source = HealthKitSourceRecord(uuid: sample.uuid, type: type)
        let facts = try SourceFacts(sample, options: request.options)
        var outputs = outputs
        outputs[0].clearIdentifiers = facts.nativeIdentifiers
        outputs[0].writerRecord = facts.writerRecord
        outputs[0].wasUserEntered = facts.wasUserEntered
        let draft = ExchangeGraphDraft(
            event: request.event,
            instant: request.instant,
            sourceRecord: try envelope.sourceRecord(sourceType: type.rawValue, nativeRecordID: sample.uuid.uuidString.lowercased()),
            outputs: outputs,
            recordingDevice: facts.recordingDevice,
            writer: facts.writer,
            converterRole: request.converterRole,
            repositoryIDs: request.repositoryIDs
        )
        let assembled = try assembler.assemble(draft)
        return HealthKitConversion(
            source: source,
            identifiers: assembled.identifiers,
            graph: assembled.graph,
            warnings: facts.warnings + sourceOffsetWarnings(for: sample, outputs: outputs)
        )
    }

    /// The effective elements the outputs serialized in UTC because the sample named no time zone, each once.
    private func sourceOffsetWarnings(for sample: HKSample, outputs: [ExchangeOutputDraft]) -> [HealthKitConversionWarning] {
        guard sample.metadata?[HKMetadataKeyTimeZone] == nil else {
            return []
        }
        var fields: [String] = []
        for output in outputs {
            guard case .observation(let observation) = output.resource else {
                continue
            }
            let elements = switch observation.effective {
            case .dateTime: ["Observation.effectiveDateTime"]
            case .period: ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"]
            case .instant, .timing, nil: [String]()
            }
            fields += elements.filter { !fields.contains($0) }
        }
        return fields.map { .sourceOffsetUnavailable(field: $0) }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// The event context a retraction or a bundled study context is minted from.
    func eventContext(for request: Request) -> ExchangeEventContext {
        ExchangeEventContext(
            subject: envelope.subject,
            event: request.event,
            identityScope: envelope.identityScope,
            repositoryScope: envelope.repositoryScope,
            application: envelope.application,
            host: envelope.host,
            conversionInstant: request.instant,
            converterRole: request.converterRole,
            studies: envelope.studies,
            repositoryIDs: request.repositoryIDs
        )
    }
}

#endif
