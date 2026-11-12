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


extension HKWorkout {
    /// Builds a workout in memory.
    ///
    /// `HKWorkout`'s initializers are deprecated in favor of `HKWorkoutBuilder`, which needs an authorized health store, so the fixtures
    /// can't avoid them.
    #if compiler(>=6.4)
    @diagnose(DeprecatedDeclaration, as: ignored, reason: "HKWorkoutBuilder needs an authorized health store.")
    #endif
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

#endif
