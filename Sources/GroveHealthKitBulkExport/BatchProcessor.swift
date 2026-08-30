//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import GroveHealthKit
import HealthKit


/// Component that receives fetched Health data for processing, as part of a ``BulkExportSession``.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol BatchProcessor<Output>: Sendable {
    /// The type of the processor's output. Should be `Void` if the processor simply consumes the samples.
    associatedtype Output: Sendable
    
    /// Invoked by a ``BulkExportSession``, to process a batch of Health samples.
    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) async throws -> Output

    /// Invoked after the session has durably recorded that an output was processed.
    ///
    /// Use this callback to release retry-only state associated with `output`. The callback is not
    /// part of processing the batch: it runs only after the session descriptor is safely persisted,
    /// and a failure to perform optional cleanup must not invalidate the already-committed output.
    /// Keep the work idempotent and cleanup-only because process termination can occur between the
    /// durable descriptor write and this callback.
    func didPersist(_ output: Output) async
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension BatchProcessor {
    /// The default implementation performs no post-persistence cleanup.
    public func didPersist(_ output: Output) async {}
}

#endif
