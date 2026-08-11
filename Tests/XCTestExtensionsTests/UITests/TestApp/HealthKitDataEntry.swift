//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import SwiftUI


private let healthStore = HKHealthStore()

struct HealthKitDataEntryView: View {
    @State private var isAddingSample = false
    @State private var didAddSample = false
    
    @State private var hasAccess = false
    
    var body: some View {
        Form {
            Button("Add a HealthKit sample") {
                Task {
                    do {
                        try await addSample()
                        didAddSample = true
                    } catch {
                        print("Erorr trying to add test sample: \(error)")
                    }
                }
            }.disabled(isAddingSample)
            
            Section { // status section
                if hasAccess {
                    Text("Has access")
                }
                if didAddSample {
                    Text("Did add sample!")
                }
            }
        }
        .task {
            switch healthStore.authorizationStatus(for: HKQuantityType(.heartRate)) {
            case .sharingAuthorized:
                hasAccess = true
            case .notDetermined, .sharingDenied: // sharingDenied will never happen in the test environment.
                hasAccess = false
            @unknown default:
                hasAccess = false
            }
        }
    }
    
    
    private func addSample() async throws {
        isAddingSample = true
        defer {
            isAddingSample = false
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }
        
        let now = Date()
        let heartRateType = HKQuantityType(.heartRate)
        
        try await healthStore.requestAuthorization(toShare: [heartRateType], read: [])
        let sample = HKQuantitySample(
            type: heartRateType,
            quantity: .init(unit: .count().unitDivided(by: .minute()), doubleValue: 69),
            start: now,
            end: now,
            // adding this incase anyone ever runs this on a real device by accicent,
            // so that they can easily identify and delete any test samples.
            metadata: ["XCTestExtensions.isTestSample": "1"]
        )
        try await healthStore.save(sample)
    }
}
