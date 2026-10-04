//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


/// Turns SensorKit records you already fetched into exchange graphs for one deployment, participant and installation.
///
/// Configure it once and keep it for as long as its `ExchangeProducer` is valid; it is safe to share across tasks.
/// Every export mints its events through the producer, in one ledger transaction per call, so an exact redelivery
/// before `ExchangeProducer.Receipt.release()` reproduces the same events byte for byte, even when the application,
/// the host or the studies changed in between. A record that cannot be converted is reported as a refusal instead of
/// ending the call. The exporter never queries SensorKit.
///
/// A ``SensorKitSourceRecordID`` names one acquisition, not one content: verify a retried record's source bytes
/// against the digest you persisted at its acquisition coordinate before you export it again (see
/// ``SensorKitSourceRecordID``). The exporter adds a second line behind that guard: other content under a reserved
/// record becomes a new event, never a restated one.
public final class SensorKitFHIRExporter: Sendable {
    /// Why an exporter could not be configured.
    public enum ConfigurationError: Error, Equatable, Sendable {
        /// The visit-location or the disclosed native identifier's system is one of the deployment's own identity
        /// systems.
        case reservedIdentifierSystem(IdentifierSystem)
    }

    /// What the exporter discloses beyond the opaque identities every graph carries.
    public struct Options: Sendable {
        /// Discloses the exact ``SensorKitSourceRecordID`` on each graph's designated primary output under a system
        /// you own; omitted by default. Grove's opaque identifiers stay the only graph keys.
        public var nativeIdentifier: GovernedSourceIdentifierDisclosurePolicy = .omit

        public init() {}
    }

    /// What one record produced: an exchange graph, or the reason it produced none.
    public struct Export: Sendable {
        public enum Outcome: Sendable {
            /// The validated graph; store or upload `ExchangeGraph.json` verbatim.
            case graph(ExchangeGraph)
            /// The record was refused; nothing was emitted and the export continued. Refusals are deterministic,
            /// so an exact redelivery refuses identically.
            case refused(SensorKitConversionError)
        }

        /// The record's identity at its acquisition coordinate; it stays on the device unless
        /// ``Options/nativeIdentifier`` discloses it.
        public let source: SensorKitSourceRecordID
        public let outcome: Outcome

        /// The graph, when one was produced.
        public var graph: ExchangeGraph? {
            if case .graph(let graph) = outcome { graph } else { nil }
        }
    }

    let producer: ExchangeProducer
    /// The namespace of the exact `SRVisit.locationId`, which the guide requires on every visit that names one.
    let visitLocationIdentifierSystem: IdentifierSystem
    let options: Options
    /// The producer's scope over this installation's SensorKit store; each graph's envelope adds its event's facts.
    let scope: ExchangeEnvelope.Scope
    /// What shapes every graph beside the frozen facts and the record; it fingerprints each request.
    let context: ExchangeRequestContext

    /// Creates the exporter of one installation's SensorKit store.
    ///
    /// - Parameters:
    ///   - producer: The producer whose ledger numbers every event and freezes what each one states.
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
        self.context = ExchangeRequestContext(
            label: "grove-sensorkit-context-v0",
            outputRevisions: [ExchangeGraphAssembler.outputRevision, SensorKitConverter.outputRevision],
            producer: producer,
            repositoryScope: repositoryScope,
            settings: [("visitLocationIdentifierSystem", [visitLocationIdentifierSystem.rawValue])] + options.fingerprintParts
        )
    }

    /// Converts records in input order, calling `receive` once per record with its graph or its refusal.
    ///
    /// A record that cannot be converted is refused in place, and so is a record the call names again with other
    /// content (``SensorKitConversionError/conflictingDuplicate``): the first input of a record keeps its event, so
    /// an exact retry of the call reproduces every event. Only these end the call:
    /// - an `instant` no FHIR instant can state (before year 1 or after year 9999) throws
    ///   `ExchangeIdentityError.invalidInstant` before the ledger is touched;
    /// - the producer's ledger throws `ExchangeProducer.LedgerError` when a stored entry is corrupt or from a later
    ///   layout, and `ExchangeProducer.resetLedger()` always recovers;
    /// - errors of the ledger's storage and of `receive` are rethrown unchanged, and the reservations made stay for
    ///   the redelivery.
    ///
    /// - Parameters:
    ///   - records: The records of one fetched batch.
    ///   - sourceTimeZone: The zone the source reported the batch's instants in; every effective bound states its
    ///     offset. Persist it with the batch, so a redelivery states the same bounds.
    ///   - recordingDevice: The physical unit that measured the batch; the graphs name no recording Device without one.
    ///   - instant: When the events are reserved; a redelivery before the receipt is released keeps the first one.
    ///   - receive: Called once per record, in input order.
    /// - Returns: The receipt to release once every graph is durably stored and the batch acknowledged.
    public func export(
        _ records: some Collection<SensorKitRecord>,
        sourceTimeZone: TimeZone,
        recordingDevice: RecordingDevice? = nil,
        at instant: Date = .now,
        receive: (Export) throws -> Void
    ) throws -> ExchangeProducer.Receipt {
        let content = SensorKitConverter.ContentContext(
            sourceTimeZone: sourceTimeZone,
            visitLocationIdentifierSystem: visitLocationIdentifierSystem
        )
        let device = recordingDevice.map(SensorKitConverter.recordingDevice)
        let plans = records.map { Plan($0, content: content, recordingDevice: device, exporter: self) }
        // One fingerprint per key and call, the first in input order: a key reserved under two would keep only the
        // later, and a retry of the call would mint both again.
        let firstPerKey = Dictionary(plans.compactMap { try? $0.content.get().request }.map { ($0.key, $0) }) { first, _ in first }
        // Refusals alone need no event, and a call that reserves nothing never touches the ledger.
        let (reserved, receipt) = try producer.reserve(Set(firstPerKey.values), at: instant)
        for plan in plans {
            try receive(Export(source: plan.source, outcome: deliver(plan, reserved: reserved)))
        }
        return receipt
    }
}


extension SensorKitFHIRExporter {
    /// One record prepared before the reservation: its event-independent content and the request that content
    /// reserves, or why it has none.
    struct Plan {
        struct Content {
            let sourceRecord: SourceRecordIdentity
            let outputs: [ExchangeOutputDraft]
            let recordingDevice: ExchangeRecordingDeviceDraft?
            let request: ExchangeEventRequest
        }

        let source: SensorKitSourceRecordID
        let content: Result<Content, SensorKitConversionError>

        init(
            _ record: SensorKitRecord,
            content context: SensorKitConverter.ContentContext,
            recordingDevice: ExchangeRecordingDeviceDraft?,
            exporter: SensorKitFHIRExporter
        ) {
            self.source = record.sourceRecordID
            do {
                let sourceRecord = try exporter.scope.sourceRecord(sourceType: record.sourceToken, nativeRecordID: record.sourceRecordID.value)
                let outputs = try SensorKitConverter.outputs(
                    of: record,
                    sourceRecord: sourceRecord,
                    nativeIdentifier: exporter.options.nativeIdentifier.identifier(for: record.sourceRecordID.value),
                    context: context
                )
                let key = ExchangeEventKey(
                    kind: .active,
                    adapterID: SensorKitConverter.adapterID,
                    sourceRecord: "\(record.sourceToken)|\(record.sourceRecordID.value)"
                )
                let parts = try Self.contentParts(outputs: outputs, recordingDevice: recordingDevice)
                self.content = .success(Content(
                    sourceRecord: sourceRecord,
                    outputs: outputs,
                    recordingDevice: recordingDevice,
                    request: exporter.context.request(for: key, recordParts: parts)
                ))
            } catch {
                self.content = .failure(SensorKitConversionError(conversionFailure: error))
            }
        }
    }

    /// The planned record's graph under its reservation, or why it has none. A refusal keeps its reservation held: it
    /// is released with the receipt, never mid-call.
    private func deliver(_ plan: Plan, reserved: [ExchangeEventRequest: ExchangeEventReservation]) -> Export.Outcome {
        let content: Plan.Content
        switch plan.content {
        case .failure(let refusal):
            return .refused(refusal)
        case .success(let planned):
            content = planned
        }
        guard let reservation = reserved[content.request] else {
            // An earlier record of this call has the same source-record identifier, other content, and that key's event.
            return .refused(.conflictingDuplicate)
        }
        do {
            let draft = ExchangeGraphDraft(
                event: try ExchangeEventIdentifier(
                    system: producer.identityScope.systems.event,
                    producerInstance: reservation.producerInstance,
                    sequence: reservation.sequence
                ),
                instant: reservation.instant,
                sourceRecord: content.sourceRecord,
                outputs: content.outputs,
                recordingDevice: content.recordingDevice
            )
            let envelope = ExchangeEnvelope(scope: scope, facts: reservation.facts)
            return .graph(try ExchangeGraphAssembler(envelope: envelope).assemble(draft).graph)
        } catch {
            return .refused(SensorKitConversionError(conversionFailure: error))
        }
    }
}
