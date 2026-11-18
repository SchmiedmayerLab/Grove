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
    /// One input of ``export(records:at:conversionInstants:receive:)``: a sample, plus the companion data HealthKit keeps
    /// outside the sample for the kinds that need it. The exporter never queries HealthKit itself.
    public enum Record: Sendable {
        /// Any sample; an `HKElectrocardiogram`, `HKHeartbeatSeriesSample` or `HKWorkoutRoute` passed here is refused, as
        /// its companion data is missing.
        case sample(HKSample)
        /// A sample `source` created and did not save into HealthKit, for example because the user does not let it
        /// write the sample's type.
        ///
        /// HealthKit attributes a sample only when it saves it: until then the sample's revision names no source, and
        /// such a sample states no writer, no source revision and no gateway role. The exporter therefore states the
        /// revision HealthKit would stamp if `source` saved the sample now: `source`, the producer's
        /// `ApplicationDevice.build` as its version, the producer host's `HostDevice.productType`, and the operating
        /// system version the process runs on. The record then states what it would for the sample saved and fetched
        /// back, under the same options. Export it from the build that created it, as a later build states itself.
        ///
        /// A sample whose revision names a source, one the store held, keeps its own. ``UnsavedSample`` lists the kinds
        /// of sample this takes.
        case unsavedSample(UnsavedSample, source: HKSource = .default())
        /// An electrocardiogram with its voltages and correlated symptom samples; each symptom becomes a
        /// record of its own.
        case electrocardiogram(HKElectrocardiogram, voltages: [HKElectrocardiogram.VoltageMeasurement], symptoms: [HKCategorySample])
        /// A heartbeat series with its beats, exported as a recording document.
        case heartbeatSeries(HKHeartbeatSeriesSample, beats: [Heartbeat])
        /// A workout route with its locations, exported as a recording document only under
        /// ``Options/route`` `.authorized`.
        case workoutRoute(HKWorkoutRoute, locations: [CLLocation])
        /// A complete file-backed route or beat series, preserving its sample metadata and device lineage.
        case fileRecording(HealthKitRecordingFile)

        /// A sample of ``unsavedSample(_:source:)``: one of the kinds of sample the exporter states an unsaved one's
        /// origin for.
        public enum UnsavedSample: Sendable {
            /// A quantity sample.
            ///
            /// - Invariant: The sample must be created by the app, and must not have been saved to HealthKit.
            case quantitySample(HKQuantitySample)

            /// A correlation sample.
            ///
            /// - Invariant: The sample must be created by the app, and must not have been saved to HealthKit.
            case correlation(HKCorrelation)

            /// The underlying `HKSample`.
            var sample: HKSample {
                switch self {
                case .quantitySample(let sample):
                    sample
                case .correlation(let sample):
                    sample
                }
            }
        }

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
            case .unsavedSample(let unsavedSample, source: _): unsavedSample.sample
            case .electrocardiogram(let ecg, _, _): ecg
            case .heartbeatSeries(let series, _): series
            case .workoutRoute(let route, _): route
            case .fileRecording(let recording): recording.sample
            }
        }

        /// The source revision HealthKit would stamp if an unsaved sample's `source` saved it now, which the record states
        /// in place of the sample's own; `nil` for every other record, and for an unsaved sample whose revision names a
        /// source. See ``unsavedSample(_:source:)``.
        func unsavedSampleRevision(producer facts: ConversionFacts) -> HKSourceRevision? {
            guard case let .unsavedSample(unsavedSample, source) = self,
                  !HealthKitAssembly.SourceFacts.namesSource(unsavedSample.sample.sourceRevision) else {
                return nil
            }
            return HKSourceRevision(
                source: source,
                version: facts.application.build,
                productType: facts.host.productType,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            )
        }
    }

    /// A deleted HealthKit object as the app noted it: HealthKit reports no deletion time, so the
    /// retraction states the bounds the app knows.
    ///
    /// The bounds key nothing: the retraction key is the source record alone, and the first accepted retraction wins.
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

    /// What one input produced: an exchange record, or the reason it produced none.
    public struct Export: Sendable {
        /// The record's coordinate in the HealthKit store. It stays on the device and is never on the wire
        /// unless ``Options/nativeIdentifier`` discloses it.
        public struct Source: Hashable, Sendable {
            public let uuid: UUID
            /// The HealthKit type identifier, such as `HKQuantityTypeIdentifierHeartRate`.
            public let typeIdentifier: String

            public var sourceType: HealthKitSourceType? { HealthKitSourceType(rawValue: typeIdentifier) }
        }

        public enum Outcome: Sendable {
            /// The validated record; stage `ExchangeRecord.json` verbatim, and pack it for upload.
            case record(ExchangeRecord)
            /// The record was refused; nothing was emitted and the export continued. Refusals are
            /// deterministic, so an exact redelivery refuses identically.
            case refused(HealthKitConversionError)
        }

        /// Counts for otherwise unmapped sample metadata; values carried by structured mappings are not counted.
        /// `excludedSampleKeys` counts the keys ``HealthKitFHIRExporter/Options/metadata`` excludes. A device metadata key
        /// whose fact ``HealthKitFHIRExporter/Options/device`` omits is counted in none of the three.
        /// Contained-object omissions remain in `warnings`.
        /// Keys and values are deliberately absent from this aggregate diagnostic.
        public struct MetadataSummary: Sendable, Equatable {
            public let preservedSampleKeys: Int
            public let unsupportedSampleKeys: Int
            public let excludedSampleKeys: Int
        }

        public let source: Source
        public let outcome: Outcome
        /// The effective preservation result, or nil when conversion was refused.
        public let metadata: MetadataSummary?

        /// What the sample carried that its record does not; each is a registered omission rule. ``WarningReport``
        /// summarizes them by kind across many exports.
        public let warnings: [ProducerDiagnostic]

        /// The record, when one was produced.
        public var record: ExchangeRecord? {
            if case .record(let record) = outcome { record } else { nil }
        }

        init(source: Source, outcome: Outcome, warnings: [ProducerDiagnostic], metadata: MetadataSummary? = nil) {
            self.source = source
            self.outcome = outcome
            self.warnings = warnings
            self.metadata = metadata
        }
    }

    /// What one ``Deletion`` produced: a retraction record, or the reason it produced none.
    public struct Retraction: Sendable {
        public enum Outcome: Sendable {
            /// The validated retraction record; pack it into a retraction Bundle for upload.
            case record(ExchangeRecord)
            /// The deletion was refused; nothing was emitted and the retraction continued. Refusals are
            /// deterministic, so an exact redelivery refuses identically.
            case refused(HealthKitConversionError)
            /// The deletion names no output this exporter can have emitted: a source type without outputs, or a
            /// workout route while ``Options/route`` is `.omit`.
            case nothingToRetract
        }

        /// The deletion, as it was passed in.
        public let deletion: Deletion
        public let outcome: Outcome

        /// The record, when one was produced.
        public var record: ExchangeRecord? {
            if case .record(let record) = outcome { record } else { nil }
        }
    }
}

#endif
