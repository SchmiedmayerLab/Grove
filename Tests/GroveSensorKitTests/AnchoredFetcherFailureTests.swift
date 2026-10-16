//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSensorKit
import SensorKit
import Testing

private enum AnchoredFetcherExpectedFailure: Error {
    case safeRepresentationConversion
}

private struct AnchoredFetcherSafeSample: SensorKitSampleSafeRepresentation {
    let timeRange: Range<Date>
}

private final class ConversionFailingSample: NSObject, SensorKitSampleProtocol {
    typealias SafeRepresentation = AnchoredFetcherSafeSample

    static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: ConversionFailingSample)>
    ) throws -> [AnchoredFetcherSafeSample] {
        throw AnchoredFetcherExpectedFailure.safeRepresentationConversion
    }
}

@Suite("Anchored fetch failure handling")
struct AnchoredFetcherFailureTests {
    @Test("Native sample materialization exceptions become fetch errors")
    @available(iOS 18, *)
    func nativeMaterializationExceptionBecomesError() {
        #expect(throws: (any Error).self) {
            let _: SensorKit.FetchResult<ConversionFailingSample> = try .init(
                timestamp: SRAbsoluteTime(Date(timeIntervalSinceReferenceDate: 500)),
                for: makeConversionFailingSensor()
            ) {
                NSException(name: .init("MalformedSensorKitResult"), reason: "Malformed test payload").raise()
                return NSObject()
            }
        }
    }

    @Test("Sample-count fetch fails on a malformed native result without advancing its cursor")
    @available(iOS 18, *)
    func sampleCountMalformedNativeResultRetainsCursor() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let fetcher = makeSampleCountFetcher(anchor: anchor)

        let shouldContinue = fetcher.processForTesting(
            sample: NSObject(),
            timestamp: SRAbsoluteTime(start.addingTimeInterval(1))
        )

        try #require(!shouldContinue)
        await #expect(throws: SensorKit.FetchResultTypeError.self) {
            _ = try await fetcher.next(isolation: nil)
        }
        #expect(try anchor.value.timestamp == start)
    }

    @Test("Sample-count fetch fails when safe-representation conversion throws without advancing its cursor")
    @available(iOS 18, *)
    func sampleCountConversionFailureRetainsCursor() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let fetcher = makeSampleCountFetcher(anchor: anchor)

        let shouldContinue = fetcher.processForTesting(
            sample: ConversionFailingSample(),
            timestamp: SRAbsoluteTime(start.addingTimeInterval(1))
        )

        try #require(!shouldContinue)
        await #expect(throws: AnchoredFetcherExpectedFailure.self) {
            _ = try await fetcher.next(isolation: nil)
        }
        #expect(try anchor.value.timestamp == start)
    }

    @Test("Time-path fetch stops on a malformed native result")
    @available(iOS 18, *)
    func timePathMalformedNativeResultStopsFetch() async {
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let delegate = SamplesFetcherDelegate(makeConversionFailingSensor())

        await #expect(throws: SensorKit.FetchResultTypeError.self) {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[AnchoredFetcherSafeSample], any Error>) in
                delegate.continuation = continuation
                let shouldContinue = delegate.process(
                    sample: NSObject(),
                    timestamp: SRAbsoluteTime(start.addingTimeInterval(1))
                )
                #expect(!shouldContinue)
            }
        }
    }

    @Test("Time-interval fetch failure leaves its cursor unchanged")
    @available(iOS 18, *)
    func timeIntervalFailureRetainsCursor() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 4_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        var fetcher = AnchoredFetcher<SRAmbientLightSample>.TimeIntervalBasedFetcher(
            sensor: .ambientLight,
            anchor: anchor,
            quarantineCutoff: start.addingTimeInterval(120),
            batchSize: 60,
            device: .current,
            fetchOperation: { _, _, _ in
                throw AnchoredFetcherExpectedFailure.safeRepresentationConversion
            }
        )

        await #expect(throws: AnchoredFetcherExpectedFailure.self) {
            _ = try await fetcher.next(isolation: nil)
        }
        #expect(try anchor.value.timestamp == start)
    }

    @Test("Crash retry reuses the persisted time boundary despite a changed batch size")
    @available(iOS 18, *)
    func timeIntervalCrashRetryReusesPendingBoundary() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 4_500)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let cutoff = start.addingTimeInterval(180)
        let sample = AnchoredFetcherSafeSample(timeRange: start..<start)
        var originalFetcher = AnchoredFetcher<ConversionFailingSample>.TimeIntervalBasedFetcher(
            sensor: makeConversionFailingSensor(),
            anchor: anchor,
            quarantineCutoff: cutoff,
            batchSize: 60,
            device: .current,
            fetchOperation: { _, _, _ in [sample] }
        )

        let original = try #require(try await originalFetcher.next(isolation: nil))
        #expect(original.info.timeRange == start..<start.addingTimeInterval(60))
        #expect(try anchor.value.pendingBatch?.timeRange == original.info.timeRange)

        // Simulate process loss before acknowledgement. The restarted fetcher's configured ten-
        // second size must not change a batch whose identity was already staged at sixty seconds.
        var restartedFetcher = AnchoredFetcher<ConversionFailingSample>.TimeIntervalBasedFetcher(
            sensor: makeConversionFailingSensor(),
            anchor: anchor,
            quarantineCutoff: cutoff,
            batchSize: 10,
            device: .current,
            fetchOperation: { _, _, _ in [sample] }
        )
        let retry = try #require(try await restartedFetcher.next(isolation: nil))
        #expect(retry.info.timeRange == original.info.timeRange)
        #expect(retry.info.acquisitionBatch == original.info.acquisitionBatch)
        #expect(retry.samples == original.samples)

        try await retry.acknowledge()
        let next = try #require(try await restartedFetcher.next(isolation: nil))
        #expect(next.info.timeRange == start.addingTimeInterval(60)..<start.addingTimeInterval(70))
        #expect(next.info.acquisitionBatch != retry.info.acquisitionBatch)
    }

    @Test("Reset during a native sample-count fetch rejects its terminal cursor")
    @available(iOS 18, *)
    func sampleCountResetDuringNativeFetchRejectsCursor() throws {
        let start = Date(timeIntervalSinceReferenceDate: 5_000)
        let anchor = ManagedQueryAnchor.ephemeral(startDate: start)
        let fetcher = AnchoredFetcher<ConversionFailingSample>.SampleCountBasedFetcher(
            sensor: makeConversionFailingSensor(),
            batchSize: 1,
            anchor: anchor,
            device: .current,
            startFetch: { _, _ in }
        )

        try fetcher.startNativeFetchForTesting()
        try anchor.reset()

        #expect(throws: SensorKit.QueryAnchorAcknowledgementError.staleCursor) {
            try fetcher.validateFetchCursorForTesting()
        }
        #expect(try anchor.value.timestamp == .distantPast)
        #expect(try anchor.value.resetGeneration == 1)
    }

    @Test("A non-empty sample-count delivery requires a durable acknowledgement cursor")
    @available(iOS 18, *)
    func sampleCountDeliveryWithoutAnchorFailsClosed() throws {
        let fetcher = makeSampleCountFetcher(
            anchor: .ephemeral(startDate: Date(timeIntervalSinceReferenceDate: 6_000))
        )

        #expect(throws: SensorKit.QueryAnchorAcknowledgementError.missingDeliveryAnchor) {
            try fetcher.validateDeliveryAnchorForTesting(nil)
        }
    }

    @available(iOS 18, *)
    private func makeSampleCountFetcher(
        anchor: ManagedQueryAnchor
    ) -> AnchoredFetcher<ConversionFailingSample>.SampleCountBasedFetcher {
        AnchoredFetcher<ConversionFailingSample>.SampleCountBasedFetcher(
            sensor: makeConversionFailingSensor(),
            batchSize: 1,
            anchor: anchor,
            device: .current,
            startFetch: { _, _ in }
        )
    }

    @available(iOS 18, *)
    private func makeConversionFailingSensor() -> Sensor<ConversionFailingSample> {
        Sensor(
            srSensor: .ambientLightSensor,
            displayName: "Conversion-failure test sensor",
            dataQuarantineDuration: .zero,
            sensorKitFetchReturnType: .object
        )
    }
}
