//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import Grove
import GroveHealthKit
import GroveHealthKitBulkExport


/// An example Standard used for the configuration.
actor TestAppStandard: Standard, HealthKitConstraint {
    @Dependency(FakeHealthStore.self) private var fakeHealthStore
    @Dependency(BulkHealthExporter.self) private var bulkExporter
    
    nonisolated func configure() {
        guard CommandLine.arguments.contains("--resetEverything") else {
            return
        }
        Task {
            do {
                FakeHealthStore.reset()
                if FileManager.default.fileExists(atPath: URL.documentsDirectory.path) {
                    try FileManager.default.removeItem(at: .documentsDirectory)
                }
                try FileManager.default.createDirectory(at: .documentsDirectory, withIntermediateDirectories: true)
                try await bulkExporter.deleteSessionRestorationInfo(for: .testApp)
            } catch {
                // a partial reset makes the following test fail somewhere else entirely, so make it fail here instead
                preconditionFailure("--resetEverything failed: \(error)")
            }
        }
    }
    
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample>,
        ofType sampleType: SampleType<Sample>
    ) async {
        for sample in addedSamples {
            await fakeHealthStore.add(sample)
        }
    }
    
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject>,
        ofType sampleType: SampleType<Sample>
    ) async {
        for object in deletedObjects {
            await fakeHealthStore.remove(object)
        }
    }
}
