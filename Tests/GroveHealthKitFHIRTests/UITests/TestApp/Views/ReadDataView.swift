//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKit
import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import SwiftUI


struct ReadDataView<Sample: _HKSampleWithSampleType>: View {
    @Environment(HealthKit.self) private var healthKit
    
    private let sampleType: SampleType<Sample>
    
    @State private var json = ""
    @State private var showingSheet = false
    
    
    var body: some View {
        Form {
            Section {
                Button("Read \(sampleType.displayTitle)") {
                    Swift::Task {
                        try await readData()
                        showingSheet.toggle()
                    }
                }
                .sheet(isPresented: $showingSheet) {
                    JSONView(json: $json)
                }
            }
        }
        .navigationBarTitle("Read Data")
    }
    
    
    init(_ sampleType: SampleType<Sample>) {
        self.sampleType = sampleType
    }
    
    private func readData() async throws {
        try await healthKit.askForAuthorization(for: .init(read: [sampleType]))
        let samples = try await healthKit.query(
            sampleType,
            timeRange: .ever,
            limit: 1,
            sortedBy: [.init(\.startDate, order: .reverse)]
        )
        let now = Date.now
        let context = HealthKitFHIRConversionContext(
            subject: Reference(reference: "Patient/example"),
            converter: HealthKitFHIRApplication(
                name: "Grove HealthKit FHIR Test App",
                bundleIdentifier: "org.grovealliance.healthkit-fhir-test-app",
                version: "0.2.0"
            ),
            graphIdentifierSystem: "https://grovealliance.org/fhir/testing/identifiers/ui-graph",
            conversionInstant: now
        )
        let bundles = try samples.map { sample in
            guard let healthKitSample = sample as? HKSample else {
                throw GroveHealthKitFHIRError.invalidValue
            }
            return try HealthKitFHIRConverter().convert(healthKitSample, context: context).bundle
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(bundles)
        self.json = String(decoding: data, as: UTF8.self)
    }
}
