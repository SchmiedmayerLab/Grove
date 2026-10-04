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
/// across tasks. Every export mints the events itself through the producer's sequencer, in one ledger
/// transaction per call, so an exact redelivery before ``Receipt/release()`` reproduces the same events
/// byte for byte, even when the application, the host or the studies changed in between. A sample that
/// cannot be converted is reported as a refusal instead of ending the call. The exporter never queries
/// HealthKit: companion data such as ECG voltages arrives through ``Record``.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class HealthKitFHIRExporter: Sendable {
    /// Why an exporter could not be configured.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The disclosed native identifier's system is one of the deployment's own identity systems.
        case reservedNativeIdentifierSystem(IdentifierSystem)
    }

    public let producer: ExchangeProducer
    /// The business identifier naming this installation's HealthKit store; it enters every source identity.
    public let repositoryScope: BusinessIdentifier
    public let options: Options
    let assembly: HealthKitAssembly
    /// What shapes every graph beside the frozen facts; it fingerprints each request.
    let context: ExportContext

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
        self.assembly = HealthKitAssembly(scope: ExchangeEnvelope.Scope(
            adapter: HealthKitAssembly.adapter,
            identityScope: producer.identityScope,
            subject: producer.subject,
            repositoryScope: repositoryScope
        ))
        self.context = ExportContext(producer: producer, repositoryScope: repositoryScope, options: options, revisions: outputRevisions)
    }

    /// Converts samples in input order, calling `receive` once per produced graph or refusal as soon as
    /// it is ready.
    ///
    /// A record that cannot be converted is refused in place, and so is a record the call names again with
    /// other content (``HealthKitConversionError/conflictingDuplicate``): the first input of a record keeps
    /// its event, so an exact retry of the call reproduces every event. Only these end the call:
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant` before the ledger is touched;
    /// - the producer's ledger throws `ExchangeEventSequencer.LedgerError` when a stored entry is corrupt or
    ///   from a later layout, and `ExchangeEventSequencer.reset()` always recovers;
    /// - errors of the ledger's storage and of `receive` are rethrown unchanged, and the reservations made
    ///   stay for the redelivery.
    public func export<Samples: Collection>(
        _ samples: Samples,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> Receipt where Samples.Element: HKSample {
        try export(records: samples.map { Record.sample($0) }, at: instant, receive: receive)
    }

    /// ``export(_:at:receive:)`` for records that carry companion data.
    public func export(
        records: some Collection<Record>,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> Receipt {
        try export(inputs: records.map(Input.record), at: instant, receive: receive)
    }

    /// One reserve transaction for every event the inputs need, then each input's delivery in order.
    func export(inputs: [Input], at instant: Date, receive: (Export) throws -> Void) throws -> Receipt {
        let plans = inputs.map { Plan($0, context: context) }
        // One fingerprint per key and call, the first in input order: a key reserved under two would keep only the
        // later, and a retry of the call would mint both again.
        let firstPerKey = Dictionary(plans.flatMap(\.requests).map { ($0.key, $0) }) { first, _ in first }
        let requests = Set(firstPerKey.values)
        // Nothing reserved means the ledger is never touched; refusals alone need no event.
        let reserved = requests.isEmpty ? [:] : try producer.reserve(requests, at: instant)
        // Created before any delivery: when a delivery throws, the receipt is dropped and its holds lapse.
        let receipt = Receipt(sequencer: producer.sequencer, held: reserved.values.map(\.handle), forgetting: [])
        for plan in plans {
            try autoreleasepool {
                try deliver(plan, reserved: reserved, receive: receive)
            }
        }
        return receipt
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What one delivery converts: a record, or, below the public API, an ECG whose evidence is already validated.
    enum Input {
        case record(Record)
        /// An ECG with prebuilt evidence: the seam tests use, as `HKElectrocardiogram.VoltageMeasurement`
        /// cannot be constructed with values outside HealthKit.
        case electrocardiogramEvidence(HKSample, evidence: HealthKitECGEvidence, symptoms: [HKCategorySample])

        var sample: HKSample {
            switch self {
            case .record(let record): record.sample
            case .electrocardiogramEvidence(let ecg, _, _): ecg
            }
        }

        /// The correlated symptoms, each its own event.
        var symptoms: [HKCategorySample] {
            switch self {
            case .record(.electrocardiogram(_, _, let symptoms)), .electrocardiogramEvidence(_, _, let symptoms): symptoms
            case .record: []
            }
        }

        /// What the record's event key does not version but its graph embeds: an ECG references its
        /// symptoms' output identifiers, so their set enters the fingerprint.
        var recordParts: [String] {
            switch self {
            case .record(.electrocardiogram), .electrocardiogramEvidence:
                symptoms.map { $0.uuid.uuidString.lowercased() }.sorted()
            case .record:
                []
            }
        }
    }

    /// One input and the requests it needs: one for its record, one per registered ECG symptom.
    struct Plan {
        let input: Input
        let primary: ExchangeEventRequest?
        /// One entry per correlated symptom, in the record's order; `nil` for a symptom of an unregistered type.
        let symptoms: [ExchangeEventRequest?]

        var requests: [ExchangeEventRequest] {
            [primary].compactMap(\.self) + symptoms.compactMap(\.self)
        }

        var source: Export.Source {
            Export.Source(uuid: input.sample.uuid, typeIdentifier: input.sample.sampleType.identifier)
        }

        init(_ input: Input, context: ExportContext) {
            let primary = ExchangeEventKey.active(input.sample).map { context.request(for: $0, recordParts: input.recordParts) }
            self.input = input
            self.primary = primary
            // A record that is refused outright reserves nothing for its symptoms either.
            self.symptoms = primary == nil ? [] : input.symptoms.map { symptom in
                ExchangeEventKey.active(symptom).map { context.request(for: $0) }
            }
        }
    }

    private func deliver(
        _ plan: Plan,
        reserved: [ExchangeEventRequest: ExchangeEventReservation],
        receive: (Export) throws -> Void
    ) throws {
        guard let primary = plan.primary else {
            let refusal = HealthKitConversionError.unregisteredSourceType(plan.input.sample.sampleType.identifier)
            try receive(Export(source: plan.source, outcome: .refused(refusal), warnings: []))
            return
        }
        guard plan.requests.allSatisfy({ reserved[$0] != nil }) else {
            // An earlier input of this call named one of its records with other content and holds that key's event.
            try receive(Export(source: plan.source, outcome: .refused(.conflictingDuplicate), warnings: []))
            return
        }
        // A refusal keeps its reservations held: they are released with the receipt, never mid-call, so a
        // standalone export of the same record in this call keeps its event.
        let set: HealthKitConversionSet?
        do {
            set = try convert(plan, primary: reservation(for: primary, in: reserved), reserved: reserved)
        } catch {
            let failure = HealthKitConversionError(conversionFailure: error, source: plan.source.sourceType)
            try receive(Export(source: plan.source, outcome: .refused(failure), warnings: []))
            return
        }
        guard let set else {
            // A policy chose to emit nothing (an unauthorized route); that is not a refusal and never warns.
            return
        }
        for conversion in set.all {
            try receive(Export(
                source: Export.Source(uuid: conversion.source.uuid, typeIdentifier: conversion.source.type.rawValue),
                outcome: .graph(conversion.graph),
                warnings: reportableWarnings(conversion.warnings)
            ))
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
        primary: ExchangeEventReservation,
        reserved: [ExchangeEventRequest: ExchangeEventReservation]
    ) throws -> HealthKitConversionSet? {
        let request = try request(for: plan.input.sample, reservation: primary)
        switch plan.input {
        case .record(.sample(let sample)):
            return try assembly.convert(sample, request: request)
        case let .record(.electrocardiogram(ecg, voltages, symptoms)):
            let ecgRecord = HealthKitECGRecord(electrocardiogram: ecg, voltageMeasurements: voltages, correlatedSymptoms: symptoms)
            return try assembly.convertECG(ecgRecord, request: request, symptomRequests: symptomRequests(plan, reserved: reserved))
        case let .record(.heartbeatSeries(series, beats)):
            return try assembly.convertHeartbeatSeries(HealthKitHeartbeatSeriesRecord(series: series, heartbeats: beats), request: request)
        case let .record(.workoutRoute(route, locations)):
            return try assembly.convertWorkoutRoute(HealthKitWorkoutRouteRecord(route: route, locations: locations), request: request)
        case let .electrocardiogramEvidence(ecg, evidence, symptoms):
            return try assembly.convertECG(
                ecg,
                evidence: evidence,
                symptoms: symptoms,
                request: request,
                symptomRequests: symptomRequests(plan, reserved: reserved)
            )
        }
    }

    /// Each registered symptom's request under its own reservation, looked up by its request, never by position.
    private func symptomRequests(
        _ plan: Plan,
        reserved: [ExchangeEventRequest: ExchangeEventReservation]
    ) throws -> HealthKitAssembly.SymptomRequests {
        var requests: [UUID: HealthKitAssembly.Request] = [:]
        for (symptom, planned) in zip(plan.input.symptoms, plan.symptoms) {
            guard let planned, requests[symptom.uuid] == nil else {
                continue
            }
            requests[symptom.uuid] = try request(for: symptom, reservation: reservation(for: planned, in: reserved))
        }
        return .keyed(requests)
    }

    /// An omission a policy chose is never reported.
    private func reportableWarnings(_ warnings: [HealthKitConversionWarning]) -> [ProducerDiagnostic] {
        warnings.compactMap { warning in
            if case .recordingDeviceOmitted = warning, case .omit = options.recordingDevice {
                return nil
            }
            return warning.diagnostic
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// One record's event, the facts frozen with it, and the policies the options resolve for its source.
    func request(for sample: HKSample, reservation: ExchangeEventReservation) throws -> HealthKitAssembly.Request {
        let source = sample.sourceRevision.source
        return HealthKitAssembly.Request(
            event: try ExchangeEventIdentifier(
                system: producer.identityScope.systems.event,
                producerInstance: reservation.producerInstance,
                sequence: reservation.sequence
            ),
            instant: reservation.instant,
            facts: reservation.facts,
            // The gateway role compares the sample's revision with the build the event froze.
            converterRole: options.role.converterRole(for: sample.sourceRevision, application: reservation.facts.application),
            repositoryIDs: try legacyRepositoryIDs(for: sample.uuid),
            options: HealthKitConversionOptions(
                writer: options.writer.classification(of: source),
                recordingDevice: options.recordingDevice.resolver,
                udiDisclosure: options.udi == .authorized ? .authorizedUDI : .omit,
                routeDisclosure: options.route == .authorized ? .authorized : .omit,
                nativeIdentifierDisclosure: options.nativeIdentifier
            )
        )
    }

    func legacyRepositoryIDs(for uuid: UUID) throws -> [ExchangeGraphNode: RepositoryID] {
        switch options.legacyBundleID {
        case .none:
            [:]
        default:
            [.bundle: try RepositoryID(uuid.uuidString)]
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ExchangeEventKey {
    /// The active-event key of a HealthKit sample: its source type and UUID, nothing else.
    static func active(_ sample: HKSample) -> ExchangeEventKey? {
        HealthKitSourceType(sample).map { active(type: $0, uuid: sample.uuid) }
    }

    /// The active-event key of the record of `type` with `uuid`.
    static func active(type: HealthKitSourceType, uuid: UUID) -> ExchangeEventKey {
        ExchangeEventKey(
            kind: .active,
            adapterID: HealthKitConverter.adapterID,
            sourceRecord: "\(type.rawValue)|\(uuid.uuidString.lowercased())"
        )
    }
}

#endif
