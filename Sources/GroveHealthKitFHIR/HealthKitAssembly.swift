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
    /// What one record's conversion needs beyond the envelope's scope: its event, the facts frozen with it,
    /// and the policies in force.
    struct Request: Sendable {
        let event: ExchangeEventIdentifier
        let instant: Date
        /// The application, host and studies the event states, as its reservation froze them.
        let facts: ExchangeEventFacts
        let converterRole: ConverterRole
        let repositoryIDs: [ExchangeGraphNode: RepositoryID]
        let options: HealthKitConversionOptions

        init(
            event: ExchangeEventIdentifier,
            instant: Date,
            facts: ExchangeEventFacts,
            converterRole: ConverterRole = .assembler,
            repositoryIDs: [ExchangeGraphNode: RepositoryID] = [:],
            options: HealthKitConversionOptions = .default
        ) {
            self.event = event
            self.instant = instant
            self.facts = facts
            self.converterRole = converterRole
            self.repositoryIDs = repositoryIDs
            self.options = options
        }

        init(context: HealthKitConversionContext) {
            self.init(
                event: context.event.event,
                instant: context.event.conversionInstant,
                facts: ExchangeEventFacts(context.event),
                converterRole: context.event.converterRole,
                repositoryIDs: context.event.repositoryIDs,
                options: context.options
            )
        }
    }

    /// The revision of the graphs this adapter's assembly builds. Bump it whenever the bytes it emits can
    /// change for equal inputs: it enters every exporter's context fingerprint, so an event reserved under an
    /// older revision is never redelivered under the same identifier with different bytes.
    static let outputRevision: UInt = 2

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

    /// The producer's scope. It holds no facts: each graph's envelope takes its own request's frozen facts.
    let scope: ExchangeEnvelope.Scope

    init(scope: ExchangeEnvelope.Scope) {
        self.scope = scope
    }

    init(context: ExchangeEventContext) {
        self.init(scope: ExchangeEnvelope.Scope(
            adapter: Self.adapter,
            identityScope: context.identityScope,
            subject: context.subject,
            repositoryScope: context.repositoryScope
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
        // A workout exports its session alone: the pinned guide defines no HealthKit segment output, and a
        // deletion could not name segments it never saw (healthkit-adapter.json workout row).
        return HealthKitConversionSet(primary: try graph(for: sample, type: type, outputs: [primary], request: request))
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
        outputs[0].wasUserEntered = facts.wasUserEntered
        // A writer-record identity travels only with its version, and only an Observation carries the version
        // extension; a document states neither, though the pair is still validated.
        if case .observation = outputs[0].resource {
            outputs[0].writerRecord = facts.writerRecord
        }
        let draft = ExchangeGraphDraft(
            event: request.event,
            instant: request.instant,
            sourceRecord: try scope.sourceRecord(sourceType: type.rawValue, nativeRecordID: sample.uuid.uuidString.lowercased()),
            outputs: outputs,
            recordingDevice: facts.recordingDevice,
            writer: facts.writer,
            converterRole: request.converterRole,
            repositoryIDs: request.repositoryIDs
        )
        let assembled = try ExchangeGraphAssembler(envelope: ExchangeEnvelope(scope: scope, facts: request.facts)).assemble(draft)
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
    /// Whether `revision` names `application` in the build it states: the same bundle identifier, and an
    /// `HKSourceRevision.version` (HealthKit copies the source's `CFBundleVersion`) equal to `application.build`.
    /// An application that states no build, or a revision without a version, never matches.
    static func isSameBuild(_ revision: HKSourceRevision, as application: ApplicationDevice) -> Bool {
        guard let build = application.build, let version = revision.version?.nonBlank else {
            return false
        }
        return version == build && revision.source.bundleIdentifier == application.bundleIdentifier
    }

    /// The event context a retraction or a bundled study context is minted from, under the request's facts.
    func eventContext(for request: Request) -> ExchangeEventContext {
        ExchangeEventContext(
            subject: scope.subject,
            event: request.event,
            identityScope: scope.identityScope,
            repositoryScope: scope.repositoryScope,
            application: request.facts.application,
            host: request.facts.host,
            conversionInstant: request.instant,
            converterRole: request.converterRole,
            studies: request.facts.studies,
            repositoryIDs: request.repositoryIDs
        )
    }
}


extension ExchangeEventFacts {
    /// The facts an explicit event context states.
    init(_ context: ExchangeEventContext) {
        self.init(application: context.application, host: context.host, studies: context.studies)
    }
}

#endif
