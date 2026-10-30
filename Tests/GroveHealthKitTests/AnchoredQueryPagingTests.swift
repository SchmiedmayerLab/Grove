//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKit
import HealthKit
import Testing


@MainActor
@Suite("Anchored collection paging")
struct AnchoredQueryPagingTests {
    private enum HandoffError: Error {
        case unavailable
    }

    @Test("Pages checkpoint separately and deletion-only pages retain the old time bound", arguments: [false, true])
    func drainsPages(hasExistingBound: Bool) async throws {
        let oldBound = Date(timeIntervalSince1970: 100)
        var persisted = hasExistingBound ? QueryAnchor(HKQueryAnchor(fromValue: 1), queriedAt: oldBound) : nil
        let initial = persisted
        let deletion = try #require(HKDeletedObject.make())
        var fetched = 0
        var commits: [QueryAnchor] = []
        let startedAt = Date.now
        try await AnchoredQueryPaging.drain(
            from: initial,
            query: { anchor, limit in
                #expect(limit == 500)
                #expect(anchor == persisted ?? QueryAnchor())
                #expect(commits.count == fetched)
                fetched += 1
                return .init(
                    added: fetched == 1 ? [42] : [],
                    deleted: fetched == 2 ? [deletion] : [],
                    anchor: HKQueryAnchor(fromValue: fetched + 1)
                )
            },
            commit: { page, expected, queriedAt in
                #expect(expected == persisted)
                let desired = QueryAnchor(page.anchor, queriedAt: queriedAt)
                persisted = desired
                commits.append(desired)
                return desired
            }
        )
        #expect(fetched == 3)
        #expect(commits.prefix(2).allSatisfy { $0.queriedAt == initial?.queriedAt })
        #expect(try #require(persisted?.queriedAt) >= startedAt)
    }

    @Test("A failed handoff resumes after the last committed page")
    func resumesAfterFailure() async throws {
        var persisted: QueryAnchor?
        var failing = true
        var fetched: [Int] = []
        func drain() async throws {
            try await AnchoredQueryPaging.drain(
                from: persisted,
                query: { anchor, _ in
                    let page = anchor.hkAnchor == nil ? 1 : (anchor.hkAnchor == HKQueryAnchor(fromValue: 1) ? 2 : 3)
                    fetched.append(page)
                    return .init(added: page < 3 ? [page] : [], deleted: [], anchor: HKQueryAnchor(fromValue: page))
                },
                commit: { page, expected, queriedAt in
                    #expect(expected == persisted)
                    if failing, page.added == [2] {
                        throw HandoffError.unavailable
                    }
                    let desired = QueryAnchor(page.anchor, queriedAt: queriedAt)
                    persisted = desired
                    return desired
                }
            )
        }
        await #expect(throws: HandoffError.unavailable) {
            try await drain()
        }
        #expect(persisted?.hkAnchor == HKQueryAnchor(fromValue: 1))
        #expect(persisted?.queriedAt == nil)
        failing = false
        try await drain()
        #expect(fetched == [1, 2, 2, 3])
    }

    @Test("Cancellation never fetches a later page or commits a cancelled query", arguments: [false, true])
    func cancellation(cancelDuringQuery: Bool) async {
        var fetched = 0
        var committed = 0
        let task = Task { @MainActor in
            try await AnchoredQueryPaging.drain(
                from: nil,
                query: { _, _ in
                    fetched += 1
                    if cancelDuringQuery {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    return .init(added: [1], deleted: [], anchor: HKQueryAnchor(fromValue: 1))
                },
                commit: { page, _, queriedAt in
                    committed += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                    return QueryAnchor(page.anchor, queriedAt: queriedAt)
                }
            )
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(fetched == 1)
        #expect(committed == (cancelDuringQuery ? 0 : 1))
    }
}

#endif
