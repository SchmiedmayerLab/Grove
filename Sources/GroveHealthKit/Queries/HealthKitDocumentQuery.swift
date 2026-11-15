//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit) && !os(watchOS)

public import Foundation
public import HealthKit


/// A document query did not produce the exact requested source envelope or authorized contents.
public enum HealthKitDocumentQueryError: Error, Equatable, Sendable {
    case invalidLimit
    case unexpectedDocument
    case unavailableDocument
}


/// One bounded CDA envelope page; its cursor is committed only after the selected payloads are durably retained.
@available(iOS 18, macOS 15, *)
public struct HealthKitDocumentEnvelopePage: Sendable {
    /// Added or updated source envelopes; XML content requires separate authorization.
    public let added: [HKCDADocumentSample]
    /// Source deletions reported with this page.
    public let deleted: [HKDeletedObject]
    /// The next candidate cursor, not an acknowledgement of application processing.
    public let nextAnchor: QueryAnchor
}


@available(iOS 18, macOS 15, *)
extension HKHealthStore {
    /// Reads a bounded page of CDA envelopes without asking for or retaining their XML contents.
    /// The caller must durably stage selected documents before retaining the returned anchor.
    nonisolated(nonsending) public func queryCDADocumentEnvelopes(
        anchor: QueryAnchor, limit: Int, predicate: NSPredicate? = nil
    ) async throws -> HealthKitDocumentEnvelopePage {
        guard (1...128).contains(limit) else { throw HealthKitDocumentQueryError.invalidLimit }
        let descriptor = HKAnchoredObjectQueryDescriptor<HKSample>(
            predicates: [.sample(type: HKDocumentType(.CDA), predicate: predicate)], anchor: anchor.hkAnchor, limit: limit
        )
        let result = try await descriptor.result(for: self)
        let documents = try result.addedSamples.map { sample in
            guard let document = sample as? HKCDADocumentSample else { throw HealthKitDocumentQueryError.unexpectedDocument }
            return document
        }
        return HealthKitDocumentEnvelopePage(added: documents, deleted: result.deletedObjects, nextAnchor: QueryAnchor(result.newAnchor))
    }

    /// Requests the contents of one exact CDA sample. HealthKit may present its per-document authorization UI.
    /// Call from an explicit foreground review action after checking application collection authority.
    /// Missing or refused contents fail explicitly; the caller must not acknowledge that sample as collected.
    @MainActor
    public func requestCDADocument(_ envelope: HKCDADocumentSample) async throws -> HKCDADocumentSample {
        try Task.checkCancellation()
        let (stream, continuation) = AsyncThrowingStream<HKCDADocumentSample, any Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let query = HKDocumentQuery(
            documentType: HKDocumentType(.CDA),
            predicate: HKQuery.predicateForObject(with: envelope.uuid),
            limit: 1,
            sortDescriptors: nil,
            includeDocumentData: true
        ) { _, results, done, error in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            guard let results, results.count <= 1 else {
                continuation.finish(throwing: HealthKitDocumentQueryError.unexpectedDocument)
                return
            }
            for result in results {
                guard let document = result as? HKCDADocumentSample, document.uuid == envelope.uuid,
                      document.startDate == envelope.startDate, document.endDate == envelope.endDate else {
                    continuation.finish(throwing: HealthKitDocumentQueryError.unexpectedDocument)
                    return
                }
                if case .dropped = continuation.yield(document) {
                    continuation.finish(throwing: HealthKitDocumentQueryError.unexpectedDocument)
                }
            }
            if done { continuation.finish() }
        }
        continuation.onTermination = { [self] _ in Task { @MainActor in self.stop(query) } }
        execute(query)
        defer { stop(query) }
        var selected: HKCDADocumentSample?
        for try await document in stream {
            try Task.checkCancellation()
            guard selected == nil else { throw HealthKitDocumentQueryError.unexpectedDocument }
            selected = document
        }
        try Task.checkCancellation()
        guard let selected, let data = selected.document?.documentData, !data.isEmpty else {
            throw HealthKitDocumentQueryError.unavailableDocument
        }
        return selected
    }
}

#endif
