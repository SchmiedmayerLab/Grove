//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Grove
import HealthKit


/// The Constraint your app's `Standard` must conform to when using the Grove HealthKit module.
///
/// Make sure that your standard in your Grove Application conforms to the ``HealthKitConstraint``
/// protocol to receive HealthKit data.
///
/// Returning normally is an explicit durability acknowledgement: Grove persists the new HealthKit
/// query anchor only after both callbacks for that anchored delta return. Throw when processing was
/// not durably accepted (including cancellation or a temporarily unavailable account); Grove keeps
/// the old anchor and redelivers. Implementations must therefore accept exact duplicate delivery
/// idempotently. When one delta contains additions and deletions, Grove invokes additions first and
/// acknowledges neither callback unless both succeed.
/// 
/// The ``HealthKitConstraint/handleNewSamples(_:ofType:)`` function is triggered once for every batch of newly collected HealthKit samples, and ``HealthKitConstraint/handleDeletedObjects(_:ofType:)`` once for every batch of deleted HealthKit objects.
/// ```swift
/// actor ExampleStandard: Standard, HealthKitConstraint {
///     // Add the newly collected `HKSample`s to your application.
///     func handleNewSamples<Sample>(
///         _ addedSamples: some Collection<Sample> & Sendable,
///         ofType sampleType: SampleType<Sample>
///     ) async throws {
///         // ...
///     }
///
///     // Remove the deleted `HKObject`s from your application.
///     func handleDeletedObjects<Sample>(
///         _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
///         ofType sampleType: SampleType<Sample>
///     ) async throws {
///         // ...
///     }
/// }
/// ```
/// ## Topics
/// ### Responding to Health Store Changes
/// - ``handleNewSamples(_:ofType:)``
/// - ``handleDeletedObjects(_:ofType:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol HealthKitConstraint: Standard {
    /// Notifies the `Standard` about the addition of a batch of HealthKit `HKSample` samples.
    ///
    /// Return only after the batch is durably and idempotently accepted. Throwing retains the
    /// previous HealthKit query anchor and causes exact redelivery.
    /// - parameter addedSamples: The `HKSample`s that were added to the HealthKit database.
    /// - parameter sampleType: The ``SampleType`` of the new samples
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async throws
    
    /// Notifies the `Standard` about the removal of a batch of HealthKit objects.
    ///
    /// Return only after every deletion intent is durable. Throwing retains the previous query
    /// anchor. The same delta's additions have already been presented, so retries must be idempotent.
    /// - parameter deletedObjects: The `HKDeletedObject`s that were removed from the HealthKit database
    /// - parameter sampleType: The ``SampleType`` of the deleted objects
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async throws
}

#endif
