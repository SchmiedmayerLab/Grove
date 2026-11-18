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


@Suite
struct NativeQueryClockTests {
    @Test
    @available(iOS 18, *)
    func retainedNativeBoundarySurvivesWallClockChangesWithoutChangingIdentity() throws {
        let firstDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let original = QueryAnchor(timestamp: firstDate, resetGeneration: 3, batchSequence: 7, streamPartition: 42)
        let retained = original.retainingNativeTimestamp(10)
        #expect(retained.acquisitionBatchCoordinate == original.acquisitionBatchCoordinate)
        let pending = retained.preparing(.sampleCount(deliveryTimestamp: firstDate.addingTimeInterval(5), sampleCount: 2, nativeTimestamp: 15))
        let restored = try JSONDecoder().decode(QueryAnchor.self, from: JSONEncoder().encode(pending))
        let boundary = try #require(restored.pendingBatch)
        #expect(boundary.matchesSampleCountDelivery(.sampleCount(
            deliveryTimestamp: firstDate.addingTimeInterval(100), sampleCount: 2, nativeTimestamp: 15
        )))
        #expect(!boundary.matchesSampleCountDelivery(.sampleCount(
            deliveryTimestamp: boundary.upperBound, sampleCount: 2, nativeTimestamp: 15.nextUp
        )))
        let committed = try restored.committingPendingBatch()
        #expect(committed.timestamp == boundary.upperBound)
        #expect(committed.nativeTimestamp == 15)
        #expect(committed.batchSequence == 8)
        #expect(restored.acquisitionBatchCoordinate == pending.acquisitionBatchCoordinate)
    }

    @Test
    func callbackProjectionUsesTheRetainedPairAfterAWallClockShift() throws {
        let first = QueryNativeClock(nativeReferenceBits: Double(100).bitPattern, wallReference: Date(timeIntervalSinceReferenceDate: 1_000))
        let later = QueryNativeClock(nativeReferenceBits: Double(100).bitPattern, wallReference: first.wallReference.addingTimeInterval(30))
        let restored = try JSONDecoder().decode(QueryNativeClock.self, from: JSONEncoder().encode(first))
        #expect(restored.date(for: 120) == first.date(for: 120))
        #expect(restored.date(for: 120) != later.date(for: 120))
        #expect(try JSONEncoder().encode(restored.date(for: 120)) == JSONEncoder().encode(first.date(for: 120)))
    }

    @Test
    func legacyPendingBoundaryRemainsUnchangedAndUsesItsOriginalComparison() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let pending = QueryAnchor(timestamp: date, pendingBatch: .sampleCount(deliveryTimestamp: date, sampleCount: 1), streamPartition: 9)
        let bytes = try JSONEncoder().encode(pending)
        let restored = try JSONDecoder().decode(QueryAnchor.self, from: bytes)
        #expect(restored == pending)
        #expect(restored.nativeTimestamp == nil)
        let boundary = try #require(restored.pendingBatch)
        #expect(boundary.matchesSampleCountDelivery(.sampleCount(deliveryTimestamp: date, sampleCount: 1, nativeTimestamp: 17)))
        #expect(!boundary.matchesSampleCountDelivery(.sampleCount(deliveryTimestamp: date.addingTimeInterval(1), sampleCount: 1)))
    }

    @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
    func decodingRejectsNonfiniteNativeCoordinates(_ invalid: Double) throws {
        let anchor = QueryAnchor(timestamp: Date(timeIntervalSinceReferenceDate: 1_000), nativeTimestampBits: invalid.bitPattern)
        let bytes = try JSONEncoder().encode(anchor)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(QueryAnchor.self, from: bytes) }
        let pending = QueryAnchor().preparing(.sampleCount(deliveryTimestamp: .now, sampleCount: 1, nativeTimestamp: invalid))
        let pendingBytes = try JSONEncoder().encode(pending)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(QueryAnchor.self, from: pendingBytes) }
    }

    @Test
    @available(iOS 18, *)
    func nativeRequestUsesThePersistedCoordinateWithoutAnotherWallClockConversion() throws {
        let anchor = ManagedQueryAnchor.ephemeral(startDate: Date.now.addingTimeInterval(-120))
        let original = try anchor.value
        let retained = original.retainingNativeTimestamp(123_456.75)
        #expect(try anchor.update(from: original, to: retained))
        var observed: UInt64?
        let fetcher = AnchoredFetcher<SRElectrocardiogramSample>.SampleCountBasedFetcher(
            sensor: .ecg,
            batchSize: 1,
            anchor: anchor,
            device: .current,
            startFetch: { _, request in observed = request.from.rawValue.bitPattern }
        )
        try fetcher.startNativeFetchForTesting()
        #expect(observed == retained.nativeTimestampBits)
        #expect(try anchor.value.timestamp == retained.timestamp)
        #expect(try anchor.value.nativeTimestampBits == retained.nativeTimestampBits)
        #expect(try anchor.value.acquisitionBatchCoordinate == retained.acquisitionBatchCoordinate)
    }

    @Test
    @available(iOS 18, *)
    func emptyCursorStartsAtTheInitialStartDateAndAnEstablishedOneIgnoresIt() throws {
        let start = Date.now.addingTimeInterval(-3_600)
        for established in [false, true] {
            let anchor = ManagedQueryAnchor.ephemeral(startDate: established ? Date.now.addingTimeInterval(-120) : nil)
            let original = try anchor.value
            var observed: Double?
            let fetcher = AnchoredFetcher<SRElectrocardiogramSample>.SampleCountBasedFetcher(
                sensor: .ecg,
                batchSize: 1,
                anchor: anchor,
                device: .current,
                initialStartDate: start,
                startFetch: { _, request in observed = request.from.rawValue }
            )
            try fetcher.startNativeFetchForTesting()
            // Converting a date to SensorKit's clock reads the current clock offset, so two conversions differ slightly.
            let expected = SRAbsoluteTime(established ? original.timestamp : start).rawValue
            #expect(abs(try #require(observed) - expected) < 1)
        }
    }
}
#endif
