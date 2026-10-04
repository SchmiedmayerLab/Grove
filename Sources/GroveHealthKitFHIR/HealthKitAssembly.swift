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
    /// What one record's conversion needs beyond the exporter's scope and options: its event, the facts frozen with
    /// it, and what the exporter's policies answered for its sample.
    struct Request: Sendable {
        let event: ExchangeEventIdentifier
        let instant: Date
        /// The application, host and studies the event states, as its reservation froze them.
        let facts: ExchangeEventFacts
        let converterRole: ConverterRole
        /// The transitional legacy `Bundle.id` ``HealthKitFHIRExporter/Options/legacyBundleID`` asks for.
        let bundleID: RepositoryID?
        /// What the writer and recording-device policies answered for the sample before its event was reserved; a
        /// retraction states no sample's origin and resolves nothing.
        let policies: HealthKitFHIRExporter.ResolvedPolicies

        init(
            event: ExchangeEventIdentifier,
            instant: Date,
            facts: ExchangeEventFacts,
            converterRole: ConverterRole = .assembler,
            bundleID: RepositoryID? = nil,
            policies: HealthKitFHIRExporter.ResolvedPolicies = .unresolved
        ) {
            self.event = event
            self.instant = instant
            self.facts = facts
            self.converterRole = converterRole
            self.bundleID = bundleID
            self.policies = policies
        }
    }

    /// One record's graph as the assembly built it: the record it is for, the identities it states, and what the record
    /// carried that the graph does not.
    struct Conversion: Sendable {
        let source: HealthKitFHIRExporter.Export.Source
        let identifiers: ExchangeGraphIdentifiers
        let graph: ExchangeGraph
        /// Each one registered `mobile-omission` rule; empty when the graph carries everything its record supplied.
        let warnings: [ProducerDiagnostic]
        /// The metadata keys the record, or an object it contains, carried that the graph does not represent, each once
        /// and sorted. The `mobile-omission.unmodeled-metadata` warning states only that there are some.
        let withheldMetadataKeys: [String]

        /// The export that delivers this graph.
        var export: HealthKitFHIRExporter.Export {
            HealthKitFHIRExporter.Export(source: source, outcome: .graph(graph), warnings: warnings)
        }
    }

    /// The revision of the graphs this adapter's assembly builds. Bump it whenever the bytes it emits can
    /// change for equal inputs: it enters every exporter's context fingerprint, so an event reserved under an
    /// older revision is never redelivered under the same identifier with different bytes.
    static let outputRevision: UInt = 11

    /// The HealthKit adapter: its closed token, which every HealthKit identity preimage and event key carries, and the
    /// profiles and application identifier its envelopes state.
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
    /// The exporter's options: what every graph discloses.
    let options: HealthKitFHIRExporter.Options

    init(scope: ExchangeEnvelope.Scope, options: HealthKitFHIRExporter.Options = HealthKitFHIRExporter.Options()) {
        self.scope = scope
        self.options = options
    }

    /// Converts one sample only when the closed catalog admits its exact published contract.
    func convert(_ sample: HKSample, request: Request) throws -> [Conversion] {
        guard let plan = HealthKitContentPlan.plan(for: sample) else {
            throw HealthKitConversionError.unregisteredSourceType(sample.sampleType.identifier)
        }
        return try convert(sample, plan: plan, request: request)
    }

    /// Converts one sample through its type's plan. An ECG or a recording needs the caller's companion data, so its
    /// bare sample is refused.
    func convert(_ sample: HKSample, plan: HealthKitContentPlan, request: Request) throws -> [Conversion] {
        switch plan.route {
        case .observation(let observation):
            let metadata = HealthKitSampleMetadata(sample, rule: plan.metadata)
            // A workout exports its session alone: the pinned guide defines no HealthKit segment output, and a
            // deletion could not name segments it never saw (healthkit-adapter.json workout row).
            let primary = plan.outputs[0].draft(.observation(try observation.observation(sample, metadata: metadata)))
            return [try graph(for: sample, type: plan.sourceType, metadata: metadata, outputs: [primary], request: request)]
        case .clinical(let document):
            let carried = try clinicalDocument(sample, plan: plan, document: document)
            return try documentGraph(for: sample, plan: plan, document: carried, request: request)
        case .electrocardiogram:
            throw HealthKitConversionError.ecgEvidence(.evidenceRequired)
        case .recording:
            // The inventory admits the type only as a document of the caller's series, which a bare sample lacks.
            throw HealthKitConversionError.platformExclusiveSourceType(plan.sourceType)
        case .refused(let error):
            throw error
        }
    }

    /// One source record's graph: the outputs under the sample's envelope, with what the graph does not carry.
    func graph(
        for sample: HKSample,
        type: HealthKitSourceType,
        metadata: HealthKitSampleMetadata,
        outputs: [ExchangeOutputDraft],
        request: Request
    ) throws -> Conversion {
        guard !outputs.isEmpty else {
            throw ExchangeAssemblyError.noOutputs
        }
        let facts = try SourceFacts(sample, metadata: metadata, policies: request.policies, options: options)
        var outputs = outputs
        outputs[0].clearIdentifiers = facts.nativeIdentifiers
        // One record states one entry method: its metadata decides it for every output it yields.
        for index in outputs.indices {
            outputs[index].wasUserEntered = facts.wasUserEntered
        }
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
            bundleID: request.bundleID
        )
        let assembled = try ExchangeGraphAssembler(envelope: ExchangeEnvelope(scope: scope, facts: request.facts)).assemble(draft)
        let withheld = metadata.withheldKeys(in: outputs)
        return Conversion(
            source: HealthKitFHIRExporter.Export.Source(uuid: sample.uuid, typeIdentifier: type.rawValue),
            identifiers: assembled.identifiers,
            graph: assembled.graph,
            warnings: facts.warnings + metadataWarnings(for: metadata, outputs: outputs, withheld: withheld),
            withheldMetadataKeys: withheld
        )
    }

    /// What the decorated `outputs` do not carry of the record's metadata: the `withheld` keys, as the registered
    /// `mobile-omission.unmodeled-metadata` warning located at the source's metadata, then each effective element they
    /// serialized in UTC because the record named no time zone, each once, as the registered
    /// `mobile-omission.source-offset` warning located at the element.
    private func metadataWarnings(
        for metadata: HealthKitSampleMetadata,
        outputs: [ExchangeOutputDraft],
        withheld: [String]
    ) -> [ProducerDiagnostic] {
        let unmodeled = withheld.isEmpty ? [] : [ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKSample.metadata")]
        guard !metadata.statesTimeZone else {
            return unmodeled
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
        return unmodeled + fields.map(ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at:))
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

    /// The event context a retraction is minted from, under the request's facts.
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
            repositoryIDs: request.bundleID.map { [.bundle: $0] } ?? [:]
        )
    }
}

#endif
