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
    /// The workout's compiled content.
    private static func workoutContent() throws -> HealthKitWorkoutContent {
        let plan = HealthKitContentPlan[.workout]
        guard case .observation(let observation) = plan.route, case .workout(let content) = observation.value else {
            throw plan.refusal
        }
        return content
    }

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
    func eachWorkoutActivityCollapsesOntoAPublishedSharedCode() throws {
        let published = Set(MeasurementCatalog.workout.allowedValues)
        let workout = try Self.workoutContent()
        #expect(workout.activities.count == HealthKitWorkoutContent.activityTable.count)
        for row in HealthKitWorkoutContent.activityTable {
            #expect(HKWorkoutActivityType(rawValue: row.raw) != nil, "\(row.name) has no HKWorkoutActivityType for raw value \(row.raw)")
            let shared = workout.activity(row.raw).value.coding?.first?.code?.value?.string
            #expect(shared.map(published.contains) == true, "\(row.name) reports as \(shared ?? "nothing"), not a published activity")
        }
    }

    @Test
    func activitiesWithTheirOwnDistanceTypeUseIt() throws {
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
        let workout = try Self.workoutContent()
        for (activity, identifier) in expected {
            #expect(workout.activity(activity.rawValue).distance == identifier)
        }
    }

    @Test
    func bothTypesResolveThroughIdentifierAndSampleLookupAlike() throws {
        // A caller holding only a sample type, a deletion, must reach the plan a sample converts through.
        for sampleType in [HKWorkoutType.workoutType(), HKSampleType.stateOfMindType()] as [HKSampleType] {
            let type = try #require(HealthKitSourceType(sampleType))
            guard case .observation = HealthKitContentPlan[type].route else {
                Issue.record("\(type.rawValue) converts to no Observation")
                continue
            }
        }
    }
}

#endif
