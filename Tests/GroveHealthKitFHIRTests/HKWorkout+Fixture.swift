//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The optional collections mirror `HKWorkout`'s initializer.
// swiftlint:disable discouraged_optional_collection

#if canImport(HealthKit)

import Foundation
import HealthKit


private protocol DeprecatedWorkoutInitializer {
    func workout( // swiftlint:disable:this function_parameter_count
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        workoutEvents: [HKWorkoutEvent]?,
        totalEnergyBurned: HKQuantity?,
        totalDistance: HKQuantity?,
        device: HKDevice?,
        metadata: [String: Any]?
    ) -> HKWorkout
}


private struct WorkoutInitializer: DeprecatedWorkoutInitializer {
    @available(*, deprecated, message: "Calls HKWorkout's deprecated initializer.")
    func workout( // swiftlint:disable:this function_parameter_count
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        workoutEvents: [HKWorkoutEvent]?,
        totalEnergyBurned: HKQuantity?,
        totalDistance: HKQuantity?,
        device: HKDevice?,
        metadata: [String: Any]?
    ) -> HKWorkout {
        HKWorkout(
            activityType: activityType,
            start: start,
            end: end,
            workoutEvents: workoutEvents,
            totalEnergyBurned: totalEnergyBurned,
            totalDistance: totalDistance,
            device: device,
            metadata: metadata
        )
    }
}


extension HKWorkout {
    /// Builds a workout in memory.
    ///
    /// `HKWorkout`'s initializers are deprecated in favor of `HKWorkoutBuilder`, which needs an authorized health store, so the fixtures
    /// can't avoid them. Calling the initializer through a protocol requirement keeps its deprecation warning out of every test.
    static func fixture(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        workoutEvents: [HKWorkoutEvent]? = nil,
        totalEnergyBurned: HKQuantity? = nil,
        totalDistance: HKQuantity? = nil,
        device: HKDevice? = nil,
        metadata: [String: Any]? = nil
    ) -> HKWorkout {
        let initializer: any DeprecatedWorkoutInitializer = WorkoutInitializer()
        return initializer.workout(
            activityType: activityType,
            start: start,
            end: end,
            workoutEvents: workoutEvents,
            totalEnergyBurned: totalEnergyBurned,
            totalDistance: totalDistance,
            device: device,
            metadata: metadata
        )
    }
}

#endif
