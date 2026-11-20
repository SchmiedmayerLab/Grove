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


/// Where the results of a generated input lie against the hold cutoff.
private enum HoldMode: CaseIterable {
    /// Every result is newer than the cutoff, so the end of a fetch holds unfinished sessions.
    case held
    /// Every result is older than the cutoff, so the end of a fetch finishes unfinished sessions.
    case finished
    /// The results before a gap of two hours are older than the cutoff, the ones after it newer.
    case mixed

    /// The start of the native stream: two minutes ago, or 26 hours ago, an hour before the ECG sensor's cutoff of its
    /// 24-hour quarantine and the one-hour hold interval.
    var start: Date {
        Date.now.addingTimeInterval(self == .held ? -120 : -26 * 3600)
    }
}


/// Generated native ECG results, with what the generator knows about them.
private struct ECGInput {
    /// The results in delivery order.
    var results: [ECGBatchBoundaryTests.NativeResult]
    /// The sessions left whole: one fetch over all results must deliver each of them.
    var intact: [[SensorKitECGSession.InputGroup]]
    /// The native timestamp before which results are older than the hold cutoff.
    var oldBefore: Double
    /// The timestamps after which a fetch may end: every distinct timestamp except those where the end of the fetch
    /// would finish a session that later results continue.
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
    /// Decides before which fetches a fetch is cancelled first, and after how many results.
    private var random: SeededGenerator
    private(set) var delivered: [SensorKitECGSession] = []
    private(set) var tokens: [ECGBatchBoundaryTests.Batch] = []
    /// Whether the run reached the end of the results, and did not stop at a capacity failure.
    private(set) var completed = false

    init(
        input: ECGInput,
        reveals: [Double],
        batchSize: Int,
        limits: SensorKitECGProcessingLimits,
        context: String,
        start: Date,
        seed: UInt64
    ) {
        self.input = input
        self.reveals = reveals
        self.batchSize = batchSize
        self.limits = limits
        self.context = context
        self.start = start
        self.random = SeededGenerator(seed: seed)
    }

    /// - Returns: Whether a fetch delivered a batch or the run completed; `false` when the first fetch failed.
    @discardableResult
    mutating func run() async throws -> Bool {
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        var revealIndex = 0
        for _ in 0..<500 {
            let cursor = try anchor.value.nativeTimestamp ?? -Double.infinity
            let visible = input.results.filter { $0.timestamp.rawValue > cursor && $0.timestamp.rawValue <= reveals[revealIndex] }
            var cancelled: ECGBatchBoundaryTests.Batch?
            if random.chance(0.3) {
                cancelled = try await cancelFetch(of: visible, anchor: anchor, after: Int.random(in: 0...visible.count, using: &random))
            }
            let batch: ECGBatchBoundaryTests.Batch?
            do {
                batch = try await SampleCountFetcherPropertyTests.firstECGBatch(of: visible, anchor: anchor, batchSize: batchSize, limits: limits)
            } catch SensorKitECGSession.ProcessingError.assemblyCapacityExceeded where limits != SensorKitECGProcessingLimits() {
                try await expectCapacityFailureIsRequired(of: visible, anchor: anchor)
                return !delivered.isEmpty
            } catch {
                Issue.record("\(context): fetch threw \(error)")
                return true
            }
            if let cancelled {
                #expect(batch?.samples == cancelled.samples, "\(context): batch of a cancelled fetch delivered again")
                #expect(batch?.info.replayToken == cancelled.info.replayToken, "\(context): token of a cancelled fetch's batch")
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
        // The anchor holds the batch as pending, so each of these fetches restarts on it with its sample count.
        var checks = input.cuts.filter { $0 > reveal }.map { cut in
            Check(label: "restart on the pending batch up to \(cut)", input: newer.filter { $0.timestamp.rawValue <= cut }, anchor: anchor)
        }
        checks.append(Check(label: "restart on the pending batch", input: visible, anchor: anchor))
        for check in checks {
            do {
                let again = try await SampleCountFetcherPropertyTests.firstECGBatch(
                    of: check.input, anchor: check.anchor, batchSize: batchSize, limits: limits
                )
                #expect(again?.samples == batch.samples, "\(context): \(check.label) samples")
                #expect(again?.info.replayToken == batch.info.replayToken, "\(context): \(check.label) token")
                #expect(again?.info.acquisitionBatch == batch.info.acquisitionBatch, "\(context): \(check.label) coordinate")
                #expect(again?.info.sourceDevices == batch.info.sourceDevices, "\(context): \(check.label) peripherals")
                #expect(
                    again?.info.sourceDevicesSuppliedEverySample == batch.info.sourceDevicesSuppliedEverySample,
                    "\(context): \(check.label) peripherals of every sample"
                )
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
            #expect(replayed?.info.sourceDevices == batch.info.sourceDevices, "\(context): replay peripherals")
        } catch {
            Issue.record("\(context): replay threw \(error)")
        }
    }

    /// Runs a fetch over `visible` that is cancelled after `count` results, while the native fetch is still running.
    ///
    /// - Returns: The batch the fetch delivered before the cancellation; the next fetch must deliver it again.
    private func cancelFetch(of visible: [ECGBatchBoundaryTests.NativeResult], anchor: ManagedQueryAnchor, after count: Int) async throws
        -> ECGBatchBoundaryTests.Batch? {
        let pending = try anchor.value.pendingBatch
        let outcome = try await SampleCountFetcherPropertyTests.cancelledECGFetch(
            of: visible, anchor: anchor, batchSize: batchSize, limits: limits, cancellingAfter: count
        )
        switch outcome {
        case .success(let batch?):
            return batch
        case .success(nil):
            #expect(try anchor.value.pendingBatch == pending, "\(context): a cancelled fetch changed the pending batch")
        case .failure(SensorKitECGSession.ProcessingError.assemblyCapacityExceeded) where limits != SensorKitECGProcessingLimits():
            break
        case .failure(let error):
            Issue.record("\(context): cancelled fetch threw \(error)")
        }
        return nil
    }

    /// Expects that the fetch over `visible` had to fail: the results that a fetch with the default limits processes
    /// before it delivers its first batch don't fit the limits in one assembly.
    private func expectCapacityFailureIsRequired(of visible: [ECGBatchBoundaryTests.NativeResult], anchor: ManagedQueryAnchor) async throws {
        let copy = ManagedQueryAnchor.ephemeral(anchor: try anchor.value)
        let first = try await SampleCountFetcherPropertyTests.firstECGBatch(of: visible, anchor: copy, batchSize: 1, limits: .init())
        var prefix = visible
        if let first {
            try await first.acknowledge()
            let boundary = try #require(try copy.value.nativeTimestamp, "\(context)")
            prefix = SampleCountFetcherPropertyTests.resultsBeforeDelivery(of: visible, boundary: boundary)
        }
        #expect(
            SampleCountFetcherPropertyTests.exceedsLimits(prefix, limits: limits),
            "\(context): capacity failure although the results before the first batch fit the limits"
        )
    }
}


/// Randomized inputs for the sample-count fetcher.
///
/// One fetch over all ECG results must deliver exactly the sessions of a sequential model of the documented session
/// rules, each once, and so must acknowledged fetches with batch sizes 1 to 4. Every batch of a sequence of fetches with
/// acknowledgement over results that become visible in steps must together hold exactly what one fetch over all results
/// delivers, in order, and for the other sensor exactly its usable samples. Before each acknowledgement, a restart on the
/// pending batch over the results returned so far, over each longer prefix of the newer results and over all of them,
/// and a replay from a copy of the pending anchor, must deliver the same batch with the same peripherals; after the run
/// every replay token must deliver its batch again. Some fetches are cancelled while the native fetch runs first; the
/// next fetch must deliver the batch a cancelled one delivered. A fetch may fail only with `assemblyCapacityExceeded`,
/// only under limits smaller than the defaults, and only when the results before the first batch of a fetch with the
/// default limits don't fit those limits. Set `GROVE_FETCHER_PROPERTY_SEED` (with the `TEST_RUNNER_` prefix for the
/// simulator) to run one seed.
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
        let mode = HoldMode.allCases.randomElement(using: &random) ?? .held
        let stream = Fixture.NativeStream(start: mode.start)
        let input = Self.ecgInput(stream: stream, mode: mode, using: &random)
        let batchSize = Int.random(in: 1...4, using: &random)
        let smallLimits = random.chance(0.5)
        let limits = smallLimits
            ? try SensorKitECGProcessingLimits(
                maximumEntries: Int.random(in: 8...40, using: &random), maximumSessions: Int.random(in: 2...6, using: &random)
            )
            : SensorKitECGProcessingLimits()
        let reveals = input.cuts.dropLast().filter { _ in random.chance(0.4) } + [input.cuts.last ?? 0]
        let context = "seed \(seed), batch size \(batchSize), limits \(limits.maximumEntries)/\(limits.maximumSessions), \(mode)"
        let reference = try await Fixture.fetch(input.results, anchor: .ephemeral(startDate: stream.start), batchSize: 1_000_000)
            .flatMap(\.samples)
        for session in input.intact {
            #expect(reference.contains(try #require(try SensorKitECGSession.process(session).first)), "\(context): whole session delivered")
        }
        var run = ECGRun(input: input, reveals: reveals, batchSize: batchSize, limits: limits, context: context, start: stream.start, seed: seed)
        guard try await run.run() || !smallLimits else {
            // The first fetch failed under the small limits, so the run repeats with the default ones.
            run = ECGRun(input: input, reveals: reveals, batchSize: batchSize, limits: .init(), context: context, start: stream.start, seed: seed)
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
    func ecgSessionsMatchASequentialModel(seed: UInt64) async throws {
        var random = SeededGenerator(seed: seed)
        let mode = HoldMode.allCases.randomElement(using: &random) ?? .held
        let stream = Fixture.NativeStream(start: mode.start)
        let input = Self.ecgInput(stream: stream, mode: mode, using: &random)
        let model = Self.modelSessions(of: input.results, oldBefore: input.oldBefore)
        let reference = try await Fixture.fetch(input.results, anchor: .ephemeral(startDate: stream.start), batchSize: 1_000_000)
            .flatMap(\.samples)
        #expect(reference == model, "seed \(seed), \(mode): one fetch against the sequential model")
        #expect(Set(reference.map(\.sessionIdentifier)).count == reference.count, "seed \(seed), \(mode): a session delivered twice")
        // Fetches that each deliver one batch, acknowledge it and start again with the configured batch size.
        for batchSize in 1...4 {
            var delivered: [SensorKitECGSession] = []
            let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
            for _ in 0..<200 {
                let cursor = try anchor.value.nativeTimestamp ?? -Double.infinity
                guard let batch = try await Self.firstECGBatch(
                    of: input.results.filter { $0.timestamp.rawValue > cursor }, anchor: anchor, batchSize: batchSize, limits: .init()
                ) else {
                    break
                }
                try await batch.acknowledge()
                delivered += batch.samples
            }
            #expect(delivered == model, "seed \(seed), \(mode), batch size \(batchSize): acknowledged fetches against the model")
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
    /// session, with results without groups between them and peripherals that may be unnamed, followed by a complete
    /// session that ends every unfinished one.
    @available(iOS 18, *)
    private static func ecgInput(
        stream: ECGBatchBoundaryTests.NativeStream, mode: HoldMode, using random: inout SeededGenerator
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
            if random.chance(0.15) {
                batches.append([])
            }
            earlier.append(groups)
        }
        for identifier in Self.interleave(&batches, sparing: fragments, using: &random) {
            whole[identifier] = nil
        }
        batches.append(ECGBatchBoundaryTests.NativeStream.session("final-session", offset: 1000))
        whole["final-session"] = batches.last
        let peripherals: [SensorKit.SourceDeviceInfo?] = [
            nil, SensorKit.SourceDeviceInfo(localIdentifier: "peripheral-1"), SensorKit.SourceDeviceInfo(localIdentifier: "peripheral-2")
        ]
        // In the mixed mode, the results from this index on are newer than the hold cutoff.
        let split = mode == .mixed ? Int.random(in: 0...batches.count, using: &random) : batches.count
        var seconds = 0
        var oldBefore = mode == .held ? -Double.infinity : Double.infinity
        var results: [NativeResult] = []
        for (index, groups) in batches.enumerated() {
            seconds += [0, 1, 1, 2].randomElement(using: &random) ?? 1
            if index == split {
                seconds += 2 * 3600
                oldBefore = stream.time(seconds).rawValue
            }
            let peripheral = peripherals[Int.random(in: 0..<peripherals.count, using: &random)]
            results.append(NativeResult(groups: groups, timestamp: stream.time(max(seconds, 1)), sourceDevice: peripheral))
        }
        let cuts = Self.cuts(of: results, oldBefore: oldBefore)
        return ECGInput(results: results, intact: Array(whole.values), oldBefore: oldBefore, cuts: cuts)
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
    /// The end of a fetch finishes the unfinished sessions when their latest result is older than the hold cutoff. A
    /// fetch that ends inside such a session, or before a repeated fragment of it, would finish it without its later
    /// data, which one fetch over all results doesn't. A restart or replay of such a batch fails, as documented, so the
    /// fetches don't end there. A session whose data before the cut includes a result newer than the cutoff is held.
    private static func cuts(of results: [NativeResult], oldBefore: Double) -> [Double] {
        let distinct = Array(Set(results.map(\.timestamp.rawValue))).sorted()
        var times: [String: [Double]] = [:]
        for result in results {
            for identifier in Set(result.groups.map(\.identifier)) {
                times[identifier, default: []].append(result.timestamp.rawValue)
            }
        }
        return distinct.filter { cut in
            !times.values.contains { times in
                guard let first = times.first, let last = times.last, first <= cut, cut < last else {
                    return false
                }
                return times.filter { $0 <= cut }.allSatisfy { $0 < oldBefore }
            }
        }
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

    /// Runs a native fetch whose consumer is cancelled after `count` results, or before the end of the fetch.
    @available(iOS 18, *)
    fileprivate static func cancelledECGFetch(
        of results: [NativeResult],
        anchor: ManagedQueryAnchor,
        batchSize: Int,
        limits: SensorKitECGProcessingLimits,
        cancellingAfter count: Int
    ) async throws -> Result<ECGBatchBoundaryTests.Batch?, any Error> {
        let fetcher = ECGBatchBoundaryTests.fetcher(anchor: anchor, batchSize: batchSize, limits: limits)
        try fetcher.startNativeFetchForTesting()
        nonisolated(unsafe) let reader = fetcher
        nonisolated(unsafe) let input = results
        let task = Task {
            try await reader.next(isolation: nil)
        }
        let (finished, continuation) = AsyncStream<Void>.makeStream()
        Thread.detachNewThread {
            defer {
                continuation.finish()
            }
            for (index, result) in input.enumerated() {
                if index == count {
                    task.cancel()
                }
                guard reader.processECGGroupsForTesting(result.groups, timestamp: result.timestamp, sourceDevice: result.sourceDevice) else {
                    return
                }
            }
            task.cancel()
            reader.completeFetchForTesting()
        }
        let outcome = await task.result
        fetcher.stopForTesting()
        for await _ in finished {}
        return outcome
    }

    /// The results a fetch processes before it delivers a first batch that ends at `boundary`: the results up to the
    /// boundary, the later ones with data of the sessions in them, and the result after those, which ends them.
    fileprivate static func resultsBeforeDelivery(of results: [NativeResult], boundary: Double) -> [NativeResult] {
        let sessions = Set(results.filter { $0.timestamp.rawValue <= boundary }.flatMap { $0.groups.map(\.identifier) })
        let last = results.lastIndex { result in
            result.timestamp.rawValue <= boundary || result.groups.contains { sessions.contains($0.identifier) }
        }
        return Array(results.prefix(last.map { $0 + 2 } ?? 1))
    }

    /// Whether the results don't fit `limits` in one assembly, which makes room as a fetch without a sample to deliver
    /// does.
    @available(iOS 18, *)
    fileprivate static func exceedsLimits(_ results: [NativeResult], limits: SensorKitECGProcessingLimits) -> Bool {
        var assembly = SensorKitECGAssembly(limits: limits)
        var hasSessions = false
        for result in results {
            hasSessions = !assembly.finishPending(supersededBy: result.groups).sessions.isEmpty || hasSessions
            while true {
                do {
                    hasSessions = try !assembly.append(result.groups, at: result.timestamp.rawValue).sessions.isEmpty || hasSessions
                    break
                } catch {
                    guard !hasSessions, assembly.forgetFinishedSessions() else {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The sessions one fetch over `results` delivers under the documented session rules, without batches, retained
    /// results or limits: a session starts at a result with its begin state, and ends with all its states, when a
    /// result carries data of another session and none of its own, or at the end of the fetch when its latest result is
    /// older than `oldBefore`. A later fragment of an ended session, and a fragment of a session that hasn't started
    /// whose result lacks its begin state, are skipped.
    @available(iOS 18, *)
    fileprivate static func modelSessions(of results: [NativeResult], oldBefore: Double) -> [SensorKitECGSession] {
        var pending: [String: (groups: [SensorKitECGSession.InputGroup], latest: Double)] = [:]
        var finished: Set<String> = []
        var delivered: [SensorKitECGSession] = []
        func merged(_ groups: [SensorKitECGSession.InputGroup]) throws -> [SensorKitECGSession.InputGroup] {
            var result: [SensorKitECGSession.InputGroup] = []
            for state in [SRElectrocardiogramSession.State.begin, .active, .end] {
                let parts = groups.filter { $0.state == state }
                guard let first = parts.first else {
                    continue
                }
                guard parts.allSatisfy({ $0.guidance == first.guidance }) else {
                    throw SensorKitECGSession.ProcessingError.inconsistentSession
                }
                result.append(.init(identifier: first.identifier, state: state, guidance: first.guidance, readings: parts.flatMap(\.readings)))
            }
            return result
        }
        func end(_ identifiers: some Sequence<String>, complete: Bool) {
            var sessions: [SensorKitECGSession] = []
            for identifier in identifiers {
                if let groups = pending.removeValue(forKey: identifier)?.groups, let groups = try? merged(groups) {
                    sessions += complete ? ((try? SensorKitECGSession.process(groups)) ?? []) : SensorKitECGSession.processLeniently(groups)
                }
                finished.insert(identifier)
            }
            delivered += sessions.sorted(by: SensorKitECGSession.precedes)
        }
        for result in results {
            let groups = result.groups
            let accepted = groups.filter { group in
                !finished.contains(group.identifier) && !group.identifier.isEmpty
                    && (pending[group.identifier] != nil || groups.contains { $0.identifier == group.identifier && $0.state == .begin })
            }
            let current = Set(accepted.map(\.identifier))
            if !current.isEmpty {
                end(pending.keys.filter { !current.contains($0) }, complete: false)
            }
            for group in accepted {
                pending[group.identifier, default: ([], result.timestamp.rawValue)].groups.append(group)
                pending[group.identifier]?.latest = result.timestamp.rawValue
            }
            end(pending.filter { Set($0.value.groups.map(\.state)) == [.begin, .active, .end] }.keys, complete: true)
        }
        if let latest = pending.values.map(\.latest).max(), latest < oldBefore {
            end(Array(pending.keys), complete: false)
        }
        return delivered
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
