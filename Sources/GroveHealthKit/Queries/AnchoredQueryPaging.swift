//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
enum AnchoredQueryPaging {
    struct Page<Sample> {
        let added: [Sample]
        let deleted: [HKDeletedObject]
        let anchor: HKQueryAnchor?
    }

    static let pageSize = 500

    /// Commits each page before fetching another, including deletion-only pages.
    static func drain<Sample>(
        from initialAnchor: QueryAnchor?,
        query: (QueryAnchor, Int) async throws -> Page<Sample>,
        commit: (Page<Sample>, QueryAnchor?, Date?) async throws -> QueryAnchor
    ) async throws {
        var expected = initialAnchor
        while true {
            try Task.checkCancellation()
            let queriedAt = Date.now
            let page = try await query(expected ?? QueryAnchor(), pageSize)
            try Task.checkCancellation()
            let isCaughtUp = page.added.isEmpty && page.deleted.isEmpty
            // A limited result can stop before deletions that predate this query. Only an empty
            // page proves the anchor has caught up enough to advance the deletion-time bound.
            expected = try await commit(page, expected, isCaughtUp ? queriedAt : expected?.queriedAt)
            if isCaughtUp {
                return
            }
        }
    }
}

#endif
