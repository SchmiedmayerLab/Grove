//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Literal formatting follows FHIR resource shape; the dispatch tables read as one table.
// swiftlint:disable multiline_literal_brackets type_contents_order

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


/// One HealthKit workout statistic and the unit it is read in.
@available(iOS 18, macOS 15, watchOS 11, *)
struct WorkoutStatistic {
    let componentID: String
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The shared workout activity a HealthKit activity type is reported as.
    ///
    /// The shared vocabulary names 28 activities; HealthKit distinguishes 84. Related cases collapse
    /// onto the shared code, and everything the shared vocabulary does not name reports as `other`.
    /// Nothing is lost: ``healthKitWorkoutActivityCode`` always retains the exact platform case
    /// alongside it, following the same adapter-lineage rule the source-type coding follows.
    ///
    /// A closed platform-vocabulary collapse is intentionally spelled as one exhaustive switch.
    static func sharedWorkoutActivity( // swiftlint:disable:this cyclomatic_complexity
        _ activity: HKWorkoutActivityType
    ) -> String {
        switch activity {
        case .running, .wheelchairRunPace: "running"
        case .walking, .wheelchairWalkPace: "walking"
        case .cycling, .handCycling: "cycling"
        case .hiking: "hiking"
        case .swimming, .waterFitness, .waterSports: "swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: "strength-training"
        case .highIntensityIntervalTraining: "high-intensity-interval-training"
        case .yoga: "yoga"
        case .pilates: "pilates"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .stairClimbing, .stairs, .stepTraining: "stair-climbing"
        case .dance, .cardioDance, .socialDance, .danceInspiredTraining, .barre: "dancing"
        case .tennis: "tennis"
        case .tableTennis: "table-tennis"
        case .badminton: "badminton"
        case .squash: "squash"
        case .basketball: "basketball"
        case .soccer: "soccer"
        case .americanFootball: "american-football"
        case .baseball, .softball: "baseball"
        case .volleyball: "volleyball"
        case .golf: "golf"
        case .boxing, .kickboxing: "boxing"
        case .martialArts, .taiChi, .wrestling: "martial-arts"
        case .downhillSkiing, .crossCountrySkiing: "skiing"
        case .snowboarding: "snowboarding"
        default: "other"
        }
    }

    /// The exact HealthKit case, for the adapter coding that rides alongside the shared code.
    static func healthKitWorkoutActivityCode(_ activity: HKWorkoutActivityType) -> String? {
        Self.workoutActivityCases[activity.rawValue]
    }

    /// Every HealthKit workout activity case, keyed by raw value.
    ///
    /// Keyed rather than switched so the exact platform case survives even when the shared
    /// vocabulary collapses it; a case Apple adds later is simply absent rather than mis-reported.
    static let workoutActivityCases: [UInt: String] = [
        HKWorkoutActivityType.americanFootball.rawValue: "americanFootball",
        HKWorkoutActivityType.archery.rawValue: "archery",
        HKWorkoutActivityType.australianFootball.rawValue: "australianFootball",
        HKWorkoutActivityType.badminton.rawValue: "badminton",
        HKWorkoutActivityType.barre.rawValue: "barre",
        HKWorkoutActivityType.baseball.rawValue: "baseball",
        HKWorkoutActivityType.basketball.rawValue: "basketball",
        HKWorkoutActivityType.bowling.rawValue: "bowling",
        HKWorkoutActivityType.boxing.rawValue: "boxing",
        HKWorkoutActivityType.cardioDance.rawValue: "cardioDance",
        HKWorkoutActivityType.climbing.rawValue: "climbing",
        HKWorkoutActivityType.cooldown.rawValue: "cooldown",
        HKWorkoutActivityType.coreTraining.rawValue: "coreTraining",
        HKWorkoutActivityType.cricket.rawValue: "cricket",
        HKWorkoutActivityType.crossCountrySkiing.rawValue: "crossCountrySkiing",
        HKWorkoutActivityType.crossTraining.rawValue: "crossTraining",
        HKWorkoutActivityType.curling.rawValue: "curling",
        HKWorkoutActivityType.cycling.rawValue: "cycling",
        HKWorkoutActivityType.dance.rawValue: "dance",
        HKWorkoutActivityType.danceInspiredTraining.rawValue: "danceInspiredTraining",
        HKWorkoutActivityType.discSports.rawValue: "discSports",
        HKWorkoutActivityType.downhillSkiing.rawValue: "downhillSkiing",
        HKWorkoutActivityType.elliptical.rawValue: "elliptical",
        HKWorkoutActivityType.equestrianSports.rawValue: "equestrianSports",
        HKWorkoutActivityType.fencing.rawValue: "fencing",
        HKWorkoutActivityType.fishing.rawValue: "fishing",
        HKWorkoutActivityType.fitnessGaming.rawValue: "fitnessGaming",
        HKWorkoutActivityType.flexibility.rawValue: "flexibility",
        HKWorkoutActivityType.functionalStrengthTraining.rawValue: "functionalStrengthTraining",
        HKWorkoutActivityType.golf.rawValue: "golf",
        HKWorkoutActivityType.gymnastics.rawValue: "gymnastics",
        HKWorkoutActivityType.handCycling.rawValue: "handCycling",
        HKWorkoutActivityType.handball.rawValue: "handball",
        HKWorkoutActivityType.highIntensityIntervalTraining.rawValue: "highIntensityIntervalTraining",
        HKWorkoutActivityType.hiking.rawValue: "hiking",
        HKWorkoutActivityType.hockey.rawValue: "hockey",
        HKWorkoutActivityType.hunting.rawValue: "hunting",
        HKWorkoutActivityType.jumpRope.rawValue: "jumpRope",
        HKWorkoutActivityType.kickboxing.rawValue: "kickboxing",
        HKWorkoutActivityType.lacrosse.rawValue: "lacrosse",
        HKWorkoutActivityType.martialArts.rawValue: "martialArts",
        HKWorkoutActivityType.mindAndBody.rawValue: "mindAndBody",
        HKWorkoutActivityType.mixedCardio.rawValue: "mixedCardio",
        HKWorkoutActivityType.mixedMetabolicCardioTraining.rawValue: "mixedMetabolicCardioTraining",
        HKWorkoutActivityType.other.rawValue: "other",
        HKWorkoutActivityType.paddleSports.rawValue: "paddleSports",
        HKWorkoutActivityType.pickleball.rawValue: "pickleball",
        HKWorkoutActivityType.pilates.rawValue: "pilates",
        HKWorkoutActivityType.play.rawValue: "play",
        HKWorkoutActivityType.preparationAndRecovery.rawValue: "preparationAndRecovery",
        HKWorkoutActivityType.racquetball.rawValue: "racquetball",
        HKWorkoutActivityType.rowing.rawValue: "rowing",
        HKWorkoutActivityType.rugby.rawValue: "rugby",
        HKWorkoutActivityType.running.rawValue: "running",
        HKWorkoutActivityType.sailing.rawValue: "sailing",
        HKWorkoutActivityType.skatingSports.rawValue: "skatingSports",
        HKWorkoutActivityType.snowboarding.rawValue: "snowboarding",
        HKWorkoutActivityType.snowSports.rawValue: "snowSports",
        HKWorkoutActivityType.soccer.rawValue: "soccer",
        HKWorkoutActivityType.socialDance.rawValue: "socialDance",
        HKWorkoutActivityType.softball.rawValue: "softball",
        HKWorkoutActivityType.squash.rawValue: "squash",
        HKWorkoutActivityType.stairClimbing.rawValue: "stairClimbing",
        HKWorkoutActivityType.stairs.rawValue: "stairs",
        HKWorkoutActivityType.stepTraining.rawValue: "stepTraining",
        HKWorkoutActivityType.surfingSports.rawValue: "surfingSports",
        HKWorkoutActivityType.swimBikeRun.rawValue: "swimBikeRun",
        HKWorkoutActivityType.swimming.rawValue: "swimming",
        HKWorkoutActivityType.tableTennis.rawValue: "tableTennis",
        HKWorkoutActivityType.taiChi.rawValue: "taiChi",
        HKWorkoutActivityType.tennis.rawValue: "tennis",
        HKWorkoutActivityType.trackAndField.rawValue: "trackAndField",
        HKWorkoutActivityType.traditionalStrengthTraining.rawValue: "traditionalStrengthTraining",
        HKWorkoutActivityType.transition.rawValue: "transition",
        HKWorkoutActivityType.underwaterDiving.rawValue: "underwaterDiving",
        HKWorkoutActivityType.volleyball.rawValue: "volleyball",
        HKWorkoutActivityType.walking.rawValue: "walking",
        HKWorkoutActivityType.waterFitness.rawValue: "waterFitness",
        HKWorkoutActivityType.waterPolo.rawValue: "waterPolo",
        HKWorkoutActivityType.waterSports.rawValue: "waterSports",
        HKWorkoutActivityType.wheelchairRunPace.rawValue: "wheelchairRunPace",
        HKWorkoutActivityType.wheelchairWalkPace.rawValue: "wheelchairWalkPace",
        HKWorkoutActivityType.wrestling.rawValue: "wrestling",
        HKWorkoutActivityType.yoga.rawValue: "yoga"
    ]

    static func workoutValue(_ workout: HKWorkout) throws -> CodeableConcept {
        try workoutValue(activityType: workout.workoutActivityType)
    }

    /// The shared and platform codings for one activity type, used by a session and by each of its
    /// per-activity segments.
    static func workoutValue(activityType: HKWorkoutActivityType) throws -> CodeableConcept {
        var codings = [Coding(
            code: FHIRPrimitive(FHIRString(stringLiteral: sharedWorkoutActivity(activityType))),
            system: Canonicals.workoutActivityCodeSystem
        )]
        if let platform = healthKitWorkoutActivityCode(activityType) {
            codings.append(Coding(
                code: FHIRPrimitive(FHIRString(stringLiteral: platform)),
                system: Canonicals.healthKitWorkoutActivity
            ))
        }
        return CodeableConcept(coding: codings)
    }

    /// The session totals HealthKit reports as workout statistics.
    ///
    /// A statistic HealthKit did not record is absent rather than zero: a workout without a distance
    /// sum did not travel zero metres, it did not measure distance at all.
    /// The distance quantity type the activity actually records.
    ///
    /// `HKWorkout.statistics(for:)` returns nil for a type the workout never collected, so reading
    /// only walking/running distance would silently drop every cycling, swimming, wheelchair, and
    /// snow-sport distance.
    static func distanceType(for workout: HKWorkout) -> HKQuantityTypeIdentifier {
        switch workout.workoutActivityType {
        case .cycling, .handCycling: .distanceCycling
        case .swimming: .distanceSwimming
        case .wheelchairRunPace, .wheelchairWalkPace: .distanceWheelchair
        case .crossCountrySkiing: .distanceCrossCountrySkiing
        case .rowing: .distanceRowing
        case .downhillSkiing, .snowboarding, .snowSports: .distanceDownhillSnowSports
        case .paddleSports, .sailing, .surfingSports: .distancePaddleSports
        case .skatingSports: .distanceSkatingSports
        default: .distanceWalkingRunning
        }
    }

    static func workoutComponents(_ workout: HKWorkout) throws -> [ObservationComponent] {
        let sums: [WorkoutStatistic] = [
            WorkoutStatistic(componentID: "distance-sum", identifier: distanceType(for: workout), unit: .meter()),
            WorkoutStatistic(componentID: "active-energy-sum", identifier: .activeEnergyBurned, unit: .kilocalorie()),
            WorkoutStatistic(componentID: "step-count-sum", identifier: .stepCount, unit: .count()),
            WorkoutStatistic(componentID: "flights-climbed-sum", identifier: .flightsClimbed, unit: .count()),
            WorkoutStatistic(
                componentID: "swimming-stroke-count-sum",
                identifier: .swimmingStrokeCount,
                unit: .count()
            )
        ]
        let heartRate = WorkoutStatistic(
            componentID: "heart-rate-avg",
            identifier: .heartRate,
            unit: .count().unitDivided(by: .minute())
        )
        var components = [try component("active-duration", value: workout.duration)]
        for statistic in sums {
            guard let statistics = workout.statistics(for: HKQuantityType(statistic.identifier)),
                  let total = statistics.sumQuantity() else {
                continue
            }
            components.append(try component(statistic.componentID, value: total.doubleValue(for: statistic.unit)))
        }
        if let statistics = workout.statistics(for: HKQuantityType(heartRate.identifier)) {
            let readings: [(String, HKQuantity?)] = [
                ("heart-rate-avg", statistics.averageQuantity()),
                ("heart-rate-max", statistics.maximumQuantity()),
                ("heart-rate-min", statistics.minimumQuantity())
            ]
            for (componentID, quantity) in readings {
                guard let quantity else {
                    continue
                }
                components.append(try component(componentID, value: quantity.doubleValue(for: heartRate.unit)))
            }
        }
        return components
    }

    /// One statistic component, with its code, system, and unit taken from the contract.
    static func component(_ id: String, value: Double) throws -> ObservationComponent {
        guard let component = MeasurementCatalog.workout.components.first(where: { $0.id == id }),
              let quantity = component.quantity else {
            throw HealthKitConversionError.missingRequiredComponent(sampleType: "workout", component: id)
        }
        return ObservationComponent(
            code: CodeableConcept(coding: [Coding(
                code: FHIRPrimitive(FHIRString(stringLiteral: component.code)),
                system: FHIRPrimitive(FHIRURI(stringLiteral: component.system))
            )]),
            value: .quantity(Quantity(
                code: FHIRPrimitive(FHIRString(stringLiteral: quantity.code)),
                system: FHIRPrimitive(FHIRURI(stringLiteral: quantity.system)),
                unit: FHIRPrimitive(FHIRString(stringLiteral: quantity.unit)),
                value: FHIRPrimitive(FHIRDecimal(Decimal(value)))
            ))
        )
    }
}

#endif

// swiftlint:enable multiline_literal_brackets type_contents_order
