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
    /// What one record's conversion needs beyond the exporter's scope and options: the conversion instant, the producer's
    /// facts, and what the exporter's policies answered for its sample.
    struct Request: Sendable {
        let instant: Date
        /// The application, host and studies the record states.
        let facts: ConversionFacts
        let converterRole: ConverterRole
        /// What the writer and unit-token policies answered for the sample; a retraction states no sample's origin and
        /// resolves nothing.
        let policies: HealthKitFHIRExporter.ResolvedPolicies

        init(
            instant: Date,
            facts: ConversionFacts,
            converterRole: ConverterRole = .assembler,
            policies: HealthKitFHIRExporter.ResolvedPolicies = .unresolved
        ) {
            self.instant = instant
            self.facts = facts
            self.converterRole = converterRole
            self.policies = policies
        }
    }

    /// One record as the assembly built it: the sample it is for, the identities it states, and what the sample carried
    /// that the record does not.
    struct Conversion: Sendable {
        let source: HealthKitFHIRExporter.Export.Source
        let identifiers: ExchangeGraphIdentifiers
        let record: ExchangeRecord
        /// Each one registered `mobile-omission` rule; empty when the record carries everything its sample supplied.
        let warnings: [ProducerDiagnostic]
        /// The metadata keys the sample, or an object it contains, carried that the record does not represent, each once
        /// and sorted. The `mobile-omission.unmodeled-metadata` warning states only that there are some.
        let withheldMetadataKeys: [String]
        let metadataSummary: HealthKitFHIRExporter.Export.MetadataSummary
        /// How long encoding and validating the record took; zero unless the exporter measures its throughput.
        let validation: Swift.Duration

        /// The export that delivers this record.
        var export: HealthKitFHIRExporter.Export {
            HealthKitFHIRExporter.Export(source: source, outcome: .record(record), warnings: warnings, metadata: metadataSummary)
        }
    }

    /// The HealthKit adapter: its closed token, which every HealthKit identity preimage carries, and the profiles and
    /// application identifier its envelopes state.
    static let adapter = ExchangeAdapterContract(
        adapterID: "healthkit",
        provenanceProfile: HealthKitContract.conversionProvenanceProfile,
        applicationDeviceProfile: HealthKitContract.applicationDeviceProfile
    ) { $0.appleBundleIdentifier }

    /// The producer's scope. It holds no facts: each record's envelope takes its own request's.
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
            let primary = plan.outputs[0].draft(.observation(try observation.observation(sample, metadata: metadata)))
            var outputs = [primary]
            if case .workout(let content) = observation.value, let workout = sample as? HKWorkout {
                outputs += try content.segments(workout, metadata: metadata)
            }
            return [try graph(for: sample, type: plan.sourceType, metadata: metadata, outputs: outputs, request: request)]
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
        let facts = try SourceFacts(sample, metadata: metadata, outputs: outputs, policies: request.policies, options: options)
        var outputs = outputs
        outputs[0].clearIdentifiers = facts.nativeIdentifiers
        let sourceMetadata = HealthKitSourceMetadata(sample: sample, values: metadata.values, disclosure: options.metadata)
        if let container = sourceMetadata.container {
            outputs[0].trailingExtensions.append(container)
        }
        // One record states one entry method: its metadata decides it for every output it yields.
        for index in outputs.indices {
            outputs[index].wasUserEntered = facts.wasUserEntered
        }
        // A writer-record identity travels only with its version, and only an Observation carries the version
        // extension; a document states neither, though the pair is still validated.
        if case .observation = outputs[0].resource {
            outputs[0].writerRecord = facts.writerRecord
            if type == .workout {
                for index in outputs.indices.dropFirst() {
                    outputs[index].writerRecord = facts.writerRecord
                }
            }
        }
        let draft = ExchangeRecordDraft(
            instant: request.instant,
            sourceRecord: try scope.sourceRecord(sourceType: type.rawValue, nativeRecordID: sample.uuid.uuidString.lowercased()),
            outputs: outputs,
            recordingDevice: facts.recordingDevice,
            writer: facts.writer,
            sourceExtensions: facts.sourceRevision.map { [$0] } ?? [],
            converterRole: request.converterRole
        )
        var validation = Swift.Duration.zero
        let assembled = try ExchangeGraphAssembler(envelope: ExchangeEnvelope(scope: scope, facts: request.facts))
            .assemble(draft, onValidation: options.measuresThroughput ? { validation += $0 } : nil)
        let withheld = metadata.withheldKeys(
            in: outputs,
            device: facts.recordingDevice,
            preservedSampleKeys: sourceMetadata.preservedKeys,
            excludesSampleMetadata: options.metadata == .omit
        )
        return Conversion(
            source: HealthKitFHIRExporter.Export.Source(uuid: sample.uuid, typeIdentifier: type.rawValue),
            identifiers: assembled.identifiers,
            record: assembled.record,
            warnings: metadataWarnings(for: metadata, outputs: outputs, withheld: withheld),
            withheldMetadataKeys: withheld,
            metadataSummary: sourceMetadata.summary,
            validation: validation
        )
    }

    /// What the decorated `outputs` do not carry of the record's metadata: the `withheld` keys, as the registered
    /// `mobile-omission.unmodeled-metadata` warning located at the source's metadata; manual entry a blood-pressure
    /// correlation or member states but the record does not establish, as `mobile-omission.recording-method` located at
    /// the extension the Observation omits; then each effective element they serialized in UTC because the record named
    /// no time zone, each once, as the registered `mobile-omission.source-offset` warning located at the element.
    private func metadataWarnings(
        for metadata: HealthKitSampleMetadata,
        outputs: [ExchangeOutputDraft],
        withheld: [String]
    ) -> [ProducerDiagnostic] {
        var omissions = withheld.isEmpty ? [] : [ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic(at: "HKSample.metadata")]
        if metadata.omitsStatedManualEntry(in: outputs) {
            omissions.append(ExchangeGraphRule.mobileOmissionRecordingMethod.diagnostic(at: "Observation.extension"))
        }
        guard !metadata.statesTimeZone else {
            return omissions
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
        return omissions + fields.map(ExchangeGraphRule.mobileOmissionSourceOffset.diagnostic(at:))
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
}

#endif
