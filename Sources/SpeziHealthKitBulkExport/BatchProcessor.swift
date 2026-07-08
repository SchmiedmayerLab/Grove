//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit
public import SpeziHealthKit


/// Component that receives fetched Health data for processing, as part of a ``BulkExportSession``.
@available(iOS 17, macOS 14, macCatalyst 17, watchOS 10, visionOS 1, *)
public protocol BatchProcessor<Output>: Sendable {
    /// The type of the processor's output. Should be `Void` if the processor simply consumes the samples.
    associatedtype Output: Sendable
    
    /// Invoked by a ``BulkExportSession``, to process a batch of Health samples.
    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) async throws -> Output
}

#endif
