//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
public import ModelsR4


/// The source-store coordinate of one converted record, for local outbox and crosswalk work.
///
/// The uuid never enters the graph; wire disclosure stays with the native identifier policy, and
/// debug output withholds it too.
@DebugDescription
public struct HealthKitSourceRecord: Hashable, Sendable, CustomDebugStringConvertible {
    public let uuid: UUID
    public let type: HealthKitSourceType

    public var debugDescription: String {
        "HealthKitSourceRecord(type: \(type.rawValue), uuid: <redacted>)"
    }

    public init(uuid: UUID, type: HealthKitSourceType) {
        self.uuid = uuid
        self.type = type
    }
}


/// One complete conversion graph, and what its record carried that the graph does not.
///
/// Resources have no logical `Resource.id` unless the caller supplied a repository id.
/// Deterministic UUIDv5 Bundle fullUrls connect graph entries.
public struct HealthKitConversion: Sendable {
    public let source: HealthKitSourceRecord
    public let identifiers: ExchangeGraphIdentifiers
    public let graph: ExchangeGraph
    /// Empty when the graph carries everything its record supplied.
    public let warnings: [HealthKitConversionWarning]

    public var bundle: ModelsR4.Bundle { graph.bundle }

    public init(
        source: HealthKitSourceRecord,
        identifiers: ExchangeGraphIdentifiers,
        graph: ExchangeGraph,
        warnings: [HealthKitConversionWarning] = []
    ) {
        self.source = source
        self.identifiers = identifiers
        self.graph = graph
        self.warnings = warnings
    }
}

#endif
