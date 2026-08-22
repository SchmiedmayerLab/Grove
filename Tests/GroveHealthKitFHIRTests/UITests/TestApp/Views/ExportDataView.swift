//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import SwiftUI


struct ExportDataView: View {
    private enum ViewState {
        case idle
        case processing
        case failed(any Error)
        
        var isIdle: Bool {
            switch self {
            case .idle:
                true
            case .processing, .failed:
                false
            }
        }
    }
    
    private let healthStore = HKHealthStore()
    
    @State private var viewState: ViewState = .idle
    @State private var generateResourcesDuration: TimeInterval?
    
    var body: some View {
        Form {
            Section("Actions") {
                actionsSectionContent
            }
            if let generateResourcesDuration {
                Section {
                    LabeledContent("genResoueces", value: "\(generateResourcesDuration) sec")
                }
            }
        }
    }
    
    @ViewBuilder private var actionsSectionContent: some View {
        Button("Ask for Authorization") {
            runAsync {
                try await healthStore.requestAuthorization(
                    toShare: [],
                    read: [HKQuantityType(.stepCount)]
                )
            }
        }
        .disabled(!viewState.isIdle)
        Button("Query Samples") {
            runAsync {
                let fetchStartTS = CACurrentMediaTime()
                let samples = try await healthStore.query(.init(.stepCount))
                let fetchEndTS = CACurrentMediaTime()
                print("did fetch samples (#=\(samples.count)) (took \(fetchEndTS - fetchStartTS) sec)")
                let mapResourcesStartTS = CACurrentMediaTime()
                let now = Date.now
                let context = HealthKitFHIRConversionContext(
                    subject: Reference(reference: "Patient/example"),
                    converter: HealthKitFHIRApplication(
                        name: "Grove HealthKit FHIR Test App",
                        bundleIdentifier: "org.grovealliance.healthkit-fhir-test-app",
                        version: "0.3.0"
                    ),
                    graphIdentifierSystem: "https://grovealliance.org/fhir/testing/identifiers/ui-graph",
                    conversionInstant: now
                )
                let result = HealthKitFHIRConverter().convert(
                    samples.map { $0 as HKSample },
                    context: context
                )
                if let failure = result.failures.first {
                    throw failure
                }
                let mapResourcesEndTS = CACurrentMediaTime()
                print("did turn into resources (took \(mapResourcesEndTS - mapResourcesStartTS) sec)")
                await MainActor.run {
                    generateResourcesDuration = mapResourcesEndTS - mapResourcesStartTS
                }
            }
        }
        .disabled(!viewState.isIdle)
    }
    
    private func runAsync(_ operation: @Sendable @escaping () async throws -> Void) {
        precondition(viewState.isIdle)
        Swift::Task {
            viewState = .processing
            do {
                try await operation()
                viewState = .idle
            } catch {
                viewState = .failed(error)
            }
        }
    }
}


extension HKHealthStore {
    func query(_ sampleType: HKQuantityType) async throws -> [HKQuantitySample] {
        let predicate = HKSamplePredicate.quantitySample(
            type: sampleType
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try await descriptor.result(for: self)
    }
}
