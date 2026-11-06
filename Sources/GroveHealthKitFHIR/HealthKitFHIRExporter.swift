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
        if case .authorized(let system, _) = options.nativeIdentifier,
           producer.identityScope.systems.all.contains(system) {
            throw .reservedNativeIdentifierSystem(system)
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
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant`;
    /// - errors of `receive` are rethrown unchanged, and so is the `CancellationError` a cancelled task stops with before
    ///   it hands over its next records.
    nonisolated(nonsending) public func export<Samples: Collection>(
        _ samples: Samples,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) async throws where Samples.Element: HKSample {
        try await export(records: samples.map { Record.sample($0) }, at: instant, receive: receive)
    }

    /// ``export(_:at:receive:)`` for records that carry companion data.
    ///
    /// The records are planned first, then built and handed to `receive` in input order, on the calling task.
    nonisolated(nonsending) public func export(
        records: some Collection<Record>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) async throws {
        guard (try? ExchangeInstant.fhirInstant(instant)) != nil else {
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
            self.build(plan, at: instant, measuring: measuring)
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
        /// What the policies answered for the record, or `nil` for a type the inventory does not list and for an omitted
        /// record.
        let primary: ResolvedPolicies?
        /// One entry per correlated symptom, in the record's order; `nil` for a symptom of an unregistered type.
        let symptoms: [ResolvedPolicies?]

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
            let omitted = if content != nil, case .workoutRoute = record { exporter.options.route == .omit } else { false }
            self.record = record
            self.content = content
            self.evidence = evidence
            self.recording = omitted ? nil : content.flatMap { record.recording(content: $0) }
            self.omitted = omitted
            let primary = omitted || content == nil ? nil : ResolvedPolicies(sample, options: exporter.options)
            self.primary = primary
            self.symptoms = primary == nil ? [] : record.symptoms.map { symptom in
                HealthKitContentPlan.plan(for: symptom) == nil ? nil : ResolvedPolicies(symptom, options: exporter.options)
            }
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
    private func build(_ plan: Plan, at instant: Date, measuring: Bool) -> Delivery {
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
            let conversions = try convert(plan, content: content, primary: primary, at: instant)
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
        at instant: Date
    ) throws -> [HealthKitAssembly.Conversion] {
        let request = assemblyRequest(for: plan.record.sample, policies: primary, at: instant)
        switch plan.record {
        case .sample(let sample):
            return try assembly.convert(sample, plan: content, request: request)
        case let .electrocardiogram(ecg, voltages, symptoms):
            // An ECG whose evidence did not validate when it was planned is refused now, for the same reason.
            let evidence = try plan.evidence ?? content.ecgEvidence(ecg, voltages: voltages)
            return try assembly.convertECG(
                evidence,
                symptoms: symptoms,
                plan: content,
                request: request,
                symptomRequests: symptomRequests(plan, at: instant)
            )
        case let .heartbeatSeries(series, _):
            return try assembly.convertHeartbeatSeries(series, recording: plan.recordingPayload(), plan: content, request: request)
        case let .workoutRoute(route, _):
            return try assembly.convertWorkoutRoute(route, recording: plan.recordingPayload(), plan: content, request: request)
        }
    }

    /// Each registered symptom's request, keyed by its sample's UUID.
    private func symptomRequests(_ plan: Plan, at instant: Date) -> [UUID: HealthKitAssembly.Request] {
        var requests: [UUID: HealthKitAssembly.Request] = [:]
        for (symptom, policies) in zip(plan.record.symptoms, plan.symptoms) {
            guard let policies, requests[symptom.uuid] == nil else {
                continue
            }
            requests[symptom.uuid] = assemblyRequest(for: symptom, policies: policies, at: instant)
        }
        return requests
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What the assembly builds one record from: the conversion instant, the producer's facts, and what the policies
    /// answered for its sample.
    func assemblyRequest(for sample: HKSample, policies: ResolvedPolicies, at instant: Date) -> HealthKitAssembly.Request {
        HealthKitAssembly.Request(
            instant: instant,
            facts: producer.facts,
            // The gateway role compares the sample's revision with the producer's build.
            converterRole: options.role.converterRole(for: sample.sourceRevision, application: producer.facts.application),
            policies: policies
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Record {
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
        case .sample, .electrocardiogram:
            nil
        }
    }
}

#endif
