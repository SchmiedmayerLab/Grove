//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
public import HealthKit


/// Turns HealthKit samples into exchange records for one deployment, participant and installation.
///
/// Configure it once and keep it for as long as its `ExchangeProducer` is valid; it is safe to share across tasks. An
/// exact redelivery reproduces the same record versions as long as nothing a record states changed. A sample that cannot
/// be converted is reported as a refusal instead of ending the call. The exporter never queries HealthKit: companion data
/// such as ECG voltages arrives through ``Record``.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class HealthKitFHIRExporter: Sendable {
    /// Why an exporter could not be configured.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The disclosed native identifier's system is one of the deployment's own identity systems.
        case reservedNativeIdentifierSystem(IdentifierSystem)
        /// The disclosed native identifier's system cannot be extended by a path: it names no authority, such as a
        /// `urn:oid:` system, or it has a query or a fragment. A stated system is refused only while
        /// ``Options/syncIdentifier`` is authorized, as the readable sync identifier's system extends it. For a derived
        /// system, which always extends it, it is the repository scope's system.
        case nativeIdentifierSystemNotExtensible(IdentifierSystem)
        /// The disclosed native identifier's type is the `healthkit-sync-id` coding, which types readable sync identifiers
        /// alone.
        case reservedNativeIdentifierType(GovernedSourceIdentifierDisclosurePolicy.IdentifierType)
    }

    let producer: ExchangeProducer
    let options: Options
    let assembly: HealthKitAssembly
    /// The totals ``throughput`` reports; `nil` unless ``Options/measuresThroughput`` is set.
    let throughputRecorder: Throughput.Recorder?

    public init(
        producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier,
        options: Options = Options()
    ) throws(ConfigurationError) {
        // Neither the native record identifier nor a readable sync identifier derived from it may use a Grove system, the
        // readable sync identifier's system extends the native one's path, and only a readable sync identifier is typed as one.
        let nativeIdentifier = options.nativeIdentifier.policy(in: repositoryScope, identityScope: producer.identityScope)
        if options.nativeIdentifier.isAuthorized, !nativeIdentifier.isAuthorized {
            throw .nativeIdentifierSystemNotExtensible(repositoryScope.system)
        }
        if case let .authorized(system, type) = nativeIdentifier {
            if let type, type.system.rawValue == HealthKitContract.syncIdentifierTypeSystem.value?.url.absoluteString,
               type.code == HealthKitContract.syncIdentifierTypeCode {
                throw .reservedNativeIdentifierType(type)
            }
            let syncIdentifierPrefix = HealthKitContract.syncIdentifierSystemPrefix(in: system.rawValue)
            guard !producer.identityScope.systems.all.contains(where: { $0 == system || $0.rawValue.hasPrefix(syncIdentifierPrefix) }) else {
                throw .reservedNativeIdentifierSystem(system)
            }
            // Only a disclosed sync identifier extends the system's path; a derived system always extends the scope's.
            guard options.syncIdentifier != .authorized || GovernedSourceIdentifierDisclosurePolicy.acceptsSyncIdentifierPath(system) else {
                throw .nativeIdentifierSystemNotExtensible(system)
            }
        }
        self.producer = producer
        self.options = options
        self.assembly = HealthKitAssembly(
            scope: ExchangeEnvelope.Scope(
                adapter: HealthKitAssembly.adapter,
                identityScope: producer.identityScope,
                subject: producer.subject,
                repositoryScope: repositoryScope
            ),
            options: options
        )
        self.throughputRecorder = options.measuresThroughput ? Throughput.Recorder() : nil
    }

    /// Converts samples, calling `receive` once per produced record or refusal, in input order and on the calling task.
    ///
    /// The call runs where its caller runs, on the caller's actor if it has one, so `receive` may capture the caller's
    /// state. The records are built on child tasks, at most ``Options/maximumConcurrency`` at once and a bounded number at
    /// a time, so a large call keeps that many cores busy while `receive` takes one export at a time.
    ///
    /// A record that cannot be converted is refused in place. Only these end the call:
    /// - an `instant` or a conversion instant no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant`;
    /// - errors of `receive` are rethrown unchanged, and so is the `CancellationError` a cancelled task stops with before
    ///   it hands over its next records.
    ///
    /// - Parameters:
    ///   - samples: The samples, each converted as ``Record/sample(_:)``.
    ///   - instant: The conversion instant of every sample without an entry in `conversionInstants`.
    ///   - conversionInstants: The retained conversion instant of a sample by its UUID, a food correlation's members
    ///     and an ECG's symptoms included. Reusing a sample's first conversion instant keeps its record version when
    ///     the sample is exported again, alone or through its grouping. These instants state when Grove converted the
    ///     sample; they change no clinical effective time.
    ///   - receive: Receives each export, in input order.
    nonisolated(nonsending) public func export<Samples: Collection>(
        _ samples: Samples,
        at instant: Date = .now,
        conversionInstants: [UUID: Date] = [:],
        receive: (Export) throws -> Void
    ) async throws where Samples.Element: HKSample {
        try await export(records: samples.map { Record.sample($0) }, at: instant, conversionInstants: conversionInstants, receive: receive)
    }

    /// ``export(_:at:conversionInstants:receive:)`` for records that carry companion data.
    ///
    /// The records are planned first, then built and handed to `receive` in input order, on the calling task. A food
    /// correlation's members and an ECG's symptoms are records of their own, so a member or symptom also passed as its
    /// own record in the same call is exported twice.
    ///
    /// - Parameters:
    ///   - records: The records, each with the companion data its conversion needs.
    ///   - instant: The conversion instant of every sample without an entry in `conversionInstants`.
    ///   - conversionInstants: The retained conversion instant of a sample by its UUID, a food correlation's members
    ///     and an ECG's symptoms included. A member or symptom without an entry uses `instant`, not its grouping's
    ///     entry. Reusing a sample's first conversion instant keeps its record version when the sample is exported
    ///     again, alone or through its grouping. These instants state when Grove converted the sample; they change no
    ///     clinical effective time.
    ///   - receive: Receives each export, in input order.
    nonisolated(nonsending) public func export(
        records: some Collection<Record>,
        at instant: Date = .now,
        conversionInstants: [UUID: Date] = [:],
        receive: (Export) throws -> Void
    ) async throws {
        guard (try? ExchangeInstant.fhirInstant(instant)) != nil,
              conversionInstants.values.allSatisfy({ (try? ExchangeInstant.fhirInstant($0)) != nil }) else {
            throw ExchangeIdentityError.invalidInstant
        }
        // `nil` unless this exporter measures its throughput; then every phase below is timed.
        let measurement = throughputRecorder.map(Throughput.Call.init)
        defer {
            measurement?.end()
        }
        let measuring = measurement != nil
        let width = options.maximumConcurrency ?? ConcurrentBuild.defaultWidth
        let planned = await ConcurrentBuild.map(Array(records)[...], width: width) { record in
            let start = measuring ? ContinuousClock.now : nil
            let plan = Plan(record, exporter: self)
            return (plan, start.map { ContinuousClock.now - $0 })
        }
        let plans = planned.map(\.0)
        if let measurement {
            for (plan, planning) in planned {
                measurement.planned(plan.source.typeIdentifier, in: planning ?? .zero)
            }
        }
        try await ConcurrentBuild.forEach(plans, width: width) { plan in
            self.build(plan, at: instant, conversionInstants: conversionInstants, measuring: measuring)
        } hand: { plan, delivery in
            try hand(delivery, of: plan, measurement: measurement, receive: receive)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// One record prepared before it is built: its type's content plan, an ECG's evidence validated, and what the policies
    /// resolved for each sample it converts, its record and each registered ECG symptom.
    struct Plan: Sendable {
        /// A sample converted beside a record, with what the policies answered for it; `nil` for a type the inventory
        /// does not list.
        struct Companion: Sendable {
            let sample: HKSample
            let policies: ResolvedPolicies?

            init(_ sample: HKSample, options: Options) {
                self.sample = sample
                self.policies = HealthKitContentPlan.plan(for: sample) == nil ? nil : ResolvedPolicies(sample, options: options)
            }
        }

        /// The record.
        let record: Record
        /// The plan of the record's type, or `nil` for a type the inventory does not list.
        let content: HealthKitContentPlan?
        /// An ECG record's evidence, validated once here; `nil` for any other record, and for an ECG whose evidence
        /// does not validate, which its delivery refuses for that reason.
        let evidence: HealthKitECGContent.Evidence?
        /// A heartbeat series' beat intervals or a route's track as its recording document carries them, serialized
        /// once here; `nil` for any other record.
        let recording: Result<Data, any Error>?
        /// Whether the options export nothing for the record, a workout route while `route` is `.omit`: it hands nothing
        /// over, which is not a refusal.
        let omitted: Bool
        /// The source revision the record states in place of its sample's own; see
        /// ``Record/unsavedSampleRevision(producer:)``.
        ///
        /// Only ever an override, never the sample's own revision: HealthKit declares `sourceRevision` nonnull, but returns
        /// no object for a sample the store never held, and a nil reference stored as non-optional reads as `nil` to any
        /// `Optional` wrapping the plan, which ends the iteration that hands the plans over.
        let revisionOverride: HKSourceRevision?
        /// What the policies answered for the record, or `nil` for a type the inventory does not list and for an omitted
        /// record.
        let primary: ResolvedPolicies?
        /// The samples converted beside the record, each a record of its own under its own policies: an ECG's correlated
        /// symptoms in the record's order, or a food correlation's members in the order of their UUIDs.
        let companions: [Companion]

        var source: Export.Source {
            Export.Source(uuid: record.sample.uuid, typeIdentifier: record.sample.sampleType.identifier)
        }

        init(_ record: Record, exporter: HealthKitFHIRExporter) {
            let sample = record.sample
            let content = HealthKitContentPlan.plan(for: sample)
            let evidence: HealthKitECGContent.Evidence? = if let content, case let .electrocardiogram(ecg, voltages, _) = record {
                try? content.ecgEvidence(ecg, voltages: voltages)
            } else {
                nil
            }
            let omitted = content != nil && record.isWorkoutRoute && exporter.options.route == .omit
            self.record = record
            self.content = content
            self.evidence = evidence
            self.recording = omitted ? nil : content.flatMap { record.recording(content: $0) }
            self.omitted = omitted
            let revisionOverride = record.unsavedSampleRevision(producer: exporter.producer.facts)
            self.revisionOverride = revisionOverride
            let primary = omitted || content == nil
                ? nil
                : ResolvedPolicies(sample, options: exporter.options, revisionOverride: revisionOverride)
            self.primary = primary
            let companions: [HKSample] = if primary == nil {
                []
            } else if case .food? = content?.route, let correlation = sample as? HKCorrelation {
                correlation.objects.sorted { $0.uuid.uuidString < $1.uuid.uuidString }
            } else {
                record.symptoms
            }
            self.companions = companions.map { Companion($0, options: exporter.options) }
        }

        /// ``recording``'s bytes, or what serializing them threw.
        func recordingPayload() throws -> Data {
            guard let recording else {
                preconditionFailure("Only a heartbeat series or a workout route is converted from its recording.")
            }
            return try recording.get()
        }
    }

    /// What one record's delivery hands over: its exports, and what building them took when measured.
    struct Delivery: Sendable {
        let exports: [Export]
        /// Building the record, validation included; zero unless measured.
        let building: Swift.Duration
        /// Validating it; zero unless measured.
        let validation: Swift.Duration
    }

    /// The exports of one planned record, built without the caller: refusals in place, records otherwise.
    private func build(_ plan: Plan, at instant: Date, conversionInstants: [UUID: Date], measuring: Bool) -> Delivery {
        let start = measuring ? ContinuousClock.now : nil
        func delivery(_ exports: [Export], validation: Swift.Duration = .zero) -> Delivery {
            Delivery(exports: exports, building: start.map { ContinuousClock.now - $0 } ?? .zero, validation: validation)
        }
        guard !plan.omitted else {
            return delivery([])
        }
        guard let primary = plan.primary, let content = plan.content else {
            let refusal = HealthKitConversionError.unregisteredSourceType(plan.record.sample.sampleType.identifier)
            return delivery([Export(source: plan.source, outcome: .refused(refusal), warnings: [])])
        }
        do {
            let conversions = try convert(plan, content: content, primary: primary, at: instant, conversionInstants: conversionInstants)
            return delivery(conversions.map(\.export), validation: conversions.reduce(.zero) { $0 + $1.validation })
        } catch {
            let failure = HealthKitConversionError(conversionFailure: error, source: plan.source.sourceType)
            return delivery([Export(source: plan.source, outcome: .refused(failure), warnings: [])])
        }
    }

    /// Hands one record's exports to the caller, whose time is measured apart from the exporter's.
    private func hand(
        _ delivery: Delivery,
        of plan: Plan,
        measurement: Throughput.Call?,
        receive: (Export) throws -> Void
    ) throws {
        guard let measurement else {
            for export in delivery.exports {
                try receive(export)
            }
            return
        }
        measurement.built(plan.source.typeIdentifier, in: delivery.building, validation: delivery.validation)
        for export in delivery.exports {
            let handStart = measurement.now
            try receive(export)
            measurement.received(export, in: measurement.now - handStart)
        }
    }

    private func convert(
        _ plan: Plan,
        content: HealthKitContentPlan,
        primary: ResolvedPolicies,
        at instant: Date,
        conversionInstants: [UUID: Date]
    ) throws -> [HealthKitAssembly.Conversion] {
        let request = assemblyRequest(
            for: plan.record.sample,
            revisionOverride: plan.revisionOverride,
            policies: primary,
            at: conversionInstants[plan.source.uuid] ?? instant
        )
        switch plan.record {
        case .sample(let sample):
            if case .food(let food) = content.route, let correlation = sample as? HKCorrelation {
                return try assembly.convertFood(
                    correlation,
                    content: food,
                    members: plan.companions.map(\.sample),
                    memberRequests: companionRequests(plan, at: instant, conversionInstants: conversionInstants),
                    request: request
                )
            }
            return try assembly.convert(sample, plan: content, request: request)
        case .unsavedSample(let unsavedSample, source: _):
            return try assembly.convert(unsavedSample.sample, plan: content, request: request)
        case let .electrocardiogram(ecg, voltages, symptoms):
            // An ECG whose evidence did not validate when it was planned is refused now, for the same reason.
            let evidence = try plan.evidence ?? content.ecgEvidence(ecg, voltages: voltages)
            return try assembly.convertECG(
                evidence,
                symptoms: symptoms,
                plan: content,
                request: request,
                symptomRequests: companionRequests(plan, at: instant, conversionInstants: conversionInstants)
            )
        case let .heartbeatSeries(series, _):
            return try assembly.convertHeartbeatSeries(series, recording: plan.recordingPayload(), plan: content, request: request)
        case let .workoutRoute(route, _):
            return try assembly.convertWorkoutRoute(route, recording: plan.recordingPayload(), plan: content, request: request)
        case .fileRecording(let recording):
            return try assembly.documentGraph(
                for: recording.sample,
                plan: content,
                document: content.recordingDocument().document(recording: recording),
                request: request
            )
        }
    }

    /// The request of each companion of a registered type, keyed by its sample's UUID.
    private func companionRequests(_ plan: Plan, at instant: Date, conversionInstants: [UUID: Date]) -> [UUID: HealthKitAssembly.Request] {
        var requests: [UUID: HealthKitAssembly.Request] = [:]
        for companion in plan.companions {
            let uuid = companion.sample.uuid
            guard let policies = companion.policies, requests[uuid] == nil else {
                continue
            }
            requests[uuid] = assemblyRequest(for: companion.sample, policies: policies, at: conversionInstants[uuid] ?? instant)
        }
        return requests
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What the assembly builds one record from: the conversion instant, the producer's facts, the source revision the
    /// record states in place of its sample's own, if any, and what the policies answered for its sample.
    func assemblyRequest(
        for sample: HKSample,
        revisionOverride: HKSourceRevision? = nil,
        policies: ResolvedPolicies,
        at instant: Date
    ) -> HealthKitAssembly.Request {
        HealthKitAssembly.Request(
            instant: instant,
            facts: producer.facts,
            // The gateway role compares the sample's revision with the producer's build.
            converterRole: options.role.converterRole(
                for: revisionOverride ?? sample.sourceRevision,
                application: producer.facts.application
            ),
            sourceRevisionOverride: revisionOverride,
            policies: policies
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Record {
    var isWorkoutRoute: Bool {
        switch self {
        case .workoutRoute: true
        case .fileRecording(let recording): recording.sample is HKWorkoutRoute
        default: false
        }
    }

    /// The correlated symptoms, each a record of its own.
    var symptoms: [HKCategorySample] {
        guard case .electrocardiogram(_, _, let symptoms) = self else {
            return []
        }
        return symptoms
    }

    /// What the recording document of a heartbeat series or a workout route carries under `content`, the plan of the
    /// record's type: its beat intervals or its track, or what serializing them throws; `nil` for any other record.
    func recording(content: HealthKitContentPlan) -> Result<Data, any Error>? {
        switch self {
        case let .heartbeatSeries(series, beats):
            Result { try content.recordingDocument().beatIntervals(seriesStart: series.startDate, heartbeats: beats) }
        case let .workoutRoute(_, locations):
            Result { try content.recordingDocument().locationTrack(locations) }
        case .sample, .unsavedSample, .electrocardiogram, .fileRecording:
            nil
        }
    }
}

#endif
