//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

/// Why an export is paused. All cases can be resumed with `start(retryFailedBatches:concurrencyLevel:)`.
public enum BulkExportPauseReason: Hashable, Sendable {
    /// The newly created or restored session has not been started in this process.
    case notStarted
    /// The caller requested a pause. Failed batches may also be present.
    case requested
    /// Inspect the session's failed batches and retry after addressing their errors.
    case failedBatches
    /// Resolve the failure before retrying. Batch failures may also be present.
    case failure(BulkExportSessionFailure)
}
