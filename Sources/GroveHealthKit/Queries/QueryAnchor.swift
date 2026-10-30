//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import HealthKit


/// Used by anchor queries to keep track of the last-seen state of the HealthKit database.
///
/// The `QueryAnchor` type wraps around HealthKit's `HKQueryAnchor` type, adding support for `Codable`-based serialization,
/// allowing you to persist your query's last-seen database state across multiple app launches:
///
/// ```swift
/// func loadAnchor() throws -> QueryAnchor? {
///     guard let data = try? Data(contentsOf: anchorUrl) else {
///         return nil
///     }
///     return try? JSONDecoder().decode(QueryAnchor.self, from: data)
/// }
///
/// func storeAnchor(_ anchor: QueryAnchor) throws {
///     let data = try JSONEncoder().encode(anchor)
///     try data.write(to: anchorUrl)
/// }
///
/// // fetches all heart rate samples since the last call
/// func fetchNewSamples() async throws -> [HKQuantitySample] {
///     // Fetch the last-used anchor,
///     // or create an empty new one for the initial launch
///     var anchor = try loadAnchor() ?? QueryAnchor()
///     let samples = try await healthKit.query(
///         .heartRate,
///         timeRange: .today,
///         anchor: &anchor
///     )
///     try storeAnchor(anchor)
///     return samples
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public struct QueryAnchor: Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case anchor
        case queriedAt
    }

    let hkAnchor: HKQueryAnchor?
    /// When the query that produced this anchor was issued, as recorded by ``CollectSamples`` when it
    /// commits the anchor; `nil` otherwise.
    ///
    /// The anchor captures the health store no earlier than this instant, so every deletion a later
    /// query reports from it happened after this instant.
    public let queriedAt: Date?

    /// Creates a new, empty `QueryAnchor`.
    ///
    /// Use this initializer to create a "fresh" anchor, which when used in a query will match against all samples in the database.
    public init() {
        self.hkAnchor = nil
        self.queriedAt = nil
    }

    /// Creates a `QueryAnchor` from a HealthKit `HKQueryAnchor`.
    public init(_ hkAnchor: HKQueryAnchor) {
        self.init(hkAnchor, queriedAt: nil)
    }

    init(_ hkAnchor: HKQueryAnchor?, queriedAt: Date?) {
        self.hkAnchor = hkAnchor
        self.queriedAt = queriedAt
    }

    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            hkAnchor = try container.decodeIfPresent(Data.self, forKey: .anchor).map(Self.unarchive)
            queriedAt = try container.decodeIfPresent(Date.self, forKey: .queriedAt)
        } else {
            // Anchors persisted before `queriedAt` existed are a bare archive or null.
            let container = try decoder.singleValueContainer()
            hkAnchor = container.decodeNil() ? nil : try Self.unarchive(container.decode(Data.self))
            queriedAt = nil
        }
    }

    private static func unarchive(_ data: Data) throws -> HKQueryAnchor {
        guard let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) else {
            throw DecodingError.valueNotFound(HKQueryAnchor.self, .init(codingPath: [], debugDescription: ""))
        }
        return anchor
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(
            hkAnchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) },
            forKey: .anchor
        )
        try container.encodeIfPresent(queriedAt, forKey: .queriedAt)
    }
}

#endif
