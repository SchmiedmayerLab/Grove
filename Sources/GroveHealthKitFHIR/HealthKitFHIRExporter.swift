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


/// Turns HealthKit samples into exchange graphs for one deployment, participant and installation.
///
/// Configure it once and keep it for as long as its `ExchangeProducer` is valid; it is safe to share
/// across tasks. Every export mints its events through the producer, in one ledger transaction per call,
/// so an exact redelivery before `ExchangeProducer.Receipt.release()` reproduces the same events byte for
/// byte, even when the application, the host or the studies changed in between. A sample that cannot be
/// converted is reported as a refusal instead of ending the call. The exporter never queries HealthKit:
/// companion data such as ECG voltages arrives through ``Record``.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class HealthKitFHIRExporter: Sendable {
    /// Why an exporter could not be configured.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The disclosed native identifier's system is one of the deployment's own identity systems.
        case reservedNativeIdentifierSystem(IdentifierSystem)
    }

    let producer: ExchangeProducer
    /// The business identifier naming this installation's HealthKit store; it enters every source identity.
    let repositoryScope: BusinessIdentifier
    let options: Options
    let assembly: HealthKitAssembly
    /// What shapes every graph beside the frozen facts; it fingerprints each request.
    let context: ExchangeRequestContext
    /// The totals ``throughput`` reports; `nil` unless ``Options/measuresThroughput`` is set.
    let throughputRecorder: Throughput.Recorder?

    public convenience init(
        producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier,
        options: Options = Options()
    ) throws(ConfigurationError) {
        try self.init(producer: producer, repositoryScope: repositoryScope, options: options, outputRevisions: .current)
    }

    /// An exporter that fingerprints its requests under `outputRevisions`; tests vary them.
    init(
        producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier,
        options: Options,
        outputRevisions: OutputRevisions
    ) throws(ConfigurationError) {
        if case .authorized(let system, _) = options.nativeIdentifier,
           producer.identityScope.systems.all.contains(system) {
            throw .reservedNativeIdentifierSystem(system)
        }
        self.producer = producer
        self.repositoryScope = repositoryScope
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
        self.context = ExchangeRequestContext(
            label: "grove-healthkit-context-v0",
            outputRevisions: [outputRevisions.assembler, outputRevisions.healthKit],
            producer: producer,
            repositoryScope: repositoryScope,
            settings: options.fingerprintParts
        )
        self.throughputRecorder = options.measuresThroughput ? Throughput.Recorder() : nil
    }

    /// Converts samples, calling `receive` once per produced graph or refusal, in input order and on the calling task.
    ///
    /// The call runs where its caller runs, on the caller's actor if it has one, so `receive` may capture the caller's
    /// state. The graphs are built on child tasks, at most ``Options/maximumConcurrency`` at once and a bounded number of
    /// records at a time, so a large call keeps that many cores busy while `receive` takes one export at a time.
    ///
    /// A record that cannot be converted is refused in place, and so is a record the call names again with
    /// other content (``HealthKitConversionError/conflictingDuplicate``): the first input of a record keeps
    /// its event, so an exact retry of the call reproduces every event. Only these end the call:
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant` before the ledger is touched;
    /// - the producer's ledger throws `ExchangeProducer.LedgerError` when a stored entry is corrupt or
    ///   from a later layout, and `ExchangeProducer.resetLedger()` always recovers;
    /// - errors of the ledger's storage and of `receive` are rethrown unchanged, and so is the `CancellationError` a
    ///   cancelled task stops with between chunks; the reservations made stay for the redelivery.
    public nonisolated(nonsending) func export<Samples: Collection>(
        _ samples: Samples,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) async throws -> ExchangeProducer.Receipt where Samples.Element: HKSample {
        try await export(records: samples.map { Record.sample($0) }, at: instant, receive: receive)
    }

    /// ``export(_:at:receive:)`` for records that carry companion data.
    ///
    /// The records are planned first, then one reserve transaction covers every event they need, then their graphs are
    /// built and handed to `receive` in input order, on the calling task.
    public nonisolated(nonsending) func export(
        records: some Collection<Record>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) async throws -> ExchangeProducer.Receipt {
        // `nil` unless this exporter measures its throughput; then every phase below is timed.
        let measurement = throughputRecorder.map(Throughput.Call.init)
        defer {
            measurement?.end()
        }
        let measuring = measurement != nil
        let width = options.maximumConcurrency ?? ConcurrentBuild.defaultWidth
        let planned = await ConcurrentBuild.map(Array(records)[...], width: width) { record in
            autoreleasepool {
                let start = measuring ? ContinuousClock.now : nil
                let plan = Plan(record, exporter: self)
                return (plan, start.map { ContinuousClock.now - $0 })
            }
        }
        let plans = planned.map(\.0)
        if let measurement {
            for (plan, planning) in planned {
                measurement.planned(plan.source.typeIdentifier, in: planning ?? .zero)
            }
        }
        // One fingerprint per key and call, the first in input order: a key reserved under two would keep only the
        // later, and a retry of the call would mint both again.
        let firstPerKey = Dictionary(plans.flatMap(\.requests).map { ($0.key, $0) }) { first, _ in first }
        // Refusals alone need no event, and a call that reserves nothing never touches the ledger.
        let reserveStart = measurement?.now
        let (reserved, receipt) = try producer.reserve(Set(firstPerKey.values), at: instant)
        measurement?.reserved(since: reserveStart)
        try await ConcurrentBuild.forEach(plans, width: width) { plan in
            autoreleasepool {
                self.build(plan, reserved: reserved, measuring: measuring)
            }
        } hand: { plan, delivery in
            try hand(delivery, of: plan, measurement: measurement, receive: receive)
        }
        return receipt
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// One record prepared before the reservation: its type's content plan, an ECG's evidence validated, and one event
    /// per sample it converts, its record and each registered ECG symptom, under what the policies resolved for that
    /// sample. Each event's fingerprint covers those answers and the record's companion data, and its graph is built
    /// from exactly them.
    struct Plan: Sendable {
        /// One sample's request and what the policies answered for it.
        struct Event: Sendable {
            let request: ExchangeEventRequest
            let policies: ResolvedPolicies
        }

        /// The record.
        let record: Record
        /// The plan of the record's type, or `nil` for a type the inventory does not list.
        let content: HealthKitContentPlan?
        /// An ECG record's evidence, validated once here; `nil` for any other record, and for an ECG whose evidence
        /// does not validate, which its delivery refuses for that reason.
        let evidence: HealthKitECGContent.Evidence?
        /// The record's own event, or `nil` for a type the inventory does not list.
        let primary: Event?
        /// One entry per correlated symptom, in the record's order; `nil` for a symptom of an unregistered type.
        let symptoms: [Event?]

        var requests: [ExchangeEventRequest] {
            ([primary] + symptoms).compactMap { $0?.request }
        }

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
            let primary = content.map { content in
                Self.event(for: sample, key: .active(type: content.sourceType, uuid: sample.uuid), exporter: exporter) {
                    record.companionParts(content: content, evidence: evidence)
                }
            }
            self.record = record
            self.content = content
            self.evidence = evidence
            self.primary = primary
            // A record that is refused outright reserves nothing for its symptoms either.
            self.symptoms = primary == nil ? [] : record.symptoms.map { symptom in
                ExchangeEventKey.active(symptom).map { Self.event(for: symptom, key: $0, exporter: exporter) { [] } }
            }
        }

        /// The event of `sample` under `key`: fingerprinted with what the policies answer for the sample and with
        /// `companionParts`.
        private static func event(
            for sample: HKSample,
            key: ExchangeEventKey,
            exporter: HealthKitFHIRExporter,
            companionParts: () -> [String]
        ) -> Event {
            let policies = ResolvedPolicies(sample, options: exporter.options)
            return Event(request: exporter.context.request(for: key, recordParts: policies.fingerprintParts + companionParts()), policies: policies)
        }
    }

    /// What one record's delivery hands over: its exports, and what building them took when measured.
    struct Delivery: Sendable {
        let exports: [Export]
        /// Building the record's graphs, validation included; zero unless measured.
        let building: Swift.Duration
        /// Validating them; zero unless measured.
        let validation: Swift.Duration
    }

    /// The exports of one planned record, built without the caller: refusals in place, graphs otherwise.
    private func build(
        _ plan: Plan,
        reserved: [ExchangeEventRequest: ExchangeEventReservation],
        measuring: Bool
    ) -> Delivery {
        let start = measuring ? ContinuousClock.now : nil
        func delivery(_ exports: [Export], validation: Swift.Duration = .zero) -> Delivery {
            Delivery(exports: exports, building: start.map { ContinuousClock.now - $0 } ?? .zero, validation: validation)
        }
        guard let primary = plan.primary, let content = plan.content else {
            let refusal = HealthKitConversionError.unregisteredSourceType(plan.record.sample.sampleType.identifier)
            return delivery([Export(source: plan.source, outcome: .refused(refusal), warnings: [])])
        }
        guard plan.requests.allSatisfy({ reserved[$0] != nil }) else {
            // An earlier input of this call named one of its records with other content and holds that key's event.
            return delivery([Export(source: plan.source, outcome: .refused(.conflictingDuplicate), warnings: [])])
        }
        // A refusal keeps its reservations held: they are released with the receipt, never mid-call, so a
        // standalone export of the same record in this call keeps its event.
        do {
            let conversions = try convert(plan, content: content, primary: primary, reserved: reserved)
            // A policy that chose to emit nothing (an unauthorized route) leaves no conversion; that is not a refusal
            // and never warns.
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

    private func reservation(
        for request: ExchangeEventRequest,
        in reserved: [ExchangeEventRequest: ExchangeEventReservation]
    ) -> ExchangeEventReservation {
        guard let reservation = reserved[request] else {
            preconditionFailure("Every planned request is reserved in the same call.")
        }
        return reservation
    }

    private func convert(
        _ plan: Plan,
        content: HealthKitContentPlan,
        primary: Plan.Event,
        reserved: [ExchangeEventRequest: ExchangeEventReservation]
    ) throws -> [HealthKitAssembly.Conversion] {
        let request = try assemblyRequest(
            for: plan.record.sample,
            policies: primary.policies,
            reservation: reservation(for: primary.request, in: reserved)
        )
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
                symptomRequests: symptomRequests(plan, reserved: reserved)
            )
        case let .heartbeatSeries(series, beats):
            return try assembly.convertHeartbeatSeries(series, beats: beats, plan: content, request: request)
        case let .workoutRoute(route, locations):
            return try assembly.convertWorkoutRoute(route, locations: locations, plan: content, request: request)
        }
    }

    /// Each registered symptom's request under its own reservation, looked up by its request, never by position.
    private func symptomRequests(
        _ plan: Plan,
        reserved: [ExchangeEventRequest: ExchangeEventReservation]
    ) throws -> [UUID: HealthKitAssembly.Request] {
        var requests: [UUID: HealthKitAssembly.Request] = [:]
        for (symptom, event) in zip(plan.record.symptoms, plan.symptoms) {
            guard let event, requests[symptom.uuid] == nil else {
                continue
            }
            requests[symptom.uuid] = try assemblyRequest(
                for: symptom,
                policies: event.policies,
                reservation: reservation(for: event.request, in: reserved)
            )
        }
        return requests
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What the assembly builds one record's graph from: its event under `reservation`, the facts frozen with it, and
    /// the answers the policies resolved for its sample before the reservation, which its fingerprint covers. Not the
    /// ledger request (`ExchangeRequestContext.request(for:recordParts:)`), which that reservation answered.
    func assemblyRequest(
        for sample: HKSample,
        policies: ResolvedPolicies,
        reservation: ExchangeEventReservation
    ) throws -> HealthKitAssembly.Request {
        HealthKitAssembly.Request(
            event: try ExchangeEventIdentifier(
                system: producer.identityScope.systems.event,
                producerInstance: reservation.producerInstance,
                sequence: reservation.sequence
            ),
            instant: reservation.instant,
            facts: reservation.facts,
            // The gateway role compares the sample's revision with the build the event froze.
            converterRole: options.role.converterRole(for: sample.sourceRevision, application: reservation.facts.application),
            bundleID: try bundleID(for: sample.uuid),
            policies: policies
        )
    }

    /// The `Bundle.id` of the record with `uuid` under ``Options/legacyBundleID``.
    func bundleID(for uuid: UUID) throws -> RepositoryID? {
        switch options.legacyBundleID {
        case .none:
            nil
        default:
            try RepositoryID(uuid.uuidString)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Record {
    /// The correlated symptoms, each its own event.
    var symptoms: [HKCategorySample] {
        guard case .electrocardiogram(_, _, let symptoms) = self else {
            return []
        }
        return symptoms
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ExchangeEventKey {
    /// The active-event key of a HealthKit sample: its source type and UUID, nothing else.
    static func active(_ sample: HKSample) -> ExchangeEventKey? {
        HealthKitContentPlan.plan(for: sample).map { active(type: $0.sourceType, uuid: sample.uuid) }
    }

    /// The active-event key of the record of `type` with `uuid`.
    static func active(type: HealthKitSourceType, uuid: UUID) -> ExchangeEventKey {
        ExchangeEventKey(
            kind: .active,
            adapterID: HealthKitAssembly.adapter.adapterID,
            sourceRecord: "\(type.rawValue)|\(uuid.uuidString.lowercased())"
        )
    }
}

#endif
