//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


/// Turns SensorKit records you already fetched into exchange records for one deployment, participant and installation.
///
/// Configure it once and keep it for as long as its `ExchangeProducer` is valid; it is safe to share across tasks. A
/// record that cannot be converted is reported as a refusal instead of ending the call. The exporter never queries
/// SensorKit.
///
/// A ``SensorKitSourceRecordID`` names one acquisition, not one content: verify a retried record's source bytes
/// against the digest you persisted at its acquisition coordinate before you export it again (see
/// ``SensorKitSourceRecordID``). Other content at a coordinate is a new record version, never a restated one.
public final class SensorKitFHIRExporter: Sendable {
    /// Why an exporter could not be configured.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The visit-location or the disclosed native identifier's system is one of the deployment's own identity
        /// systems.
        case reservedIdentifierSystem(IdentifierSystem)
    }

    /// What the exporter discloses beyond the opaque identities every record carries.
    public struct Options: Sendable {
        /// Discloses the exact ``SensorKitSourceRecordID`` on each record's designated primary output under a system
        /// you own; omitted by default. Grove's opaque identifiers stay the only entry keys.
        public var nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit
        /// At most how many child tasks build one call's records at once; `nil`, the default, builds on one per active
        /// core, and `1` builds on the calling task alone. It changes how fast a call runs, never what it exports.
        public var maximumConcurrency: Int?

        public init() {}
    }

    /// What one input produced: an exchange record, or the reason it produced none.
    public struct Export: Sendable {
        public enum Outcome: Sendable {
            /// The validated record; stage `ExchangeRecord.json` verbatim, and pack it for upload.
            case record(ExchangeRecord)
            /// The record was refused; nothing was emitted and the export continued. Refusals are deterministic,
            /// so an exact redelivery refuses identically.
            case refused(SensorKitConversionError)
        }

        /// The record's identity at its acquisition coordinate; it stays on the device unless
        /// ``Options/nativeIdentifier`` discloses it.
        public let source: SensorKitSourceRecordID
        public let outcome: Outcome

        /// The record, when one was produced.
        public var record: ExchangeRecord? {
            if case .record(let record) = outcome { record } else { nil }
        }
    }

    let producer: ExchangeProducer
    /// The namespace of the exact `SRVisit.locationId`, which the guide requires on every visit that names one.
    let visitLocationIdentifierSystem: IdentifierSystem
    let options: Options
    /// The producer's scope over this installation's SensorKit store.
    let scope: ExchangeEnvelope.Scope

    /// Creates the exporter of one installation's SensorKit store.
    ///
    /// - Parameters:
    ///   - producer: The producer every record states.
    ///   - repositoryScope: The business identifier naming this installation's SensorKit store; it enters every
    ///     source identity.
    ///   - visitLocationIdentifierSystem: A system your deployment owns for the exact `SRVisit.locationId`, which a
    ///     visit's Observation states on its focus whenever the source names a location.
    ///   - options: What the exporter discloses.
    public init(
        producer: ExchangeProducer,
        repositoryScope: BusinessIdentifier,
        visitLocationIdentifierSystem: IdentifierSystem,
        options: Options = Options()
    ) throws(ConfigurationError) {
        let reserved = producer.identityScope.systems.all
        guard !reserved.contains(visitLocationIdentifierSystem) else {
            throw .reservedIdentifierSystem(visitLocationIdentifierSystem)
        }
        if case .authorized(let system, _) = options.nativeIdentifier, reserved.contains(system) {
            throw .reservedIdentifierSystem(system)
        }
        self.producer = producer
        self.visitLocationIdentifierSystem = visitLocationIdentifierSystem
        self.options = options
        self.scope = ExchangeEnvelope.Scope(
            adapter: SensorKitConverter.adapter,
            identityScope: producer.identityScope,
            subject: producer.subject,
            repositoryScope: repositoryScope
        )
    }

    /// Converts records in input order, calling `receive` once per record with its exchange record or its refusal.
    ///
    /// A record that cannot be converted is refused in place. Only these end the call:
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant`;
    /// - errors of `receive` are rethrown unchanged.
    ///
    /// - Parameters:
    ///   - records: The records of one fetched batch.
    ///   - sourceTimeZone: The zone the source reported the batch's instants in; every effective bound states its
    ///     offset. Persist it with the batch, so a redelivery states the same bounds.
    ///   - recordingDevice: The `SRDevice` that recorded the batch, as `RecordingDevice(batch.info.device)` states it. A
    ///     Recording Document names it as its author; pass `nil` only when the source does not state the hardware.
    ///   - sourceDevices: The peripherals that supplied the batch, as `batch.info.sourceDevices` states them. Each becomes a
    ///     recording Device that every record of the call names as its source entity's performer, with `recordingDevice`
    ///     as the composer, since SensorKit states them per batch: split a batch across calls to state a record's own
    ///     peripheral.
    ///   - sourceDevicesSuppliedEverySample: Whether the peripherals supplied every sample of the batch, as
    ///     `batch.info.sourceDevicesSuppliedEverySample` states it. With exactly one peripheral, an Observation then names
    ///     it as its device; otherwise it names `recordingDevice`. Persist it with the batch, so a redelivery repeats every
    ///     record version.
    ///   - instant: The conversion instant. Persist it with the batch, so a redelivery repeats every record version.
    ///   - receive: Called once per record, in input order.
    nonisolated(nonsending) public func export(
        _ records: some Collection<SensorKitRecord>,
        sourceTimeZone: TimeZone,
        recordingDevice: RecordingDevice?,
        sourceDevices: [RecordingDevice] = [],
        sourceDevicesSuppliedEverySample: Bool = false,
        at instant: Date,
        receive: (Export) throws -> Void
    ) async throws {
        guard (try? ExchangeInstant.fhirInstant(instant)) != nil else {
            throw ExchangeIdentityError.invalidInstant
        }
        let content = SensorKitConverter.ContentContext(
            sourceTimeZone: sourceTimeZone,
            visitLocationIdentifierSystem: visitLocationIdentifierSystem
        )
        let width = options.maximumConcurrency ?? ConcurrentBuild.defaultWidth
        let plans = await ConcurrentBuild.map(Array(records)[...], width: width) { record in
            Plan(record, content: content, exporter: self)
        }
        try await ConcurrentBuild.forEach(plans, width: width) { plan in
            self.deliver(
                plan,
                recordingDevice: recordingDevice,
                sourceDevices: sourceDevices,
                sourceDevicesSuppliedEverySample: sourceDevicesSuppliedEverySample,
                at: instant
            )
        } hand: { plan, outcome in
            try receive(Export(source: plan.source, outcome: outcome))
        }
    }
}


extension SensorKitFHIRExporter {
    /// One record prepared before it is built: its content, or why it has none.
    struct Plan {
        struct Content {
            let sourceRecord: SourceRecordIdentity
            let outputs: [ExchangeOutputDraft]
        }

        let source: SensorKitSourceRecordID
        let content: Result<Content, SensorKitConversionError>

        init(_ record: SensorKitRecord, content context: SensorKitConverter.ContentContext, exporter: SensorKitFHIRExporter) {
            self.source = record.sourceRecordID
            do {
                let sourceRecord = try exporter.scope.sourceRecord(sourceType: record.sourceToken, nativeRecordID: record.sourceRecordID.value)
                let outputs = try SensorKitConverter.outputs(
                    of: record,
                    sourceRecord: sourceRecord,
                    nativeIdentifier: exporter.options.nativeIdentifier.identifier(for: record.sourceRecordID.value),
                    context: context
                )
                self.content = .success(Content(sourceRecord: sourceRecord, outputs: outputs))
            } catch {
                self.content = .failure(SensorKitConversionError(conversionFailure: error))
            }
        }
    }

    /// The planned record, or why it has none.
    private func deliver(
        _ plan: Plan,
        recordingDevice: RecordingDevice?,
        sourceDevices: [RecordingDevice],
        sourceDevicesSuppliedEverySample: Bool,
        at instant: Date
    ) -> Export.Outcome {
        let content: Plan.Content
        switch plan.content {
        case .failure(let refusal):
            return .refused(refusal)
        case .success(let planned):
            content = planned
        }
        do {
            let draft = ExchangeRecordDraft(
                instant: instant,
                sourceRecord: content.sourceRecord,
                outputs: content.outputs,
                recordingDevice: recordingDevice,
                sourceDevices: sourceDevices,
                sourceDevicesSuppliedEverySample: sourceDevicesSuppliedEverySample
            )
            let envelope = ExchangeEnvelope(scope: scope, facts: producer.facts)
            return .record(try ExchangeGraphAssembler(envelope: envelope).assemble(draft).record)
        } catch {
            return .refused(SensorKitConversionError(conversionFailure: error))
        }
    }
}
