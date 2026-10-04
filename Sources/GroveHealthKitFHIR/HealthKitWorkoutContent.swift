//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit
import ModelsR4


/// The parts of a workout session's Observation that every workout shares, compiled from the workout contract: the
/// value of each activity, and the components of the statistics HealthKit keeps.
///
/// A session reports its active duration first, then the totals HealthKit recorded, in a fixed order, then its
/// heart-rate statistics; a statistic HealthKit did not record is absent, never zero.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitWorkoutContent: Sendable {
    /// One HealthKit workout activity.
    struct Activity: Sendable {
        /// The raw value.
        let raw: UInt
        /// The exact HealthKit case name, kept beside the shared code so nothing the shared vocabulary collapses is lost.
        let name: String
        /// The shared activity the case reports as; `other` when the shared vocabulary does not name it.
        let shared: String
        /// The distance type the activity records: `HKWorkout.statistics(for:)` has none for any other.
        let distance: HKQuantityTypeIdentifier

        /// A current activity.
        init(
            _ activity: HKWorkoutActivityType,
            _ name: String,
            _ shared: String = "other",
            distance: HKQuantityTypeIdentifier = .distanceWalkingRunning
        ) {
            self.init(raw: activity.rawValue, name: name, shared: shared, distance: distance)
        }

        /// An activity HealthKit deprecated but keeps readable in older workouts, by its raw value.
        init(deprecated raw: UInt, _ name: String, _ shared: String = "other") {
            self.init(raw: raw, name: name, shared: shared, distance: .distanceWalkingRunning)
        }

        /// Any activity.
        private init(raw: UInt, name: String, shared: String, distance: HKQuantityTypeIdentifier) {
            self.raw = raw
            self.name = name
            self.shared = shared
            self.distance = distance
        }
    }

    /// One statistic HealthKit keeps for a workout: the component it becomes and how HealthKit states it.
    struct Statistic: Sendable {
        /// The component.
        let template: ComponentTemplate
        /// The statistic's quantity type, or `nil` for the distance, whose type is the activity's.
        let quantityType: HKQuantityTypeIdentifier?
        /// The unit the statistic is read in.
        let unit: HKUnit
    }

    /// The totals a session reports, in order, each with the quantity type HealthKit keeps it under.
    private static let totalTypes: KeyValuePairs<String, HKQuantityTypeIdentifier?> = [
        "distance-sum": nil,
        "active-energy-sum": .activeEnergyBurned,
        "step-count-sum": .stepCount,
        "flights-climbed-sum": .flightsClimbed,
        "swimming-stroke-count-sum": .swimmingStrokeCount
    ]

    /// The heart-rate statistics a session reports, in order: average, maximum and minimum.
    private static let heartRateStatistics = ["heart-rate-avg", "heart-rate-max", "heart-rate-min"]

    /// The value of each activity the table names: the shared coding, then the HealthKit case's coding.
    let activities: [UInt: CodeableConcept]
    /// The value of an activity the table does not name: the shared `other` alone.
    let otherActivity: CodeableConcept
    /// The distance type of each activity the table names; any other records walking and running distance.
    let distanceTypes: [UInt: HKQuantityTypeIdentifier]
    /// The active duration's component, always reported.
    let activeDuration: ComponentTemplate
    /// The totals, in order.
    let totals: [Statistic]
    /// The heart-rate statistics, in order: average, maximum and minimum.
    let heartRate: [Statistic]

    /// The content of the workout contract.
    init(_ contract: MeasurementContract) throws(HealthKitContentDefect) {
        guard let system = contract.resultCodeSystem else {
            throw HealthKitContentDefect("states no activity CodeSystem")
        }
        var activities: [UInt: CodeableConcept] = [:]
        var distanceTypes: [UInt: HKQuantityTypeIdentifier] = [:]
        for activity in Self.activityTable {
            let platform = Coding(code: activity.name.asFHIRStringPrimitive(), system: Canonicals.healthKitWorkoutActivity)
            activities[activity.raw] = CodeableConcept(coding: [Coding(activity.shared, system: system), platform])
            distanceTypes[activity.raw] = activity.distance
        }
        self.activities = activities
        self.distanceTypes = distanceTypes
        otherActivity = CodeableConcept(coding: [Coding("other", system: system)])
        activeDuration = try Self.component("active-duration", of: contract).template
        var totals: [Statistic] = []
        for (id, quantityType) in Self.totalTypes {
            totals.append(try Self.statistic(id, quantityType: quantityType, of: contract))
        }
        self.totals = totals
        var heartRate: [Statistic] = []
        for id in Self.heartRateStatistics {
            heartRate.append(try Self.statistic(id, quantityType: .heartRate, of: contract))
        }
        self.heartRate = heartRate
    }

    /// The statistic of the contract's component `id`, read in the HealthKit unit of its UCUM code.
    private static func statistic(
        _ id: String,
        quantityType: HKQuantityTypeIdentifier?,
        of contract: MeasurementContract
    ) throws(HealthKitContentDefect) -> Statistic {
        let component = try component(id, of: contract)
        guard let unit = HealthKitContentRules.ucumUnits[component.code] else {
            throw HealthKitContentDefect("reads component \(id) in \(component.code), which has no HealthKit unit")
        }
        return Statistic(template: component.template, quantityType: quantityType, unit: unit)
    }

    /// The contract's quantity component `id`, and its UCUM code.
    private static func component(
        _ id: String,
        of contract: MeasurementContract
    ) throws(HealthKitContentDefect) -> (template: ComponentTemplate, code: String) {
        guard let component = contract.components.first(where: { $0.id == id }),
              let quantity = component.quantity,
              let template = ComponentTemplate(component) else {
            throw HealthKitContentDefect("states no quantity component \(id)")
        }
        return (template, quantity.code)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitWorkoutContent {
    /// Every HealthKit workout activity, by case name. The shared vocabulary names 28 activities and HealthKit 84, so
    /// related cases collapse onto one shared code and the rest report as `other`.
    static let activityTable = [
        Activity(.americanFootball, "americanFootball", "american-football"),
        Activity(.archery, "archery"),
        Activity(.australianFootball, "australianFootball"),
        Activity(.badminton, "badminton", "badminton"),
        Activity(.barre, "barre", "dancing"),
        Activity(.baseball, "baseball", "baseball"),
        Activity(.basketball, "basketball", "basketball"),
        Activity(.bowling, "bowling"),
        Activity(.boxing, "boxing", "boxing"),
        Activity(.cardioDance, "cardioDance", "dancing"),
        Activity(.climbing, "climbing"),
        Activity(.cooldown, "cooldown"),
        Activity(.coreTraining, "coreTraining", "strength-training"),
        Activity(.cricket, "cricket"),
        Activity(.crossCountrySkiing, "crossCountrySkiing", "skiing", distance: .distanceCrossCountrySkiing),
        Activity(.crossTraining, "crossTraining"),
        Activity(.curling, "curling"),
        Activity(.cycling, "cycling", "cycling", distance: .distanceCycling),
        Activity(deprecated: 14, "dance", "dancing"),
        Activity(deprecated: 15, "danceInspiredTraining", "dancing"),
        Activity(.discSports, "discSports"),
        Activity(.downhillSkiing, "downhillSkiing", "skiing", distance: .distanceDownhillSnowSports),
        Activity(.elliptical, "elliptical", "elliptical"),
        Activity(.equestrianSports, "equestrianSports"),
        Activity(.fencing, "fencing"),
        Activity(.fishing, "fishing"),
        Activity(.fitnessGaming, "fitnessGaming"),
        Activity(.flexibility, "flexibility"),
        Activity(.functionalStrengthTraining, "functionalStrengthTraining", "strength-training"),
        Activity(.golf, "golf", "golf"),
        Activity(.gymnastics, "gymnastics"),
        Activity(.handCycling, "handCycling", "cycling", distance: .distanceCycling),
        Activity(.handball, "handball"),
        Activity(.highIntensityIntervalTraining, "highIntensityIntervalTraining", "high-intensity-interval-training"),
        Activity(.hiking, "hiking", "hiking"),
        Activity(.hockey, "hockey"),
        Activity(.hunting, "hunting"),
        Activity(.jumpRope, "jumpRope"),
        Activity(.kickboxing, "kickboxing", "boxing"),
        Activity(.lacrosse, "lacrosse"),
        Activity(.martialArts, "martialArts", "martial-arts"),
        Activity(.mindAndBody, "mindAndBody"),
        Activity(.mixedCardio, "mixedCardio"),
        Activity(deprecated: 30, "mixedMetabolicCardioTraining"),
        Activity(.other, "other"),
        Activity(.paddleSports, "paddleSports", distance: .distancePaddleSports),
        Activity(.pickleball, "pickleball"),
        Activity(.pilates, "pilates", "pilates"),
        Activity(.play, "play"),
        Activity(.preparationAndRecovery, "preparationAndRecovery"),
        Activity(.racquetball, "racquetball"),
        Activity(.rowing, "rowing", "rowing", distance: .distanceRowing),
        Activity(.rugby, "rugby"),
        Activity(.running, "running", "running"),
        Activity(.sailing, "sailing", distance: .distancePaddleSports),
        Activity(.skatingSports, "skatingSports", distance: .distanceSkatingSports),
        Activity(.snowboarding, "snowboarding", "snowboarding", distance: .distanceDownhillSnowSports),
        Activity(.snowSports, "snowSports", distance: .distanceDownhillSnowSports),
        Activity(.soccer, "soccer", "soccer"),
        Activity(.socialDance, "socialDance", "dancing"),
        Activity(.softball, "softball", "baseball"),
        Activity(.squash, "squash", "squash"),
        Activity(.stairClimbing, "stairClimbing", "stair-climbing"),
        Activity(.stairs, "stairs", "stair-climbing"),
        Activity(.stepTraining, "stepTraining", "stair-climbing"),
        Activity(.surfingSports, "surfingSports", distance: .distancePaddleSports),
        Activity(.swimBikeRun, "swimBikeRun"),
        Activity(.swimming, "swimming", "swimming", distance: .distanceSwimming),
        Activity(.tableTennis, "tableTennis", "table-tennis"),
        Activity(.taiChi, "taiChi", "martial-arts"),
        Activity(.tennis, "tennis", "tennis"),
        Activity(.trackAndField, "trackAndField"),
        Activity(.traditionalStrengthTraining, "traditionalStrengthTraining", "strength-training"),
        Activity(.transition, "transition"),
        Activity(.underwaterDiving, "underwaterDiving"),
        Activity(.volleyball, "volleyball", "volleyball"),
        Activity(.walking, "walking", "walking"),
        Activity(.waterFitness, "waterFitness", "swimming"),
        Activity(.waterPolo, "waterPolo"),
        Activity(.waterSports, "waterSports", "swimming"),
        Activity(.wheelchairRunPace, "wheelchairRunPace", "running", distance: .distanceWheelchair),
        Activity(.wheelchairWalkPace, "wheelchairWalkPace", "walking", distance: .distanceWheelchair),
        Activity(.wrestling, "wrestling", "martial-arts"),
        Activity(.yoga, "yoga", "yoga")
    ]
}

#endif
