//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
@testable import GroveSensorKit
import SensorKit
import Testing


/// A deterministic generator, so a failing seed reproduces its input.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }
}


/// A fetch that must deliver the same batch again.
private struct Check<Input> {
    let label: String
    let input: Input
    let anchor: ManagedQueryAnchor
}


private struct IndexedSafeSample: SensorKitSampleSafeRepresentation {
    let timeRange: Range<Date>
    let index: Int
}

/// A sample of another sensor that carries its position in the generated input, so a lost or repeated sample shows.
private final class IndexedSample: NSObject, SensorKitSampleProtocol {
    typealias SafeRepresentation = IndexedSafeSample

    let index: Int
    let isUsable: Bool

    init(index: Int, isUsable: Bool) {
        self.index = index
        self.isUsable = isUsable
    }

    static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: IndexedSample)>
    ) -> [IndexedSafeSample] {
        samples.filter(\.sample.isUsable).map { IndexedSafeSample(timeRange: $0.timestamp..<$0.timestamp, index: $0.sample.index) }
    }
}


/// Generated native ECG results, with what the generator knows about them.
private struct ECGInput {
    /// The results in delivery order.
    var results: [ECGBatchBoundaryTests.NativeResult]
    /// The sessions left whole: one fetch over all results must deliver each of them.
    var intact: [[SensorKitECGSession.InputGroup]]
    /// The timestamps after which a fetch may end: every distinct timestamp, or, when unfinished sessions are
    /// finished at the end of a fetch, only those that no session spans.
    var cuts: [Double]
}


/// A sequence of ECG fetches with acknowledgement over results that become visible in steps, checking each batch.
@available(iOS 18, *)
private struct ECGRun {
    let input: ECGInput
    let reveals: [Double]
    let batchSize: Int
    let limits: SensorKitECGProcessingLimits
    let context: String
    let start: Date
    private(set) var delivered: [SensorKitECGSession] = []
    private(set) var tokens: [ECGBatchBoundaryTests.Batch] = []
    /// Whether the run reached the end of the results, and did not stop at a capacity failure.
    private(set) var completed = false

    init(input: ECGInput, reveals: [Double], batchSize: Int, limits: SensorKitECGProcessingLimits, context: String, start: Date) {
        self.input = input
        self.reveals = reveals
        self.batchSize = batchSize
        self.limits = limits
        self.context = context
        self.start = start
    }

    /// - Returns: Whether a fetch delivered a batch or the run completed; `false` when the first fetch failed.
    @discardableResult
    mutating func run() async throws -> Bool {
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        var revealIndex = 0
        for _ in 0..<500 {
            let cursor = try anchor.value.nativeTimestamp ?? -Double.infinity
            let visible = input.results.filter { $0.timestamp.rawValue > cursor && $0.timestamp.rawValue <= reveals[revealIndex] }
            let batch: ECGBatchBoundaryTests.Batch?
            do {
                batch = try await SampleCountFetcherPropertyTests.firstECGBatch(of: visible, anchor: anchor, batchSize: batchSize, limits: limits)
            } catch SensorKitECGSession.ProcessingError.assemblyCapacityExceeded where limits != SensorKitECGProcessingLimits() {
                return !delivered.isEmpty
            } catch {
                Issue.record("\(context): fetch threw \(error)")
                return true
            }
            guard let batch else {
                guard revealIndex < reveals.count - 1 else {
                    completed = true
                    return true
                }
                revealIndex += 1
                continue
            }
            try await check(batch, anchor: anchor, cursor: cursor, visible: visible, reveal: reveals[revealIndex])
            try await batch.acknowledge()
            delivered += batch.samples
            tokens.append(batch)
        }
        Issue.record("\(context): the run didn't end")
        return true
    }

    private func check(
        _ batch: ECGBatchBoundaryTests.Batch,
        anchor: ManagedQueryAnchor,
        cursor: Double,
        visible: [ECGBatchBoundaryTests.NativeResult],
        reveal: Double
    ) async throws {
        let pendingAnchor = batch.info.replayToken.anchor
        let newer = input.results.filter { $0.timestamp.rawValue > cursor }
        var checks = input.cuts.filter { $0 > reveal }.map { cut in
            Check(label: "restart up to \(cut)", input: newer.filter { $0.timestamp.rawValue <= cut }, anchor: anchor)
        }
        checks.append(Check(label: "restart", input: visible, anchor: anchor))
        for check in checks {
            do {
                let again = try await SampleCountFetcherPropertyTests.firstECGBatch(
                    of: check.input, anchor: check.anchor, batchSize: batchSize, limits: limits
                )
                #expect(again?.samples == batch.samples, "\(context): \(check.label) samples")
                #expect(again?.info.replayToken == batch.info.replayToken, "\(context): \(check.label) token")
                #expect(again?.info.acquisitionBatch == batch.info.acquisitionBatch, "\(context): \(check.label) coordinate")
            } catch {
                Issue.record("\(context): \(check.label) threw \(error)")
            }
        }
        do {
            let replayed = try await SampleCountFetcherPropertyTests.firstECGBatch(
                of: newer,
                anchor: .ephemeral(anchor: pendingAnchor),
                batchSize: try #require(pendingAnchor.pendingBatch, "\(context)").sampleCount,
                limits: limits
            )
            #expect(replayed?.samples == batch.samples, "\(context): replay samples")
            #expect(replayed?.info.replayToken == batch.info.replayToken, "\(context): replay token")
        } catch {
            Issue.record("\(context): replay threw \(error)")
        }
    }
}


/// Randomized inputs for the sample-count fetcher.
///
/// Every batch of a sequence of fetches with acknowledgement must together hold exactly what one fetch over all results
/// delivers, in order, and for the other sensor exactly its usable samples. That one fetch must deliver every ECG session
/// the generator left whole. Before each acknowledgement, a restart with the configured batch size over the results
/// returned so far, over each longer prefix of the newer results and over all of them, and a replay from a copy of the
/// pending anchor, must deliver the same batch; after the run every replay token must deliver its batch again. A fetch
/// may fail only with `assemblyCapacityExceeded`, and only under limits smaller than the defaults. Set
/// `GROVE_FETCHER_PROPERTY_SEED` (with the `TEST_RUNNER_` prefix for the simulator) to run one seed.
@Suite(.timeLimit(.minutes(1)))
struct SampleCountFetcherPropertyTests {
    private typealias Fixture = ECGBatchBoundaryTests
    fileprivate typealias NativeResult = ECGBatchBoundaryTests.NativeResult

    static let seeds: [UInt64] = {
        if let seed = ProcessInfo.processInfo.environment["GROVE_FETCHER_PROPERTY_SEED"].flatMap(UInt64.init) {
            return [seed]
        }
        return Array(1...300)
    }()

    @Test(arguments: seeds)
    @available(iOS 18, *)
    func ecgBatchesMatchOneFetchOverAllResults(seed: UInt64) async throws {
        var random = SeededGenerator(seed: seed)
        // Results older than the hold cutoff can't receive more data, so a fetch finishes their unfinished sessions.
        let finishesAtTheEnd = random.chance(0.5)
        let stream = Fixture.NativeStream(start: Date.now.addingTimeInterval(finishesAtTheEnd ? -26 * 3600 : -120))
        let input = Self.ecgInput(stream: stream, finishesAtTheEnd: finishesAtTheEnd, using: &random)
        let batchSize = Int.random(in: 1...4, using: &random)
        let smallLimits = random.chance(0.5)
        let limits = smallLimits
            ? try SensorKitECGProcessingLimits(
                maximumEntries: Int.random(in: 8...40, using: &random), maximumSessions: Int.random(in: 2...6, using: &random)
            )
            : SensorKitECGProcessingLimits()
        let reveals = input.cuts.dropLast().filter { _ in random.chance(0.4) } + [input.cuts.last ?? 0]
        let context = "seed \(seed), batch size \(batchSize), limits \(limits.maximumEntries)/\(limits.maximumSessions), " +
            (finishesAtTheEnd ? "finished at the end" : "held")
        let reference = try await Fixture.fetch(input.results, anchor: .ephemeral(startDate: stream.start), batchSize: 1_000_000)
            .flatMap(\.samples)
        for session in input.intact {
            #expect(reference.contains(try #require(try SensorKitECGSession.process(session).first)), "\(context): whole session delivered")
        }
        var run = ECGRun(input: input, reveals: reveals, batchSize: batchSize, limits: limits, context: context, start: stream.start)
        guard try await run.run() || !smallLimits else {
            // The first fetch failed under the small limits, so the run repeats with the default ones.
            run = ECGRun(input: input, reveals: reveals, batchSize: batchSize, limits: .init(), context: context, start: stream.start)
            try await run.run()
            #expect(run.delivered == reference, "\(context): all batches against one fetch, default limits")
            return
        }
        if run.completed {
            #expect(run.delivered == reference, "\(context): all batches against one fetch")
        } else {
            #expect(reference.starts(with: run.delivered), "\(context): batches before the capacity failure")
        }
        for batch in run.tokens {
            let pendingAnchor = batch.info.replayToken.anchor
            let cursor = pendingAnchor.nativeTimestamp ?? -Double.infinity
            let again = try await Self.firstECGBatch(
                of: input.results.filter { $0.timestamp.rawValue > cursor },
                anchor: .ephemeral(anchor: pendingAnchor),
                batchSize: try #require(pendingAnchor.pendingBatch).sampleCount,
                limits: run.limits
            )
            #expect(again?.samples == batch.samples, "\(context): replay after the run")
        }
    }

    @Test(arguments: seeds)
    @available(iOS 18, *)
    func otherSensorBatchesMatchTheirUsableSamples(seed: UInt64) async throws {
        var random = SeededGenerator(seed: seed)
        let origin = SRAbsoluteTime(Date.now.addingTimeInterval(-120))
        var results: [(timestamp: SRAbsoluteTime, sample: IndexedSample)] = []
        var seconds = 1.0
        for index in 0..<Int.random(in: 1...24, using: &random) {
            seconds += [0, 0, 1, 2].randomElement(using: &random) ?? 1
            results.append((SRAbsoluteTime(rawValue: origin.rawValue + seconds), IndexedSample(index: index, isUsable: random.chance(0.8))))
        }
        let reference = results.filter(\.sample.isUsable).map(\.sample.index)
        let batchSize = Int.random(in: 1...4, using: &random)
        let cuts = Array(Set(results.map(\.timestamp.rawValue))).sorted()
        let reveals = cuts.dropLast().filter { _ in random.chance(0.4) } + [cuts.last ?? 0]
        let anchor = ManagedQueryAnchor.ephemeral(startDate: Date(origin))
        let context = "seed \(seed), batch size \(batchSize)"
        var delivered: [Int] = []
        var revealIndex = 0
        for _ in 0..<500 {
            let cursor = try anchor.value.nativeTimestamp ?? -Double.infinity
            let visible = results.filter { $0.timestamp.rawValue > cursor && $0.timestamp.rawValue <= reveals[revealIndex] }
            guard let batch = try await Self.firstBatch(of: visible, anchor: anchor, batchSize: batchSize) else {
                guard revealIndex < reveals.count - 1 else {
                    break
                }
                revealIndex += 1
                continue
            }
            let pendingAnchor = batch.info.replayToken.anchor
            var checks = cuts.filter { $0 > reveals[revealIndex] }.map { cut in
                Check(label: "restart up to \(cut)", input: results.filter { $0.timestamp.rawValue > cursor && $0.timestamp.rawValue <= cut }, anchor: anchor)
            }
            checks.append(Check(label: "restart", input: visible, anchor: anchor))
            for check in checks {
                do {
                    let again = try await Self.firstBatch(of: check.input, anchor: check.anchor, batchSize: batchSize)
                    #expect(again?.samples.map(\.index) == batch.samples.map(\.index), "\(context): \(check.label) samples")
                    #expect(again?.info.replayToken == batch.info.replayToken, "\(context): \(check.label) token")
                    #expect(again?.info.acquisitionBatch == batch.info.acquisitionBatch, "\(context): \(check.label) coordinate")
                } catch {
                    Issue.record("\(context): \(check.label) threw \(error)")
                }
            }
            let replayed = try await Self.firstBatch(
                of: results.filter { $0.timestamp.rawValue > cursor },
                anchor: .ephemeral(anchor: pendingAnchor),
                batchSize: try #require(pendingAnchor.pendingBatch, "\(context)").sampleCount
            )
            #expect(replayed?.samples.map(\.index) == batch.samples.map(\.index), "\(context): replay samples")
            #expect(replayed?.info.replayToken == batch.info.replayToken, "\(context): replay token")
            try await batch.acknowledge()
            delivered += batch.samples.map(\.index)
        }
        #expect(delivered == reference, "\(context): all batches against all usable samples")
    }
}


extension SampleCountFetcherPropertyTests {
    /// Native ECG results of sessions that may be split across results, share timestamps, lack states or voltage,
    /// start in the result of the previous session's last data or before it, or repeat a fragment of an earlier
    /// session, followed by a complete session that ends every unfinished one.
    @available(iOS 18, *)
    private static func ecgInput(
        stream: ECGBatchBoundaryTests.NativeStream, finishesAtTheEnd: Bool, using random: inout SeededGenerator
    ) -> ECGInput {
        var batches: [[SensorKitECGSession.InputGroup]] = []
        var fragments: Set<Int> = []
        var whole: [String: [SensorKitECGSession.InputGroup]] = [:]
        var earlier: [[SensorKitECGSession.InputGroup]] = []
        var forceWithoutEnd = false
        for index in 0..<Int.random(in: 1...10, using: &random) {
            var groups = ECGBatchBoundaryTests.NativeStream.session("session-\(index)", offset: Double(index) * 10)
            // A session without voltage over several results, whose last result starts an unfinished session.
            let targeted = !forceWithoutEnd && random.chance(0.2)
            let kind = targeted ? 1 : forceWithoutEnd ? 0 : Int.random(in: 0..<6, using: &random)
            groups = Self.altered(groups, kind: kind)
            if kind >= 4 {
                whole[groups[0].identifier] = groups
            }
            var parts: [[SensorKitECGSession.InputGroup]] = []
            for group in groups {
                if parts.isEmpty || targeted || random.chance(0.7) {
                    parts.append([group])
                } else {
                    parts[parts.count - 1].append(group)
                }
            }
            if let last = batches.last, forceWithoutEnd || random.chance(0.6), let first = parts.first {
                // The session starts in the result that holds the previous session's last data.
                batches[batches.count - 1] = last + first
                parts.removeFirst()
            }
            forceWithoutEnd = targeted
            batches += parts
            if let fragment = earlier.randomElement(using: &random)?.first(where: { $0.state == .active }), random.chance(0.2) {
                fragments.insert(batches.count)
                batches.append([fragment])
            }
            earlier.append(groups)
        }
        for identifier in Self.interleave(&batches, sparing: fragments, using: &random) {
            whole[identifier] = nil
        }
        batches.append(ECGBatchBoundaryTests.NativeStream.session("final-session", offset: 1000))
        whole["final-session"] = batches.last
        var seconds = 0
        let results = batches.map { groups in
            seconds += [0, 1, 1, 2].randomElement(using: &random) ?? 1
            return stream.result(groups, at: max(seconds, 1))
        }
        let cuts = Self.cuts(of: results, finishesAtTheEnd: finishesAtTheEnd)
        return ECGInput(results: results, intact: Array(whole.values), cuts: cuts)
    }

    /// A session without its end state (kind 0), without voltage (1), without its begin state (2), without its active
    /// state (3), or whole.
    @available(iOS 18, *)
    private static func altered(_ groups: [SensorKitECGSession.InputGroup], kind: Int) -> [SensorKitECGSession.InputGroup] {
        switch kind {
        case 0:
            return Array(groups.dropLast())
        case 1:
            return groups.map { group in
                SensorKitECGSession.InputGroup(
                    identifier: group.identifier,
                    state: group.state,
                    guidance: group.guidance,
                    readings: group.readings.map { .init(date: $0.date, frequency: $0.frequency, lead: $0.lead, samples: []) }
                )
            }
        case 2:
            return Array(groups.dropFirst())
        case 3:
            return groups.filter { $0.state != .active }
        default:
            return groups
        }
    }

    /// Swaps some adjacent results of different sessions, so another session's data arrives before a session's end.
    ///
    /// - Returns: The sessions such a swap interrupted.
    private static func interleave(
        _ batches: inout [[SensorKitECGSession.InputGroup]], sparing fragments: Set<Int>, using random: inout SeededGenerator
    ) -> Set<String> {
        var interrupted: Set<String> = []
        for index in batches.indices.dropLast() where random.chance(0.15) && !fragments.contains(index) && !fragments.contains(index + 1) {
            let first = Set(batches[index].map(\.identifier))
            let second = Set(batches[index + 1].map(\.identifier))
            guard first.isDisjoint(with: second) else {
                continue
            }
            batches.swapAt(index, index + 1)
            interrupted.formUnion(first.union(second))
        }
        return interrupted
    }

    /// The timestamps after which a fetch may end.
    ///
    /// When unfinished sessions are finished at the end of a fetch, a fetch that ends inside a session, or before a
    /// repeated fragment of it, would finish it without its later data, which one fetch over all results doesn't. A
    /// restart or replay of such a batch fails, as documented, so the fetches end only where no session continues.
    private static func cuts(of results: [NativeResult], finishesAtTheEnd: Bool) -> [Double] {
        let distinct = Array(Set(results.map(\.timestamp.rawValue))).sorted()
        guard finishesAtTheEnd else {
            return distinct
        }
        var spans: [String: ClosedRange<Double>] = [:]
        for result in results {
            for identifier in Set(result.groups.map(\.identifier)) {
                let time = result.timestamp.rawValue
                spans[identifier] = spans[identifier].map { min($0.lowerBound, time)...max($0.upperBound, time) } ?? time...time
            }
        }
        return distinct.filter { cut in !spans.values.contains { $0.lowerBound <= cut && cut < $0.upperBound } }
    }

    /// Runs a native fetch up to its first batch and abandons it there, or returns `nil` when it delivers none.
    @available(iOS 18, *)
    fileprivate static func firstECGBatch(
        of results: [NativeResult], anchor: ManagedQueryAnchor, batchSize: Int, limits: SensorKitECGProcessingLimits
    ) async throws -> ECGBatchBoundaryTests.Batch? {
        let fetcher = ECGBatchBoundaryTests.fetcher(anchor: anchor, batchSize: batchSize, limits: limits)
        try fetcher.startNativeFetchForTesting()
        let feed = ECGBatchBoundaryTests.feed(results, to: fetcher)
        let batch: ECGBatchBoundaryTests.Batch?
        do {
            batch = try await fetcher.next(isolation: nil)
        } catch {
            fetcher.stopForTesting()
            await feed.value
            throw error
        }
        fetcher.stopForTesting()
        await feed.value
        return batch
    }

    @available(iOS 18, *)
    private static func firstBatch(
        of results: [(timestamp: SRAbsoluteTime, sample: IndexedSample)], anchor: ManagedQueryAnchor, batchSize: Int
    ) async throws -> SensorKit.AnchoredBatch<IndexedSafeSample>? {
        let sensor = Sensor<IndexedSample>(
            srSensor: .ambientLightSensor, displayName: "Indexed test sensor", dataQuarantineDuration: .zero, sensorKitFetchReturnType: .object
        )
        let fetcher = AnchoredFetcher<IndexedSample>.SampleCountBasedFetcher(
            sensor: sensor, batchSize: batchSize, anchor: anchor, device: .current, startFetch: { _, _ in }
        )
        try fetcher.startNativeFetchForTesting()
        nonisolated(unsafe) let reader = fetcher
        let (finished, continuation) = AsyncStream<Void>.makeStream()
        nonisolated(unsafe) let input = results
        Thread.detachNewThread {
            defer {
                continuation.finish()
            }
            for result in input where !reader.processForTesting(sample: result.sample, timestamp: result.timestamp) {
                return
            }
            reader.completeFetchForTesting()
        }
        let batch = try await fetcher.next(isolation: nil)
        fetcher.stopForTesting()
        for await _ in finished {}
        return batch
    }
}
#endif
