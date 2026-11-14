//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

import Foundation
import GroveHealthKit
import HealthKit
import Testing


struct HealthKitDocumentQueryTests {
    @Test(arguments: [0, 129])
    func envelopeQueriesRejectAnUnboundedPageBeforeAccessingTheStore(limit: Int) async throws {
        await #expect(throws: HealthKitDocumentQueryError.invalidLimit) {
            try await HKHealthStore().queryCDADocumentEnvelopes(anchor: QueryAnchor(), limit: limit)
        }
    }

    @Test
    @MainActor
    func alreadyCancelledReviewDoesNotStartTheDocumentAuthorizationQuery() async throws {
        let sample = try HKCDADocumentSample(
            data: Data(GoldenCase.clinicalDocumentXML.utf8),
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_000_000),
            metadata: nil
        )
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HKHealthStore().requestCDADocument(sample)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

#endif
