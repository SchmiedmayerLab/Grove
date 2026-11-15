//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Testing


@Suite
struct FHIRMeasurementCatalogTests {
    @Test("The portable view covers every generated source without manufacturing a converter capability")
    func inventoryCoverage() throws {
        let sources = FHIRMeasurementCatalog.healthKitSources
        #expect(sources.map(\.sourceTypeIdentifier) == HealthKitContract.rows.map(\.sourceTypeIdentifier))
        #expect(Set(sources.map(\.sourceTypeIdentifier)).count == sources.count)
        for source in sources {
            let found = try #require(FHIRMeasurementCatalog.healthKitSource(identifier: source.sourceTypeIdentifier))
            #expect(found.measurementIDs == source.measurementIDs && found.profiles == source.profiles)
        }
        let food = try #require(FHIRMeasurementCatalog.healthKitSource(identifier: "HKCorrelationTypeIdentifierFood"))
        #expect(food.guideStatus == .supported)
        #expect(FHIRMeasurementCatalog.measurement(id: "food-correlation")?.valueShape == nil)
        let refused = try #require(FHIRMeasurementCatalog.healthKitSource(identifier: "HKQuantityTypeIdentifierBloodPressureSystolic"))
        #expect(refused.guideStatus == .intentionallyUnsupported)
        #expect(refused.requirement?.isEmpty == false)
        #expect(FHIRMeasurementCatalog.healthKitSource(identifier: "HKQuantityTypeIdentifierBodyMass ") == nil)
        #expect(FHIRMeasurementCatalog.healthKitSource(identifier: "unknown") == nil)
    }

    @Test("Point, whole-interval and dual temporal contracts stay distinct")
    func temporalSelection() throws {
        let weight = try #require(FHIRMeasurementCatalog.measurement(id: "body-weight"))
        let steps = try #require(FHIRMeasurementCatalog.measurement(id: "step-count"))
        let heart = try #require(FHIRMeasurementCatalog.measurement(id: "heart-rate"))
        #expect(weight.effective == .dateTime && weight.valueShape == .quantity)
        #expect(steps.effective == .period && steps.valueShape == .quantity)
        #expect(heart.effective == .dateTimeOrPeriod)
        #expect(weight.quantity?.code == "kg" && steps.quantity?.code == "{steps}")
        #expect(steps.quantity?.domain?.integerOnly == true)
        #expect(steps.quantity?.domain?.minimum.value == 0 && steps.quantity?.domain?.minimum.inclusive == true)
        let saturation = try #require(FHIRMeasurementCatalog.measurement(id: "oxygen-saturation"))
        #expect(saturation.quantity?.code == "%")
        #expect(saturation.quantity?.domain?.maximum?.value == 100)
        #expect(saturation.quantity?.domain?.maximum?.inclusive == true)
        let resting = try #require(FHIRMeasurementCatalog.measurement(id: "resting-heart-rate"))
        #expect(resting.code.value == "40443-4" && resting.requiredCodings.map(\.value) == ["8867-4"])
    }

    @Test("A component panel is not a scalar, and an adapter-wide profile never selects a measurement")
    func shapesAndProfileSelection() throws {
        let panel = try #require(FHIRMeasurementCatalog.measurement(id: "blood-pressure"))
        #expect(panel.valueShape == .components && panel.quantity == nil)
        #expect(Set(panel.components.map(\.id)) == ["systolic", "diastolic"])
        #expect(panel.components.allSatisfy { $0.quantity?.code == "mm[Hg]" })
        let sleep = try #require(FHIRMeasurementCatalog.measurement(id: "sleep-stage"))
        #expect(sleep.valueShape == .coded && sleep.resultCodeSystem != nil)
        #expect(FHIRMeasurementCatalog.measurements(profile: Profile.healthkitObservation).isEmpty)
        #expect(FHIRMeasurementCatalog.measurements(profile: Profile.groveMobileBodyWeight).map(\.id) == ["body-weight"])
        #expect(FHIRMeasurementCatalog.measurement(id: "body-weight ") == nil)
        let workout = try #require(FHIRMeasurementCatalog.healthKitSource(identifier: "HKWorkoutTypeIdentifier"))
        #expect(workout.measurementIDs == ["workout", "workout-segment"])
        #expect(workout.measurementIDs.allSatisfy { FHIRMeasurementCatalog.measurement(id: $0) != nil })
    }

    @Test("All generated measurement families, including HealthKit-only contracts and standard BMI, remain discoverable")
    func measurementCoverage() throws {
        let provider = GoogleHealthMeasurementCatalog.all + OuraMeasurementCatalog.all + WithingsMeasurementCatalog.all
        let generated = MeasurementCatalog.all + HealthKitMeasurementCatalog.all + [HealthKitContract.bodyMassIndex] + provider
        #expect(FHIRMeasurementCatalog.providerMeasurements.map(\.id) == provider.map(\.id))
        let publicIDs = FHIRMeasurementCatalog.measurements.map(\.id)
        #expect(Set(publicIDs) == Set(generated.map(\.id)))
        #expect(publicIDs.count == Set(publicIDs).count)
        for contract in generated {
            let found = try #require(FHIRMeasurementCatalog.measurement(id: contract.id))
            #expect(found.profile == contract.profile)
            #expect(found.components.map(\.id) == contract.components.map(\.id))
            #expect(found.quantity?.system == contract.quantity?.system)
        }
        let bmi = try #require(FHIRMeasurementCatalog.measurement(id: "body-mass-index"))
        #expect(bmi.quantity?.code == "kg/m2" && bmi.effective == .dateTime)
        #expect(FHIRMeasurementCatalog.measurement(id: "date-of-birth")?.valueShape == nil)
    }
}
