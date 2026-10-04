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


/// The parts of a workout session's Observation that every workout shares, compiled from the workout contract: what
/// each activity reports, and the components of the statistics HealthKit keeps.
///
/// A session reports its active duration first, then each statistic HealthKit recorded, in a fixed order: the totals,
/// then the heart-rate statistics. A statistic HealthKit did not record is absent, never zero.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitWorkoutContent: Sendable {
    /// What a workout of one activity reports.
    struct Activity: Sendable {
        /// The value: the shared activity's coding, then the exact HealthKit case's, or the shared `other` alone for
        /// a case the table does not name.
        let value: CodeableConcept
        /// The distance type HealthKit records the activity's distance under.
        let distance: HKQuantityTypeIdentifier
    }

    /// One statistic HealthKit keeps for a workout, what it reads, and the component it becomes.
    struct Statistic: Sendable {
        /// Which quantity type's statistics a statistic reads.
        enum Source: Sendable {
            /// The statistics of this quantity type.
            case quantityType(HKQuantityTypeIdentifier)
            /// The statistics of the distance type the workout's activity records.
            case activityDistance
        }

        /// Which of those statistics a statistic reads.
        enum Reading: Sendable {
            /// The total.
            case sum
            /// The average.
            case average
            /// The maximum.
            case maximum
            /// The minimum.
            case minimum

            /// The quantity read from `statistics`, or `nil` when HealthKit kept none.
            func quantity(of statistics: HKStatistics?) -> HKQuantity? {
                switch self {
                case .sum: statistics?.sumQuantity()
                case .average: statistics?.averageQuantity()
                case .maximum: statistics?.maximumQuantity()
                case .minimum: statistics?.minimumQuantity()
                }
            }
        }

        /// The quantity type whose statistics it reads.
        let source: Source
        /// The statistic it reads of them.
        let reading: Reading
        /// The component.
        let template: ComponentTemplate
        /// The unit the statistic is read in.
        let unit: HKUnit

        /// The quantity type the statistic reads for a workout of `activity`.
        func quantityType(of activity: Activity) -> HKQuantityTypeIdentifier {
            switch source {
            case .quantityType(let quantityType): quantityType
            case .activityDistance: activity.distance
            }
        }
    }

    /// The statistics a session reports, in order, by contract component: the totals, then the heart-rate average,
    /// maximum and minimum.
    private static let statisticReadings: KeyValuePairs<String, (source: Statistic.Source, reading: Statistic.Reading)> = [
        "distance-sum": (.activityDistance, .sum),
        "active-energy-sum": (.quantityType(.activeEnergyBurned), .sum),
        "step-count-sum": (.quantityType(.stepCount), .sum),
        "flights-climbed-sum": (.quantityType(.flightsClimbed), .sum),
        "swimming-stroke-count-sum": (.quantityType(.swimmingStrokeCount), .sum),
        "heart-rate-avg": (.quantityType(.heartRate), .average),
        "heart-rate-max": (.quantityType(.heartRate), .maximum),
        "heart-rate-min": (.quantityType(.heartRate), .minimum)
    ]

    /// What each activity the table names reports, by raw value.
    let activities: [UInt: Activity]
    /// What an activity the table does not name reports: the shared `other`, and walking and running distance.
    let otherActivity: Activity
    /// The active duration's component, always reported.
    let activeDuration: ComponentTemplate
    /// The statistics, in the order the session reports them.
    let statistics: [Statistic]

    /// The content of the workout contract, whose activity vocabulary must admit every shared code the table states.
    init(_ contract: MeasurementContract) throws(HealthKitContentDefect) {
        guard let system = contract.resultCodeSystem else {
            throw HealthKitContentDefect("states no activity CodeSystem")
        }
        var activities: [UInt: Activity] = [:]
        for row in Self.activityTable {
            let shared = try Coding(row.shared, system: system, admittedBy: contract.allowedValues)
            let platform = Coding(row.name, system: Canonicals.healthKitWorkoutActivity)
            activities[row.raw] = Activity(value: CodeableConcept(coding: [shared, platform]), distance: row.distance)
        }
        self.activities = activities
        let other = try Coding("other", system: system, admittedBy: contract.allowedValues)
        otherActivity = Activity(value: CodeableConcept(coding: [other]), distance: .distanceWalkingRunning)
        activeDuration = try contract.quantityComponent("active-duration").template
        statistics = try Self.statisticReadings.map { id, read throws(HealthKitContentDefect) in
            let (template, quantity) = try contract.quantityComponent(id)
            return Statistic(source: read.source, reading: read.reading, template: template, unit: try quantity.binding().unit)
        }
    }

    /// What a workout of the activity with raw value `raw` reports.
    func activity(_ raw: UInt) -> Activity {
        activities[raw] ?? otherActivity
    }

    /// Sets a session's components, then its activity, on `observation`.
    func apply(to observation: inout Observation, workout: HKWorkout) throws(HealthKitValueFailure) {
        let activity = self.activity(workout.workoutActivityType.rawValue)
        observation.component = try components(duration: workout.duration, activity: activity, recorded: workout.statistics(for:))
        observation.value = .codeableConcept(activity.value)
    }

    /// The components of an interval of `activity` lasting `duration` seconds, whose statistics HealthKit `recorded`
    /// by quantity type: the active duration, then each statistic it recorded. A workout's activities keep their
    /// statistics the same way, so a segment of one reads its components through here too.
    func components(
        duration: TimeInterval,
        activity: Activity,
        recorded: (HKQuantityType) -> HKStatistics?
    ) throws(HealthKitValueFailure) -> [ObservationComponent] {
        var components = [try activeDuration.component(duration)]
        for statistic in statistics {
            let quantityType = HKQuantityType(statistic.quantityType(of: activity))
            if let quantity = statistic.reading.quantity(of: recorded(quantityType)) {
                components.append(try statistic.template.component(quantity.doubleValue(for: statistic.unit)))
            }
        }
        return components
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitWorkoutContent {
    /// One row of the activity table: a HealthKit case, its exact name, the shared activity it reports as and the
    /// distance type it records.
    struct ActivityRow: Sendable {
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
            name: String,
            shared: String = "other",
            distance: HKQuantityTypeIdentifier = .distanceWalkingRunning
        ) {
            self.init(raw: activity.rawValue, name: name, shared: shared, distance: distance)
        }

        /// An activity HealthKit deprecated but keeps readable in older workouts, by its raw value.
        init(deprecated raw: UInt, name: String, shared: String = "other") {
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

    /// Every HealthKit workout activity, by case name. The shared vocabulary names 28 activities and HealthKit 84, so
    /// related cases collapse onto one shared code and the rest report as `other`.
    static let activityTable = [
        ActivityRow(.americanFootball, name: "americanFootball", shared: "american-football"),
        ActivityRow(.archery, name: "archery"),
        ActivityRow(.australianFootball, name: "australianFootball"),
        ActivityRow(.badminton, name: "badminton", shared: "badminton"),
        ActivityRow(.barre, name: "barre", shared: "dancing"),
        ActivityRow(.baseball, name: "baseball", shared: "baseball"),
        ActivityRow(.basketball, name: "basketball", shared: "basketball"),
        ActivityRow(.bowling, name: "bowling"),
        ActivityRow(.boxing, name: "boxing", shared: "boxing"),
        ActivityRow(.cardioDance, name: "cardioDance", shared: "dancing"),
        ActivityRow(.climbing, name: "climbing"),
        ActivityRow(.cooldown, name: "cooldown"),
        ActivityRow(.coreTraining, name: "coreTraining", shared: "strength-training"),
        ActivityRow(.cricket, name: "cricket"),
        ActivityRow(.crossCountrySkiing, name: "crossCountrySkiing", shared: "skiing", distance: .distanceCrossCountrySkiing),
        ActivityRow(.crossTraining, name: "crossTraining"),
        ActivityRow(.curling, name: "curling"),
        ActivityRow(.cycling, name: "cycling", shared: "cycling", distance: .distanceCycling),
        ActivityRow(deprecated: 14, name: "dance", shared: "dancing"),
        ActivityRow(deprecated: 15, name: "danceInspiredTraining", shared: "dancing"),
        ActivityRow(.discSports, name: "discSports"),
        ActivityRow(.downhillSkiing, name: "downhillSkiing", shared: "skiing", distance: .distanceDownhillSnowSports),
        ActivityRow(.elliptical, name: "elliptical", shared: "elliptical"),
        ActivityRow(.equestrianSports, name: "equestrianSports"),
        ActivityRow(.fencing, name: "fencing"),
        ActivityRow(.fishing, name: "fishing"),
        ActivityRow(.fitnessGaming, name: "fitnessGaming"),
        ActivityRow(.flexibility, name: "flexibility"),
        ActivityRow(.functionalStrengthTraining, name: "functionalStrengthTraining", shared: "strength-training"),
        ActivityRow(.golf, name: "golf", shared: "golf"),
        ActivityRow(.gymnastics, name: "gymnastics"),
        ActivityRow(.handCycling, name: "handCycling", shared: "cycling", distance: .distanceCycling),
        ActivityRow(.handball, name: "handball"),
        ActivityRow(.highIntensityIntervalTraining, name: "highIntensityIntervalTraining", shared: "high-intensity-interval-training"),
        ActivityRow(.hiking, name: "hiking", shared: "hiking"),
        ActivityRow(.hockey, name: "hockey"),
        ActivityRow(.hunting, name: "hunting"),
        ActivityRow(.jumpRope, name: "jumpRope"),
        ActivityRow(.kickboxing, name: "kickboxing", shared: "boxing"),
        ActivityRow(.lacrosse, name: "lacrosse"),
        ActivityRow(.martialArts, name: "martialArts", shared: "martial-arts"),
        ActivityRow(.mindAndBody, name: "mindAndBody"),
        ActivityRow(.mixedCardio, name: "mixedCardio"),
        ActivityRow(deprecated: 30, name: "mixedMetabolicCardioTraining"),
        ActivityRow(.other, name: "other"),
        ActivityRow(.paddleSports, name: "paddleSports", distance: .distancePaddleSports),
        ActivityRow(.pickleball, name: "pickleball"),
        ActivityRow(.pilates, name: "pilates", shared: "pilates"),
        ActivityRow(.play, name: "play"),
        ActivityRow(.preparationAndRecovery, name: "preparationAndRecovery"),
        ActivityRow(.racquetball, name: "racquetball"),
        ActivityRow(.rowing, name: "rowing", shared: "rowing", distance: .distanceRowing),
        ActivityRow(.rugby, name: "rugby"),
        ActivityRow(.running, name: "running", shared: "running"),
        ActivityRow(.sailing, name: "sailing", distance: .distancePaddleSports),
        ActivityRow(.skatingSports, name: "skatingSports", distance: .distanceSkatingSports),
        ActivityRow(.snowboarding, name: "snowboarding", shared: "snowboarding", distance: .distanceDownhillSnowSports),
        ActivityRow(.snowSports, name: "snowSports", distance: .distanceDownhillSnowSports),
        ActivityRow(.soccer, name: "soccer", shared: "soccer"),
        ActivityRow(.socialDance, name: "socialDance", shared: "dancing"),
        ActivityRow(.softball, name: "softball", shared: "baseball"),
        ActivityRow(.squash, name: "squash", shared: "squash"),
        ActivityRow(.stairClimbing, name: "stairClimbing", shared: "stair-climbing"),
        ActivityRow(.stairs, name: "stairs", shared: "stair-climbing"),
        ActivityRow(.stepTraining, name: "stepTraining", shared: "stair-climbing"),
        ActivityRow(.surfingSports, name: "surfingSports", distance: .distancePaddleSports),
        ActivityRow(.swimBikeRun, name: "swimBikeRun"),
        ActivityRow(.swimming, name: "swimming", shared: "swimming", distance: .distanceSwimming),
        ActivityRow(.tableTennis, name: "tableTennis", shared: "table-tennis"),
        ActivityRow(.taiChi, name: "taiChi", shared: "martial-arts"),
        ActivityRow(.tennis, name: "tennis", shared: "tennis"),
        ActivityRow(.trackAndField, name: "trackAndField"),
        ActivityRow(.traditionalStrengthTraining, name: "traditionalStrengthTraining", shared: "strength-training"),
        ActivityRow(.transition, name: "transition"),
        ActivityRow(.underwaterDiving, name: "underwaterDiving"),
        ActivityRow(.volleyball, name: "volleyball", shared: "volleyball"),
        ActivityRow(.walking, name: "walking", shared: "walking"),
        ActivityRow(.waterFitness, name: "waterFitness", shared: "swimming"),
        ActivityRow(.waterPolo, name: "waterPolo"),
        ActivityRow(.waterSports, name: "waterSports", shared: "swimming"),
        ActivityRow(.wheelchairRunPace, name: "wheelchairRunPace", shared: "running", distance: .distanceWheelchair),
        ActivityRow(.wheelchairWalkPace, name: "wheelchairWalkPace", shared: "walking", distance: .distanceWheelchair),
        ActivityRow(.wrestling, name: "wrestling", shared: "martial-arts"),
        ActivityRow(.yoga, name: "yoga", shared: "yoga")
    ]
}

#endif
