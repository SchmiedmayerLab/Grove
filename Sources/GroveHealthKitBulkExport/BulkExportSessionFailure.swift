//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
// SPDX-License-Identifier: MIT
//

/// A session-level failure; individual batch errors remain on the failed batches.
public enum BulkExportSessionFailure: Error, Hashable, Sendable {
    case checkpointWriteFailed(CheckpointWriteFailure)
}
