//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Counts the exact distinct batches of one recording.
///
/// A batch key is the exact (device, identifier) pair. CoreMotion assigns one identifier to a whole batch of
/// samples and increases it for each new batch, so a recording states far fewer batches than rows. The registered
/// format does not require a batch's rows to be contiguous, so the pairs are retained: 8 bytes per batch, at most
/// about 17 MiB at the limit.
struct RecordingBatchCounter {
    /// The limit was reached; the recording cannot be summarized, which says nothing about its clinical content.
    enum Failure: Error { case indexUnavailable }

    /// The most distinct batches one recording may state: more than eleven days of one batch per second.
    static let maximumBatchCount = 1_000_000

    private var identifiersByDevice: [String: Set<UInt64>] = [:]
    private(set) var count = 0

    /// Records the row's batch, throwing ``Failure/indexUnavailable`` for a new batch beyond the limit.
    mutating func add(device: String, identifier: UInt64) throws(Failure) {
        if identifiersByDevice[device]?.contains(identifier) == true {
            return
        }
        guard count < Self.maximumBatchCount else { throw .indexUnavailable }
        identifiersByDevice[device, default: []].insert(identifier)
        count += 1
    }
}
