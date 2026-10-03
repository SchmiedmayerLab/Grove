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
/// Configure it once and keep it for as long as its ``ExchangeProducer`` is valid; it is safe to share
/// across tasks. Every export mints the events itself through the producer's sequencer, so an exact
/// redelivery before ``Receipt/release()`` reproduces the same events, and a sample that cannot be
/// converted is reported as a refusal instead of ending the call. The exporter never queries HealthKit:
/// companion data such as ECG voltages arrives through ``Record``.
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
        self.repositoryScope = repositoryScope
        self.options = options
    }

    /// Converts samples in input order, calling `receive` once per produced graph or refusal as soon as
    /// it is ready. Only the sequencer's storage and `receive` itself can end the call early; their
    /// errors are rethrown unchanged.
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
        let plans = records.map(Plan.init)
        let keys = plans.flatMap(\.keys)
        // Nothing reserved means the ledger is never touched; refusals alone need no producer instance.
        let reservations = keys.isEmpty ? [] : try producer.sequencer.reserve(keys, at: instant)
        let producerInstance = keys.isEmpty ? UUID() : try producer.sequencer.producerInstance
        var offset = 0
        for plan in plans {
            let reserved = Array(reservations[offset..<(offset + plan.keys.count)])
            offset += plan.keys.count
            try autoreleasepool {
                try deliver(plan, reservations: reserved, producerInstance: producerInstance, receive: receive)
            }
        }
        return Receipt(keys: keys, sequencer: producer.sequencer)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// One record and the event keys it needs: one for itself, one per ECG symptom.
    struct Plan {
        let record: Record
        let keys: [ExchangeEventKey]
        let refusal: HealthKitConversionError?

        var source: Export.Source {
            Export.Source(uuid: record.sample.uuid, typeIdentifier: record.sample.sampleType.identifier)
        }
    }

    private func deliver(
        _ plan: Plan,
        reservations: [ExchangeEventReservation],
        producerInstance: UUID,
        receive: (Export) throws -> Void
    ) throws {
        if let refusal = plan.refusal {
            try receive(Export(source: plan.source, outcome: .refused(refusal), warnings: []))
            return
        }
        let set: HealthKitConversionSet?
        do {
            set = try convert(plan.record, reservations: reservations, producerInstance: producerInstance)
        } catch {
            let failure = HealthKitConversionError(conversionFailure: error, source: plan.source.sourceType)
            producer.sequencer.releaseIgnoringErrors(plan.keys)
            try receive(Export(source: plan.source, outcome: .refused(failure), warnings: []))
            return
        }
        guard let set else {
            // A policy chose to emit nothing (an unauthorized route); that is not a refusal and never warns.
            producer.sequencer.releaseIgnoringErrors(plan.keys)
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

    private func convert(
        _ record: Record,
        reservations: [ExchangeEventReservation],
        producerInstance: UUID
    ) throws -> HealthKitConversionSet? {
        let context = try conversionContext(for: record.sample, reservation: reservations[0], producerInstance: producerInstance)
        switch record {
        case .sample(let sample):
            return try HealthKitConverter.convertSample(sample, context: context)
        case let .electrocardiogram(ecg, voltages, symptoms):
            let symptomContexts = try zip(symptoms, reservations.dropFirst()).map { symptom, reservation in
                try conversionContext(for: symptom, reservation: reservation, producerInstance: producerInstance)
            }
            let ecgRecord = HealthKitECGRecord(electrocardiogram: ecg, voltageMeasurements: voltages, correlatedSymptoms: symptoms)
            return try HealthKitConverter.convertECG(ecgRecord, context: context, symptomContexts: symptomContexts)
        case let .heartbeatSeries(series, beats):
            return try HealthKitConverter.convertHeartbeatSeries(
                HealthKitHeartbeatSeriesRecord(series: series, heartbeats: beats),
                context: context
            )
        case let .workoutRoute(route, locations):
            return try HealthKitConverter.convertWorkoutRoute(
                HealthKitWorkoutRouteRecord(route: route, locations: locations),
                context: context
            )
        }
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
extension HealthKitFHIRExporter.Plan {
    init(_ record: HealthKitFHIRExporter.Record) {
        self.record = record
        var keys: [ExchangeEventKey] = []
        if let key = ExchangeEventKey.active(record.sample) {
            keys.append(key)
        }
        if case .electrocardiogram(_, _, let symptoms) = record {
            keys += symptoms.compactMap(ExchangeEventKey.active)
        }
        self.keys = keys
        self.refusal = keys.isEmpty ? .unregisteredSourceType(record.sample.sampleType.identifier) : nil
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// The per-event conversion inputs, in the shape the conversion pipeline still takes.
    func conversionContext(
        for sample: HKSample,
        reservation: ExchangeEventReservation,
        producerInstance: UUID
    ) throws -> HealthKitConversionContext {
        let source = sample.sourceRevision.source
        let event = ExchangeEventContext(
            subject: producer.subject,
            event: try ExchangeEventIdentifier(
                system: producer.identityScope.systems.event,
                producerInstance: producerInstance,
                sequence: reservation.sequence
            ),
            identityScope: producer.identityScope,
            repositoryScope: repositoryScope,
            application: producer.application,
            host: producer.host,
            conversionInstant: reservation.instant,
            converterRole: options.role.converterRole(for: source, application: producer.application),
            studies: producer.studies,
            repositoryIDs: try legacyRepositoryIDs(for: sample.uuid)
        )
        let conversionOptions = HealthKitConversionOptions(
            writer: options.writer.classification(of: source),
            recordingDevice: options.recordingDevice.resolver,
            udiDisclosure: options.udi == .authorized ? .authorizedUDI : .omit,
            routeDisclosure: options.route == .authorized ? .authorized : .omit,
            nativeIdentifierDisclosure: options.nativeIdentifier
        )
        return HealthKitConversionContext(event: event, options: conversionOptions)
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
        guard let type = HealthKitSourceType(sample) else {
            return nil
        }
        return ExchangeEventKey(
            kind: .active,
            adapterID: HealthKitConverter.adapterID,
            sourceRecord: "\(type.rawValue)|\(sample.uuid.uuidString.lowercased())"
        )
    }
}

#endif
