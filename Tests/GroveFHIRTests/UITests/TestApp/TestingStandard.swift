//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import os
import Grove
import GroveHealthKit


actor TestingStandard: Standard, HealthKitConstraint, EnvironmentAccessible {
    static let recordTypes: [SampleType<HKClinicalRecord>] = [
        .allergyRecord, .clinicalNoteRecord, .conditionRecord,
        .coverageRecord, .immunizationRecord, .labResultRecord,
        .medicationRecord, .procedureRecord, .vitalSignRecord
    ]
    
    
    @Dependency(HealthKit.self) private var healthKit
    
    private let logger = Logger()
    private var samples: [HKSample] = []
    
    
    @MainActor
    func configure() {
        Task {
            await self.initialSetup()
        }
    }
    
    private func initialSetup() async {
        // Waiting until the HealthKit module loads all authorization requirements: the module reports
        // `.completed` asynchronously and offers no way to await it, so this polls with a short ceiling.
        let loadingStartDate = Date.now
        while healthKit.configurationState != .completed && abs(loadingStartDate.distance(to: .now)) < 0.5 {
            logger.debug("Loading HealthKit Module ...")
            try? await Task.sleep(for: .seconds(0.02))
        }
        
        guard healthKit.isFullyAuthorized else {
            logger.error("HealthKit permissions not yet provided.")
            return
        }
        
        await fetchRecordsFromHealthKit()
    }
    
    func handleNewSamples<Sample>(_ addedSamples: some Collection<Sample>, ofType sampleType: SampleType<Sample>) async {
        samples.append(contentsOf: addedSamples.lazy.map { $0 as HKSample })
    }
    
    func handleDeletedObjects<Sample>(_ deletedObjects: some Collection<HKDeletedObject>, ofType sampleType: SampleType<Sample>) async {
        for object in deletedObjects {
            samples.removeAll { $0.id == object.uuid }
        }
    }
    
    func fetchRecordsFromHealthKit() async {
        let healthKit = self.healthKit
        await withTaskGroup { taskGroup in
            for recordType in Self.recordTypes {
                taskGroup.addTask { [self] in
                    let records = try? await healthKit.query(
                        recordType,
                        timeRange: .ever,
                        sortedBy: [SortDescriptor(\.startDate, order: .reverse)]
                    )
                    
                    guard let records else {
                        return
                    }
                    
                    await addRecords(records)
                }
            }
        }
    }
    
    private func addRecords(_ records: [HKClinicalRecord]) async {
        samples.append(contentsOf: records)
    }
}
