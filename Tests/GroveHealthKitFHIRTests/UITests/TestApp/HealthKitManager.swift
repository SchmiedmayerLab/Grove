//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import Foundation
import HealthKit
import Observation


@Observable
final class HealthKitManager: Sendable {
    let healthStore: HKHealthStore?
    
    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            healthStore = nil
        }
    }
    
    func requestStepAuthorization() async throws {
        try await requestReadWriteAuthorization(for: [.stepCount])
    }
    
    func requestReadWriteAuthorization(for identifiers: [HKQuantityTypeIdentifier]) async throws {
        guard let healthStore else {
            throw HKError(.errorHealthDataUnavailable)
        }
        let sampleTypes = Set(identifiers.map { HKQuantityType($0) })
        try await healthStore.requestAuthorization(toShare: sampleTypes, read: sampleTypes)
    }
    
    func readSamples(
        for identifier: HKQuantityTypeIdentifier,
        sorted sortDescriptors: [SortDescriptor<HKQuantitySample>] = [],
        limit: Int? = nil
    ) async throws -> [HKQuantitySample] {
        guard let healthStore else {
            throw HKError(.errorHealthDataUnavailable)
        }
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: sortDescriptors,
            limit: limit ?? HKObjectQueryNoLimit
        )
        return try await query.result(for: healthStore)
    }
    
    func writeSteps(startDate: Date, endDate: Date, steps: Double) async throws {
        guard let healthStore,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HKError(.errorHealthDataUnavailable)
        }
        let stepsSample = HKQuantitySample(
            type: stepType,
            quantity: HKQuantity(unit: HKUnit.count(), doubleValue: steps),
            start: startDate,
            end: endDate
        )
        try await healthStore.save(stepsSample)
    }

}
