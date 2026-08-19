//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

@_spi(Internal)
public import GroveFHIR
public import GroveHealthKit
public import HealthKit
public import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore {
    /// Add a HealthKit sample to the FHIR store.
    /// - Parameters:
    ///   - sample: The sample that should be added.
    ///   - subject: The patient the sample was recorded for. Required: the observation
    ///     declares a profile that pins `subject`, and a profile claim has to be true.
    ///   - healthKit: The `HealthKit` module to be used when fetching attachments.
    ///   - loadHealthKitAttachments: Indicates if the `HKAttachmentStore` should be queried for any document references found in clinical records.
    public func add(
        _ sample: HKSample,
        subject: ModelsR4.Reference,
        using healthKit: HealthKit,
        loadHealthKitAttachments: Bool = false
    ) async throws {
        let resource = try await FHIRResource.initialize(
            basedOn: sample,
            subject: subject,
            using: healthKit,
            loadHealthKitAttachments: loadHealthKitAttachments
        )
        await insert(resource)
    }
    
    /// Remove a HealthKit sample delete object from the FHIR store.
    /// - Parameter deletedObject: The sample delete object that should be removed.
    @MainActor
    public func remove(_ deletedObject: HKDeletedObject) {
        removeResource(withHealthKitUUID: deletedObject.uuid.uuidString)
    }
}

#endif
