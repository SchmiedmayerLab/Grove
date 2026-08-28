//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

private import Foundation
import GroveLocalStorage
import Synchronization


/// Used to keep track of previously-fetched SensorKit samples to avoid duplicates when querying data.
struct QueryAnchor: Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case timestamp
        case resetGeneration
        case batchSequence
        case pendingBatch
    }

    struct PendingBatch: Hashable, Codable, Sendable {
        enum Mode: String, Codable, Sendable {
            case sampleCount
            case timeRange
        }

        let mode: Mode
        let lowerBound: Date?
        let upperBound: Date
        let sampleCount: Int

        var timeRange: Range<Date>? {
            guard mode == .timeRange, let lowerBound else {
                return nil
            }
            return lowerBound..<upperBound
        }

        static func sampleCount(deliveryTimestamp: Date, sampleCount: Int) -> Self {
            Self(
                mode: .sampleCount,
                lowerBound: nil,
                upperBound: deliveryTimestamp,
                sampleCount: sampleCount
            )
        }

        static func timeRange(_ timeRange: Range<Date>, sampleCount: Int) -> Self {
            Self(
                mode: .timeRange,
                lowerBound: timeRange.lowerBound,
                upperBound: timeRange.upperBound,
                sampleCount: sampleCount
            )
        }
    }

    /// The most-recent point in time for which data was queried.
    ///
    /// Note that this refers to the upper bound of the time range *for* which data was queried, not the point in time *at* which the query took place.
    let timestamp: Date

    /// Monotonically increases whenever the consumer explicitly resets this cursor.
    ///
    /// Acknowledgements bind to both the timestamp and this generation, so a batch fetched before
    /// reset can never restore the reset cursor afterwards.
    let resetGeneration: UInt64

    /// Number of non-empty acquisition batches durably acknowledged in this reset generation.
    /// This advances even when SensorKit delivers consecutive batches at the same timestamp.
    let batchSequence: UInt64

    /// Durable delivery boundary of a batch exposed to a consumer but not yet acknowledged.
    ///
    /// Persisting this before the batch is yielded makes a crash retry reuse the same query mode,
    /// range or delivery timestamp, and requested sample count even if the caller changes its
    /// configured batch size after restart. SensorKit does not promise exact-content replay for
    /// that boundary; consumers that assign per-record identities must verify retried content and
    /// fail closed if SensorKit backfills or reorders the pending delivery.
    let pendingBatch: PendingBatch?

    var acquisitionBatchCoordinate: SensorKit.AcquisitionBatchCoordinate {
        SensorKit.AcquisitionBatchCoordinate(
            cursorTimestamp: timestamp,
            resetGeneration: resetGeneration,
            sequence: batchSequence
        )
    }
    
    /// Creates a new, empty `QueryAnchor`.
    init() {
        self.timestamp = .distantPast
        self.resetGeneration = 0
        self.batchSequence = 0
        self.pendingBatch = nil
    }
    
    /// Creates a new `QueryAnchor` for the specified timestamp.
    init(
        timestamp: Date,
        resetGeneration: UInt64 = 0,
        batchSequence: UInt64 = 0,
        pendingBatch: PendingBatch? = nil
    ) {
        self.timestamp = timestamp
        self.resetGeneration = resetGeneration
        self.batchSequence = batchSequence
        self.pendingBatch = pendingBatch
    }

    init(from decoder: any Decoder) throws {
        // Grove 0.5 and earlier encoded only a date. Decode that representation as generation zero
        // so the first 0.6 reset can fence any old acknowledgement deterministically.
        if let timestamp = try? decoder.singleValueContainer().decode(Date.self) {
            self.init(timestamp: timestamp)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            resetGeneration: try container.decode(UInt64.self, forKey: .resetGeneration),
            batchSequence: try container.decodeIfPresent(UInt64.self, forKey: .batchSequence) ?? 0,
            pendingBatch: try container.decodeIfPresent(PendingBatch.self, forKey: .pendingBatch)
        )
    }

    static func requireDeliveryAnchor(_ deliveredAnchor: Self?) throws -> Self {
        guard let deliveredAnchor else {
            throw SensorKit.QueryAnchorAcknowledgementError.missingDeliveryAnchor
        }
        return deliveredAnchor
    }

    func advancedPastEmptyRange(to timestamp: Date) -> Self {
        Self(
            timestamp: timestamp,
            resetGeneration: resetGeneration,
            batchSequence: batchSequence
        )
    }

    func preparing(_ pendingBatch: PendingBatch) -> Self {
        Self(
            timestamp: timestamp,
            resetGeneration: resetGeneration,
            batchSequence: batchSequence,
            pendingBatch: pendingBatch
        )
    }

    func committingPendingBatch() throws -> Self {
        guard let pendingBatch else {
            return self
        }
        let (nextSequence, overflow) = batchSequence.addingReportingOverflow(1)
        guard !overflow else {
            throw SensorKit.QueryAnchorAcknowledgementError.exhaustedBatchSequence
        }
        return Self(
            timestamp: pendingBatch.upperBound,
            resetGeneration: resetGeneration,
            batchSequence: nextSequence
        )
    }

    func reset() -> Self {
        Self(timestamp: .distantPast, resetGeneration: resetGeneration &+ 1)
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(resetGeneration, forKey: .resetGeneration)
        try container.encode(batchSequence, forKey: .batchSequence)
        try container.encodeIfPresent(pendingBatch, forKey: .pendingBatch)
    }
}


/// A `QueryAnchor` that is backed using Grove LocalStorage.
@available(iOS 18, macOS 15, watchOS 11, *)
public final class ManagedQueryAnchor: Sendable {
    private let get: @Sendable () throws -> QueryAnchor
    private let set: @Sendable (QueryAnchor) throws -> Void
    private let compareExchange: @Sendable (QueryAnchor, QueryAnchor) throws -> Bool
    
    var value: QueryAnchor {
        get throws {
            try get()
        }
    }
    
    private init(
        get: @escaping @Sendable () throws -> QueryAnchor,
        set: @escaping @Sendable (QueryAnchor) throws -> Void,
        compareExchange: @escaping @Sendable (QueryAnchor, QueryAnchor) throws -> Bool
    ) {
        self.get = get
        self.set = set
        self.compareExchange = compareExchange
    }
    
    convenience init(storageKey: LocalStorageKey<QueryAnchor>, in localStorage: LocalStorage) {
        self.init {
            try localStorage.load(storageKey) ?? QueryAnchor()
        } set: {
            try localStorage.store($0, for: storageKey)
        } compareExchange: { expected, desired in
            let persistedExpected: QueryAnchor? = expected == QueryAnchor() ? nil : expected
            if try localStorage.compareExchange(expected: persistedExpected, desired: desired, for: storageKey) {
                return true
            }
            // A default anchor may have been materialized explicitly by an older client.
            guard expected == QueryAnchor() else {
                return false
            }
            return try localStorage.compareExchange(expected: expected, desired: desired, for: storageKey)
        }
    }
    
    func update(from expectedValue: QueryAnchor, to newValue: QueryAnchor) throws -> Bool {
        if expectedValue == newValue {
            return try value == expectedValue
        }
        return try compareExchange(expectedValue, newValue)
    }

    /// Atomically resets the cursor while invalidating every acknowledgement issued beforehand.
    /// A delivered batch must be durably resolved first; reset never discards its retry boundary.
    func reset() throws {
        while true {
            let current = try value
            guard current.pendingBatch == nil else {
                throw SensorKit.QueryAnchorAcknowledgementError.unresolvedPendingBatch
            }
            guard !current.resetGeneration.addingReportingOverflow(1).overflow else {
                throw SensorKit.QueryAnchorAcknowledgementError.exhaustedResetGeneration
            }
            guard try update(from: current, to: current.reset()) else {
                continue
            }
            return
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ManagedQueryAnchor {
    /// Creates an ephemeral Managed Query Anchor, that does not persist itself to disk.
    ///
    /// Intended primarily for testing purposes, but also useful for performing one-off batched fetches.
    public static func ephemeral(startDate: Date? = nil) -> Self {
        final class EphemeralStorage: Sendable {
            let anchor: Mutex<QueryAnchor>
            init(anchor: QueryAnchor) {
                self.anchor = Mutex(anchor)
            }
        }
        let storage = EphemeralStorage(
            anchor: startDate.map { QueryAnchor(timestamp: $0) } ?? QueryAnchor()
        )
        return Self {
            storage.anchor.withLock { $0 }
        } set: { newAnchor in
            storage.anchor.withLock { $0 = newAnchor }
        } compareExchange: { expected, desired in
            storage.anchor.withLock { current in
                guard current == expected else {
                    return false
                }
                current = desired
                return true
            }
        }
    }
}
