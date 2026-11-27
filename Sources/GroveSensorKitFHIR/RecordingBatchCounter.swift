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
/// format does not require a batch's rows to be contiguous, so the identifiers are retained in a set per device.
///
/// A set fills at most three quarters of its 8-byte buckets and doubles them when it grows, so it stays at least
/// three eighths full, and it keeps one more bit per bucket for occupancy. At the limits the identifier sets therefore
/// take at most 1,000,000 × 8⅛ bytes × 8/3, about 20.7 MiB, and about 16.3 MiB for a recording of one device. Each of
/// the at most 16 devices also retains its name, at most 1 MiB as the CSV field limit allows, and up to a memory page
/// for its set. A set that grows briefly also holds its previous buckets, at most about 8.1 MiB more.
struct RecordingBatchCounter {
    /// The most distinct batches one recording may state: more than eleven days of one batch per second.
    static let maximumBatchCount = 1_000_000
    /// The most distinct devices one recording may state; a recording Grove prepares states one.
    static let maximumDeviceCount = 16

    private var identifiersByDevice: [String: Set<UInt64>] = [:]
    private(set) var count = 0

    /// Records the row's batch, throwing ``SensorKitSummaryError/batchLimitExceeded(maximumBatchCount:)`` for a new batch
    /// beyond the limit and ``SensorKitSummaryError/deviceLimitExceeded(maximumDeviceCount:)`` for a new device beyond its
    /// limit.
    mutating func add(device: String, identifier: UInt64) throws(SensorKitSummaryError) {
        if identifiersByDevice[device]?.contains(identifier) == true {
            return
        }
        guard count < Self.maximumBatchCount else {
            throw .batchLimitExceeded(maximumBatchCount: Self.maximumBatchCount)
        }
        guard identifiersByDevice[device] != nil || identifiersByDevice.count < Self.maximumDeviceCount else {
            throw .deviceLimitExceeded(maximumDeviceCount: Self.maximumDeviceCount)
        }
        identifiersByDevice[device, default: []].insert(identifier)
        count += 1
    }
}
