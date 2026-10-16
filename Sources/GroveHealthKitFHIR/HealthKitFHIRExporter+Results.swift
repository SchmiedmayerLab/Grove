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
        /// Any sample; an `HKElectrocardiogram`, `HKHeartbeatSeriesSample` or `HKWorkoutRoute` passed here reserves
        /// its event and is then refused, as its companion data is missing.
        case sample(HKSample)
        /// An electrocardiogram with its voltages and correlated symptom samples; each symptom becomes an
        /// event of its own.
        case electrocardiogram(HKElectrocardiogram, voltages: [HKElectrocardiogram.VoltageMeasurement], symptoms: [HKCategorySample])
        /// A heartbeat series with its beats, exported as a recording document.
        case heartbeatSeries(HKHeartbeatSeriesSample, beats: [Heartbeat])
        /// A workout route with its locations, exported as a recording document only under
        /// ``Options/route`` `.authorized`.
        case workoutRoute(HKWorkoutRoute, locations: [CLLocation])

        /// One beat instant in a heartbeat series, as `HKHeartbeatSeriesQuery` enumerates it.
        public struct Heartbeat: Hashable, Sendable {
            public let timeSinceSeriesStart: TimeInterval
            public let precededByGap: Bool

            public init(timeSinceSeriesStart: TimeInterval, precededByGap: Bool) {
                self.timeSinceSeriesStart = timeSinceSeriesStart
                self.precededByGap = precededByGap
            }
        }

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
    ///
    /// Both bounds key the retraction event, so persist them with the deletion until its retraction's receipt is
    /// released: a retry that recomputes either, such as `detectedAt` from the clock, mints a second retraction event.
    public struct Deletion: Hashable, Sendable {
        public let uuid: UUID
        public let sourceType: HealthKitSourceType
        /// A lower bound on when the object was deleted, or `nil` when none is known: the latest instant every
        /// deletion an anchored query reports is known to follow, which is when the query that produced the anchor
        /// it started from was issued.
        ///
        /// GroveHealthKit passes it to `HealthKitConstraint.handleDeletedObjects(_:ofType:deletedAfter:)`. With a raw
        /// `HKAnchoredObjectQuery`, record when you issue each query, persist that instant with the anchor the query
        /// returns, and pass it for every deletion the next query, started from that anchor, reports. The start of
        /// the query that reported the deletion is too late: the deletion may precede it.
        public let deletedAfter: Date?
        /// When the app received the deletion; the retraction states it as the upper bound.
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
        }

        public let source: Source
        public let outcome: Outcome
        /// What the record carried that its graph does not; each is a registered omission rule. ``WarningReport``
        /// summarizes them by kind across many exports.
        public let warnings: [ProducerDiagnostic]

        /// The graph, when one was produced.
        public var graph: ExchangeGraph? {
            if case .graph(let graph) = outcome { graph } else { nil }
        }
    }

    /// What one ``Deletion`` produced: a retraction graph, or the reason it produced none.
    public struct Retraction: Sendable {
        public enum Outcome: Sendable {
            /// The validated retraction graph; store or upload `ExchangeGraph.json` verbatim.
            case graph(ExchangeGraph)
            /// The deletion was refused; nothing was emitted and the retraction continued. Refusals are
            /// deterministic, so an exact redelivery refuses identically.
            case refused(HealthKitConversionError)
            /// The deletion names no output this exporter can have emitted: a source type without outputs, or a
            /// workout route while ``Options/route`` is `.omit`. No event is reserved for it.
            case nothingToRetract
        }

        /// The deletion, as it was passed in.
        public let deletion: Deletion
        public let outcome: Outcome

        /// The graph, when one was produced.
        public var graph: ExchangeGraph? {
            if case .graph(let graph) = outcome { graph } else { nil }
        }
    }
}

#endif
