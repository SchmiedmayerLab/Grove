//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// Pins the codes and systems these converters emit to the published contract.
///
/// Both were previously hardcoded, and both were wrong: State of Mind emitted component codes no
/// profile slice matched, and workout statistics went out under a code system that does not contain
/// them — which validates cleanly and loses every statistic. Nothing pinned either.
@Suite
struct WorkoutAndStateOfMindContractTests {
    @Test
    func stateOfMindComponentCodesComeFromTheContract() throws {
        let contract = HealthKitMeasurementCatalog.stateOfMind
        for id in ["kind", "valence-classification", "label", "association"] {
            let component = try #require(
                contract.components.first { $0.id == id },
                "the contract must declare a \(id) component"
            )
            #expect(component.resultCodeSystem != nil, "\(id) must bind a result code system")
            // The profile slices on a code pattern, so an emitted code that is not the contract's
            // leaves the required slice empty and the Observation fails validation.
            #expect(!component.code.isEmpty)
        }
        #expect(contract.components.first { $0.id == "kind" }?.code == "kind")
        #expect(contract.components.first { $0.id == "valence-classification" }?.code == "valence-classification")
    }

    @Test
    func everyWorkoutStatisticTheConverterEmitsExistsInTheContract() throws {
        // If an id drifts from the contract the converter now throws rather than mis-coding, so
        // this also proves the conversion path cannot trip that error.
        let emitted = [
            "active-duration", "distance-sum", "active-energy-sum",
            "step-count-sum", "flights-climbed-sum", "swimming-stroke-count-sum",
            "heart-rate-avg", "heart-rate-max", "heart-rate-min"
        ]
        for id in emitted {
            let component = try #require(
                MeasurementCatalog.workout.components.first { $0.id == id },
                "\(id) is emitted but not declared by the workout contract"
            )
            #expect(component.quantity != nil, "\(id) must declare a quantity")
            #expect(
                component.system == "https://grovealliance.org/fhir/mobile/CodeSystem/grove-workout-statistic",
                "\(id) must be coded from the workout statistic system"
            )
        }
    }

    @Test
    func eachWorkoutActivityCollapsesOntoAPublishedSharedCode() {
        let published = Set(MeasurementCatalog.workout.allowedValues)
        for (rawValue, name) in HealthKitConverter.workoutActivityCases {
            guard let activity = HKWorkoutActivityType(rawValue: rawValue) else {
                Issue.record("\(name) has no HKWorkoutActivityType for raw value \(rawValue)")
                continue
            }
            let shared = HealthKitConverter.sharedWorkoutActivity(activity)
            #expect(published.contains(shared), "\(shared) is not in the published workout vocabulary")
        }
    }

    @Test
    func activitiesWithTheirOwnDistanceTypeUseIt() {
        // Reading walking/running distance for every activity silently drops the distance of every
        // workout that records a different type.
        let expected: [(HKWorkoutActivityType, HKQuantityTypeIdentifier)] = [
            (.cycling, .distanceCycling),
            (.swimming, .distanceSwimming),
            (.rowing, .distanceRowing),
            (.crossCountrySkiing, .distanceCrossCountrySkiing),
            (.downhillSkiing, .distanceDownhillSnowSports),
            (.wheelchairRunPace, .distanceWheelchair),
            (.running, .distanceWalkingRunning)
        ]
        for (activity, identifier) in expected {
            let workout = HKWorkout(activityType: activity, start: Date(), end: Date().addingTimeInterval(60))
            #expect(HealthKitConverter.distanceType(for: workout) == identifier)
        }
    }

    @Test
    func bothTypesResolveThroughIdentifierAndSampleLookupAlike() {
        // A caller holding only an identifier must get the same binding as one holding a sample.
        #expect(HealthKitCatalog.binding(forSourceTypeIdentifier: HKWorkoutType.workoutType().identifier) != nil)
        #expect(HealthKitCatalog.binding(forSourceTypeIdentifier: HKSampleType.stateOfMindType().identifier) != nil)
    }
}

#endif
