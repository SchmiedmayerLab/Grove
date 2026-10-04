//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import CoreLocation
public import Foundation
public import GroveFHIRContract
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// One input of ``export(records:at:receive:)``: a sample, plus the companion data HealthKit keeps
    /// outside the sample for the kinds that need it. The exporter never queries HealthKit itself.
    public enum Record: Sendable {
        /// Any sample; an `HKElectrocardiogram` passed here is refused because its voltages are missing.
        case sample(HKSample)
        /// An electrocardiogram with its voltages and correlated symptom samples; each symptom becomes an
        /// event of its own.
        case electrocardiogram(HKElectrocardiogram, voltages: [HKElectrocardiogram.VoltageMeasurement], symptoms: [HKCategorySample])
        /// A heartbeat series with its beats, exported as a recording document.
        case heartbeatSeries(HKHeartbeatSeriesSample, beats: [HealthKitHeartbeat])
        /// A workout route with its locations, exported as a recording document only under
        /// ``Options/route`` `.authorized`.
        case workoutRoute(HKWorkoutRoute, locations: [CLLocation])

        var sample: HKSample {
            switch self {
            case .sample(let sample): sample
            case .electrocardiogram(let ecg, _, _): ecg
            case .heartbeatSeries(let series, _): series
            case .workoutRoute(let route, _): route
            }
        }
    }

    /// A deleted HealthKit object as the app noted it: HealthKit reports no deletion time, so the
    /// retraction states the bounds the app knows.
    public struct Deletion: Hashable, Sendable {
        public let uuid: UUID
        public let sourceType: HealthKitSourceType
        /// The start of the query that first reported the deletion, when known.
        public let deletedAfter: Date?
        /// When the app received the deletion.
        public let detectedAt: Date

        public init(uuid: UUID, sourceType: HealthKitSourceType, deletedAfter: Date?, detectedAt: Date) {
            self.uuid = uuid
            self.sourceType = sourceType
            self.deletedAfter = deletedAfter
            self.detectedAt = detectedAt
        }
    }

    /// What one record produced: an exchange graph, or the reason it produced none.
    public struct Export: Sendable {
        /// The record's coordinate in the HealthKit store. It stays on the device and is never on the wire
        /// unless ``Options/nativeIdentifier`` discloses it, or ``Options/legacyBundleID`` repeats its UUID as
        /// `Bundle.id`.
        public struct Source: Hashable, Sendable {
            public let uuid: UUID
            /// The HealthKit type identifier, such as `HKQuantityTypeIdentifierHeartRate`.
            public let typeIdentifier: String

            public var sourceType: HealthKitSourceType? { HealthKitSourceType(rawValue: typeIdentifier) }
        }

        public enum Outcome: Sendable {
            /// The validated graph; store or upload `ExchangeGraph.json` verbatim.
            case graph(ExchangeGraph)
            /// The record was refused; nothing was emitted and the export continued. Refusals are
            /// deterministic, so an exact redelivery refuses identically.
            case refused(HealthKitConversionError)
            /// A deletion that names no output this exporter can have emitted: a source type without outputs, or a
            /// workout route while ``Options/route`` is `.omit`. No event is reserved for it.
            case nothingToRetract
        }

        public let source: Source
        public let outcome: Outcome
        /// What the record carried that its graph does not; each is a registered omission rule.
        public let warnings: [ProducerDiagnostic]

        /// The graph, when one was produced.
        public var graph: ExchangeGraph? {
            if case .graph(let graph) = outcome { graph } else { nil }
        }
    }

    /// What an export or retraction reserved.
    ///
    /// Call ``release()`` once every produced graph is durably stored AND the source cursor (HealthKit anchor,
    /// bulk-export checkpoint) is committed. Until then an exact redelivery of the same records reproduces the
    /// same events, byte for byte. Releasing is idempotent, also across copies of this reference, and makes
    /// one ledger transaction at most. An export's receipt makes none when nothing was reserved, or while
    /// another call in this process still holds the same events. A retraction's receipt makes one whenever it
    /// names a deletion, as it also forgets each deleted record's active reservation.
    ///
    /// A receipt dropped unreleased (the call threw, or its commit action was discarded) leaves its
    /// reservations for the redelivery. When another call in this process released the same event, the last
    /// one to finish removes it, which may run one ledger transaction on the thread that drops the receipt. A
    /// release that fails keeps the reservations; a later release of the same events, a later exact export,
    /// or `ExchangeEventSequencer.reset()` removes them.
    public final class Receipt: @unchecked Sendable { // `isFinished` is guarded by `lock`.
        private let sequencer: ExchangeEventSequencer
        private let held: [ExchangeEventReservation.Handle]
        private let forgetting: [ExchangeEventKey]
        private let lock = NSLock()
        private var isFinished = false

        init(sequencer: ExchangeEventSequencer, held: [ExchangeEventReservation.Handle], forgetting: [ExchangeEventKey]) {
            self.sequencer = sequencer
            self.held = held
            self.forgetting = forgetting
        }

        /// Ends this call's hold on its reservations, so the next export of the same records is a new event.
        ///
        /// Only the first call counts. Storage failures are swallowed: a reservation that stays behind only
        /// makes a later exact export reproduce the same event.
        public func release() {
            guard claim() else {
                return
            }
            try? sequencer.finish(held, released: true, forgetting: forgetting)
        }

        private func claim() -> Bool {
            lock.lock()
            defer {
                lock.unlock()
            }
            guard !isFinished else {
                return false
            }
            isFinished = true
            return true
        }

        deinit {
            if !isFinished, !held.isEmpty {
                try? sequencer.finish(held, released: false, forgetting: [])
            }
        }
    }
}

#endif
