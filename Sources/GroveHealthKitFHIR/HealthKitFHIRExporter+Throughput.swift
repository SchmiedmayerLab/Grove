//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import OSLog
import Synchronization


/// One export call's measurements, gathered without locking and added to the exporter's totals once, when it ends.
@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What this exporter's export calls cost since it was created, measured under ``Options/measuresThroughput``.
    ///
    /// Phase times are summed over every call, so with concurrent calls they add up to more than ``busy``, the
    /// wall-clock time during which at least one call ran. Retractions are not measured.
    public struct Throughput: Sendable, CustomStringConvertible {
        /// The time spent in each phase of the export calls.
        public struct Phases: Sendable, Equatable {
            /// Planning each record: its content plan, an ECG's evidence, the policies and the request fingerprint.
            public internal(set) var plan: Duration = .zero
            /// The ledger transaction that reserves a call's events, once per call.
            public internal(set) var reserve: Duration = .zero
            /// Building each graph: its content, envelope, Devices, Provenance and identities.
            public internal(set) var assemble: Duration = .zero
            /// Encoding each graph and validating it against the guide.
            public internal(set) var validate: Duration = .zero
            /// The caller's `receive` closure; not the exporter's own time.
            public internal(set) var receive: Duration = .zero

            /// The exporter's own time: every phase but ``receive``.
            public var exporter: Duration {
                plan + reserve + assemble + validate
            }
        }

        /// What the records of one source type cost.
        public struct SourceTypeTotals: Sendable, Equatable {
            /// The records of this type the calls planned.
            public internal(set) var records = 0
            /// The graphs delivered for this type; an ECG's symptoms count under their own type.
            public internal(set) var graphs = 0
            /// The refusals delivered for this type.
            public internal(set) var refusals = 0
            /// The bytes of this type's graphs.
            public internal(set) var bytes = 0
            /// Planning, assembling and validating this type's records.
            public internal(set) var duration: Duration = .zero
        }

        /// The export calls measured.
        public internal(set) var calls = 0
        /// The records those calls planned.
        public internal(set) var records = 0
        /// The time spent in each phase, summed over every call.
        public internal(set) var phases = Phases()
        /// The wall-clock time during which at least one export call ran.
        public internal(set) var busy: Duration = .zero
        /// The totals of each source type, by HealthKit type identifier.
        public internal(set) var sourceTypes: [String: SourceTypeTotals] = [:]

        /// A short report: the rates, each phase's share of the measured time, then each type by record count.
        public var description: String {
            guard calls > 0 else {
                return "No HealthKit export measured"
            }
            let total = phases.exporter + phases.receive
            func share(_ duration: Duration) -> String {
                Self.percent(duration, of: total)
            }
            var lines = [
                "HealthKit export: \(Self.count(records, "record")) in \(Self.count(calls, "call")), \(Self.seconds(busy)) busy"
                    + " (\(Self.rate(records, in: busy)) records/s; \(Self.rate(records, in: phases.exporter)) records/s of exporter time)",
                "  plan \(share(phases.plan)) · reserve \(share(phases.reserve)) (\(Self.milliseconds(phases.reserve / calls)) per call)"
                    + " · assemble \(share(phases.assemble)) · validate \(share(phases.validate))"
                    + " · receive \(share(phases.receive)) (caller)"
            ]
            let types = sourceTypes.sorted { lhs, rhs in
                lhs.value.records != rhs.value.records ? lhs.value.records > rhs.value.records : lhs.key < rhs.key
            }
            for (type, totals) in types {
                let perRecord = totals.records > 0 ? Self.milliseconds(totals.duration / totals.records) : "-"
                let perGraph = totals.graphs > 0 ? String(format: "%.1f KB", Double(totals.bytes) / Double(totals.graphs) / 1024) : "-"
                lines.append(
                    "  \(type): \(Self.count(totals.records, "record")), \(Self.count(totals.graphs, "graph")),"
                        + " \(Self.count(totals.refusals, "refusal")) · \(perRecord) per record · \(perGraph) per graph"
                )
            }
            return lines.joined(separator: "\n")
        }

        private static func count(_ value: Int) -> String {
            value.formatted(.number.locale(Locale(identifier: "en_US")))
        }

        private static func count(_ value: Int, _ noun: String) -> String {
            "\(count(value)) \(noun)\(value == 1 ? "" : "s")"
        }

        private static func secondsValue(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds) + Double(components.attoseconds) / 1e18
        }

        private static func seconds(_ duration: Duration) -> String {
            String(format: "%.1f s", secondsValue(duration))
        }

        private static func milliseconds(_ duration: Duration) -> String {
            String(format: "%.2f ms", secondsValue(duration) * 1000)
        }

        private static func rate(_ records: Int, in duration: Duration) -> String {
            let seconds = secondsValue(duration)
            return seconds > 0 ? count(Int((Double(records) / seconds).rounded())) : "-"
        }

        private static func percent(_ part: Duration, of total: Duration) -> String {
            let total = secondsValue(total)
            return total > 0 ? String(format: "%.1f%%", secondsValue(part) / total * 100) : "-"
        }

        /// Adds another measurement, such as one call's, into this one.
        mutating func add(_ other: Self) {
            calls += other.calls
            records += other.records
            busy += other.busy
            phases.plan += other.phases.plan
            phases.reserve += other.phases.reserve
            phases.assemble += other.phases.assemble
            phases.validate += other.phases.validate
            phases.receive += other.phases.receive
            for (type, totals) in other.sourceTypes {
                sourceTypes[type, default: SourceTypeTotals()].add(totals)
            }
        }
    }

    /// What this exporter's export calls cost so far; `nil` unless ``Options/measuresThroughput`` is set.
    public var throughput: Throughput? {
        throughputRecorder?.snapshot
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Throughput {
    /// The totals of one measuring exporter, shared by its concurrent calls.
    final class Recorder: Sendable {
        private struct State {
            var totals = HealthKitFHIRExporter.Throughput()
            var activeCalls = 0
            var busySince: ContinuousClock.Instant?
        }

        static let signposter = OSSignposter(subsystem: "org.grovealliance", category: "GroveHealthKitFHIR")

        private let state = Mutex(State())

        var snapshot: HealthKitFHIRExporter.Throughput {
            state.withLock { $0.totals }
        }

        func callBegan(at instant: ContinuousClock.Instant) {
            state.withLock { state in
                if state.activeCalls == 0 {
                    state.busySince = instant
                }
                state.activeCalls += 1
            }
        }

        func callEnded(_ call: HealthKitFHIRExporter.Throughput, at instant: ContinuousClock.Instant) {
            state.withLock { state in
                state.activeCalls -= 1
                if state.activeCalls == 0, let busySince = state.busySince {
                    state.totals.busy += instant - busySince
                    state.busySince = nil
                }
                state.totals.add(call)
            }
        }
    }

    /// Measures one export call of a measuring exporter, without locking, and adds it to the recorder's totals once,
    /// when the call ends; an exporter that does not measure makes none.
    final class Call {
        private let recorder: Recorder
        private let signpost: OSSignpostIntervalState
        private var measured = HealthKitFHIRExporter.Throughput(calls: 1)

        var now: ContinuousClock.Instant {
            ContinuousClock.now
        }

        init(recorder: Recorder) {
            self.recorder = recorder
            recorder.callBegan(at: ContinuousClock.now)
            signpost = Recorder.signposter.beginInterval("export", id: Recorder.signposter.makeSignpostID())
        }

        func planned(_ type: String, since start: ContinuousClock.Instant?) {
            guard let start else {
                return
            }
            let duration = now - start
            measured.records += 1
            measured.phases.plan += duration
            measured.sourceTypes[type, default: .init()].records += 1
            measured.sourceTypes[type, default: .init()].duration += duration
        }

        func reserved(since start: ContinuousClock.Instant?) {
            guard let start else {
                return
            }
            measured.phases.reserve += now - start
        }

        /// One record's delivery: everything but its validation and the caller's `receive` is assembly.
        func delivered(_ type: String, since start: ContinuousClock.Instant?, validation: Duration, receiving: Duration) {
            guard let start else {
                return
            }
            let assembly = now - start - validation - receiving
            measured.phases.assemble += assembly
            measured.phases.validate += validation
            measured.sourceTypes[type, default: .init()].duration += assembly + validation
        }

        func received(_ export: HealthKitFHIRExporter.Export, in duration: Duration) {
            measured.phases.receive += duration
            let type = export.source.typeIdentifier
            switch export.outcome {
            case .graph(let graph):
                measured.sourceTypes[type, default: .init()].graphs += 1
                measured.sourceTypes[type, default: .init()].bytes += graph.json.count
            case .refused:
                measured.sourceTypes[type, default: .init()].refusals += 1
            }
        }

        func end() {
            Recorder.signposter.endInterval("export", signpost)
            recorder.callEnded(measured, at: now)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.Throughput.SourceTypeTotals {
    mutating func add(_ other: Self) {
        records += other.records
        graphs += other.graphs
        refusals += other.refusals
        bytes += other.bytes
        duration += other.duration
    }
}

#endif
