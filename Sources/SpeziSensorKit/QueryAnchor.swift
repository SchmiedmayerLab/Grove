//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

private import Foundation
private import SpeziFoundation
import SpeziLocalStorage


/// Used to keep track of previously-fetched SensorKit samples to avoid duplicates when querying data.
@available(iOS 17, *)
struct QueryAnchor: Hashable, Codable, Sendable {
    /// The most-recent point in time for which data was queried.
    ///
    /// Note that this refers to the upper bound of the time range *for* which data was queried, not the point in time *at* which the query took place.
    let timestamp: Date
    
    /// Creates a new, empty `QueryAnchor`.
    init() {
        self.timestamp = .distantPast
    }
    
    /// Creates a new `QueryAnchor` for the specified timestamp.
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        timestamp = try container.decode(Date.self)
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(timestamp)
    }
}


/// A `QueryAnchor` that is backed using Spezi LocalStorage.
@available(iOS 17, *)
public final class ManagedQueryAnchor: Sendable {
    private let get: @Sendable () throws -> QueryAnchor
    private let set: @Sendable (QueryAnchor) throws -> Void
    
    var value: QueryAnchor {
        get throws {
            try get()
        }
    }
    
    private init(
        get: @escaping @Sendable () throws -> QueryAnchor,
        set: @escaping @Sendable (QueryAnchor) throws -> Void
    ) {
        self.get = get
        self.set = set
    }
    
    convenience init(storageKey: LocalStorageKey<QueryAnchor>, in localStorage: LocalStorage) {
        self.init {
            try localStorage.load(storageKey) ?? QueryAnchor()
        } set: {
            try localStorage.store($0, for: storageKey)
        }
    }
    
    func update(_ newValue: QueryAnchor) throws {
        if let oldValue = try? get(), oldValue == newValue {
            return
        }
        try set(newValue)
    }
}


@available(iOS 17, *)
extension ManagedQueryAnchor {
    /// Creates an ephemeral Managed Query Anchor, that does not persist itself to disk.
    ///
    /// Intended primarily for testing purposes, but also useful for performing one-off batched fetches.
    public static func ephemeral(startDate: Date? = nil) -> Self {
        final class EphemeralStorage: Sendable {
            nonisolated(unsafe) var anchor: QueryAnchor
            let lock = RWLock()
            init(anchor: QueryAnchor) {
                self.anchor = anchor
            }
        }
        let storage = EphemeralStorage(
            anchor: startDate.map { QueryAnchor(timestamp: $0) } ?? QueryAnchor()
        )
        return Self {
            storage.lock.withReadLock {
                storage.anchor
            }
        } set: { newAnchor in
            storage.lock.withWriteLock {
                storage.anchor = newAnchor
            }
        }
    }
}
