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


/// Randomized inputs for the sample-count fetcher, checked against one fetch over all results.
///
/// Every batch of a sequence of fetches with acknowledgement must together hold exactly what one fetch over all results
/// delivers, in order. Before each acknowledgement, a restart over the same results and over the results with newer
/// ones appended, and a replay from a copy of the pending anchor, must deliver the same batch. A fetch may fail only with
/// `assemblyCapacityExceeded`, and only under limits smaller than the defaults. Set `GROVE_FETCHER_PROPERTY_SEED` (with
/// the `TEST_RUNNER_` prefix for the simulator) to run one seed.
@Suite(.timeLimit(.minutes(1)))
struct SampleCountFetcherPropertyTests {
    private typealias Fixture = ECGBatchBoundaryTests
    private typealias NativeResult = ECGBatchBoundaryTests.NativeResult

    static let seeds: [UInt64] = {
        if let seed = ProcessInfo.processInfo.environment["GROVE_FETCHER_PROPERTY_SEED"].flatMap(UInt64.init) {
            return [seed]
        }
        return Array(1...1000)
    }()

    @Test(arguments: seeds)
    @available(iOS 18, *)
    func ecgBatchesMatchOneFetchOverAllResults(seed: UInt64) async throws {
        var random = SeededGenerator(seed: seed)
        let stream = Fixture.NativeStream()
        let results = Self.ecgResults(stream: stream, using: &random)
        let reference = try await Fixture.fetch(results, anchor: .ephemeral(startDate: stream.start), batchSize: 1_000_000)
            .flatMap(\.samples)
        let batchSize = Int.random(in: 1...4, using: &random)
        let smallLimits = random.chance(0.5)
        let limits = smallLimits
            ? try SensorKitECGProcessingLimits(
                maximumEntries: Int.random(in: 8...40, using: &random), maximumSessions: Int.random(in: 2...6, using: &random)
            )
            : SensorKitECGProcessingLimits()
        let reveals = Self.reveals(of: results.map(\.timestamp.rawValue), using: &random)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: stream.start)
        let context = "seed \(seed), batch size \(batchSize), limits \(limits.maximumEntries)/\(limits.maximumSessions)"
        var delivered: [SensorKitECGSession] = []
        var revealIndex = 0
        for _ in 0..<500 {
            let cursor = try anchor.value.nativeTimestamp ?? -Double.infinity
            let visible = results.filter { $0.timestamp.rawValue > cursor && $0.timestamp.rawValue <= reveals[revealIndex] }
            let batch: Fixture.Batch?
            do {
                batch = try await Self.firstECGBatch(of: visible, anchor: anchor, batchSize: batchSize, limits: limits)
            } catch SensorKitECGSession.ProcessingError.assemblyCapacityExceeded where smallLimits {
                #expect(reference.starts(with: delivered), "\(context): delivered before the capacity failure")
                return
            } catch {
                Issue.record("\(context): fetch threw \(error)")
                return
            }
            guard let batch else {
                guard revealIndex < reveals.count - 1 else {
                    break
                }
                revealIndex += 1
                continue
            }
            let newer = results.filter { $0.timestamp.rawValue > cursor }
            let pendingAnchor = batch.info.replayToken.anchor
            let pendingCount = try #require(pendingAnchor.pendingBatch).sampleCount
            let checks = [
                Check(label: "restart", input: visible, anchor: anchor),
                Check(label: "restart with newer data", input: newer, anchor: anchor),
                Check(label: "replay", input: newer, anchor: .ephemeral(anchor: pendingAnchor))
            ]
            for check in checks {
                do {
                    let again = try await Self.firstECGBatch(of: check.input, anchor: check.anchor, batchSize: pendingCount, limits: limits)
                    #expect(again?.samples == batch.samples, "\(context): \(check.label) samples")
                    #expect(again?.info.replayToken == batch.info.replayToken, "\(context): \(check.label) token")
                } catch {
                    Issue.record("\(context): \(check.label) threw \(error)")
                }
            }
            try await batch.acknowledge()
            delivered += batch.samples
        }
        #expect(delivered == reference, "\(context): all batches against one fetch")
    }

    @Test(arguments: seeds)
    @available(iOS 18, *)
    func otherSensorBatchesMatchOneFetchOverAllResults(seed: UInt64) async throws {
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
        let reveals = Self.reveals(of: results.map(\.timestamp.rawValue), using: &random)
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
            let newer = results.filter { $0.timestamp.rawValue > cursor }
            let pendingAnchor = batch.info.replayToken.anchor
            let pendingCount = try #require(pendingAnchor.pendingBatch).sampleCount
            let checks = [
                Check(label: "restart", input: visible, anchor: anchor),
                Check(label: "restart with newer data", input: newer, anchor: anchor),
                Check(label: "replay", input: newer, anchor: .ephemeral(anchor: pendingAnchor))
            ]
            for check in checks {
                do {
                    let again = try await Self.firstBatch(of: check.input, anchor: check.anchor, batchSize: pendingCount)
                    #expect(again?.samples.map(\.index) == batch.samples.map(\.index), "\(context): \(check.label) samples")
                    #expect(again?.info.replayToken == batch.info.replayToken, "\(context): \(check.label) token")
                } catch {
                    Issue.record("\(context): \(check.label) threw \(error)")
                }
            }
            try await batch.acknowledge()
            delivered += batch.samples.map(\.index)
        }
        #expect(delivered == reference, "\(context): all batches against all usable samples")
    }
}


extension SampleCountFetcherPropertyTests {
    /// The timestamps up to which successive fetches see the results: cuts after some distinct timestamps, then all.
    private static func reveals(of timestamps: [Double], using random: inout SeededGenerator) -> [Double] {
        let distinct = Array(Set(timestamps)).sorted()
        return distinct.dropLast().filter { _ in random.chance(0.4) } + [distinct.last ?? 0]
    }

    /// Native ECG results of sessions that may be split across results, share timestamps, lack states or voltage,
    /// start before the previous session ended, or repeat a fragment of an earlier session, followed by a complete
    /// session that ends every unfinished one.
    @available(iOS 18, *)
    private static func ecgResults(stream: ECGBatchBoundaryTests.NativeStream, using random: inout SeededGenerator) -> [NativeResult] {
        var batches: [[SensorKitECGSession.InputGroup]] = []
        var earlier: [[SensorKitECGSession.InputGroup]] = []
        for index in 0..<Int.random(in: 1...10, using: &random) {
            var groups = ECGBatchBoundaryTests.NativeStream.session("session-\(index)", offset: Double(index) * 10)
            switch Int.random(in: 0..<8, using: &random) {
            case 0:
                groups.removeLast()
            case 1:
                groups = groups.map { group in
                    SensorKitECGSession.InputGroup(
                        identifier: group.identifier,
                        state: group.state,
                        guidance: group.guidance,
                        readings: group.readings.map { .init(date: $0.date, frequency: $0.frequency, lead: $0.lead, samples: []) }
                    )
                }
            case 2:
                groups.removeFirst()
            case 3:
                groups.removeAll { $0.state == .active }
            default:
                break
            }
            var parts: [[SensorKitECGSession.InputGroup]] = []
            for group in groups {
                if parts.isEmpty || random.chance(0.5) {
                    parts.append([group])
                } else {
                    parts[parts.count - 1].append(group)
                }
            }
            if let last = batches.last, random.chance(0.4), let first = parts.first {
                // The session starts in the result that holds the previous session's last data.
                batches[batches.count - 1] = last + first
                parts.removeFirst()
            }
            batches += parts
            if let fragment = earlier.randomElement(using: &random)?.first(where: { $0.state == .active }), random.chance(0.2) {
                batches.append([fragment])
            }
            earlier.append(groups)
        }
        batches.append(ECGBatchBoundaryTests.NativeStream.session("final-session", offset: 1000))
        var seconds = 0
        return batches.map { groups in
            seconds += [0, 1, 1, 2].randomElement(using: &random) ?? 1
            return stream.result(groups, at: max(seconds, 1))
        }
    }

    /// Runs a native fetch up to its first batch and abandons it there, or returns `nil` when it delivers none.
    @available(iOS 18, *)
    private static func firstECGBatch(
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
