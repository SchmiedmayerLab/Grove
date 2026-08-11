//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveHealthKit
import GroveHealthKitUI
import GroveViews
import SwiftUI


struct ActionsMenu: View {
    @Environment(HealthKit.self) private var healthKit
    
    @Binding var viewState: ViewState
    
    private let testData: [TestDataDefinition] = [
        .init(sampleType: .heartRate, samples: [
            .init(date: .now, value: 87, unit: .count() / .minute())
        ]),
        .init(sampleType: .activeEnergyBurned, samples: [
            .init(date: .now, value: 71.2, unit: .largeCalorie())
        ]),
        .init(sampleType: .stepCount, samples: [
            .init(date: .now, value: 152, unit: .count())
        ]),
        .init(sampleType: .height, samples: [
            .init(date: .now, value: 187, unit: .meterUnit(with: .centi))
        ]),
        .init(sampleType: .distanceCycling, samples: [
            .init(date: .now, value: 52, unit: .meterUnit(with: .kilo))
        ])
    ]
    
    var body: some View {
        Menu {
            AsyncButton("Delete Test Data from HealthKit", role: .destructive, state: $viewState) {
                try await deleteTestData()
            }
            Divider()
            ForEach(testData, id: \.self) { entry in
                AsyncButton("Add Sample: \(entry.sampleType.displayTitle)", state: $viewState) {
                    try await addTestData([entry])
                }
            }
            Divider()
            Menu("Request Access") {
                AsyncButton("Only Blood Pressure", state: $viewState) {
                    try await healthKit.askForAuthorization(
                        for: HealthKit.DataAccessRequirements(readAndWrite: [SampleType.bloodPressure])
                    )
                }
                AsyncButton("Blood Pressure + Steps", state: $viewState) {
                    try await healthKit.askForAuthorization(
                        for: HealthKit.DataAccessRequirements(readAndWrite: [SampleType.bloodPressure, SampleType.stepCount] as [any AnySampleType])
                    )
                }
                AsyncButton("Only Steps", state: $viewState) {
                    try await healthKit.askForAuthorization(
                        for: HealthKit.DataAccessRequirements(readAndWrite: [SampleType.stepCount])
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("actions")
        }
        .accessibilityIdentifier("actions")
    }
    
    
    // MARK: Test Data Handling
    
    private func addTestData(_ definitions: [TestDataDefinition]) async throws {
        let samples: [HKQuantitySample] = definitions.flatMap { definition in
            definition.samples.map { sampleInput in
                let date = sampleInput.date
                return HKQuantitySample(
                    type: definition.sampleType.hkSampleType,
                    quantity: HKQuantity(unit: sampleInput.unit, doubleValue: sampleInput.value),
                    start: date,
                    end: date.addingTimeInterval(sampleInput.duration)
                )
            }
        }
        try await healthKit.askForAuthorization(for: .init(write: samples.mapIntoSet(\.sampleType)))
        for sample in samples {
            // NOTE: for some reason, this works but calling the overload that takes an array doesn't...
            try await healthKit.healthStore.save(sample)
        }
    }
    
    private func deleteTestData() async throws {
        for sampleType in healthKit.dataAccessRequirements.write {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [
                    HKSamplePredicate<HKSample>.sample(
                        type: sampleType,
                        predicate: HKQuery.predicateForObjects(from: .default())
                    )
                ],
                sortDescriptors: []
            )
            do {
                let samples = (try? await descriptor.result(for: healthKit.healthStore)) ?? []
                if !samples.isEmpty {
                    try await healthKit.healthStore.delete(samples)
                }
            } catch {
                print("Failed to delete \(sampleType): \(error)")
                throw error
            }
        }
    }
}
