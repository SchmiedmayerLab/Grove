//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A limit that stops Grove from summarizing a recording.
///
/// The limit says nothing about the recording's clinical content, so this is not a ``SensorKitRecordError``: creating
/// the record throws it, and the caller stops publishing the batch. The same recording fails the same way again, so
/// fetch the samples in smaller batches before retrying.
public enum SensorKitSummaryError: Error, Equatable, Sendable {
    /// An accelerometer recording states more than `maximumBatchCount` distinct pairs of device and batch identifier.
    case batchLimitExceeded(maximumBatchCount: Int)
    /// An accelerometer recording states more than `maximumDeviceCount` distinct devices.
    case deviceLimitExceeded(maximumDeviceCount: Int)
}
