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
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The structural intervals a workout carries beyond its session totals.
    ///
    /// A workout is not one undifferentiated interval: it carries laps, pauses, and — since iOS 16 —
    /// per-activity intervals that describe a multi-sport session. Converting only the totals turns a
    /// triathlon into a single Observation, so each is emitted as its own segment linked from the
    /// session through `hasMember`.
    static func workoutSegments(
        _ workout: HKWorkout,
        context: HealthKitConversionContext,
        sourceUUID: String
    ) throws -> [(identity: BusinessIdentifier, observation: Observation)] {
        var segments: [(identity: BusinessIdentifier, observation: Observation)] = []
        for (index, event) in (workout.workoutEvents ?? []).enumerated() {
            segments.append((
                identity: try derivedIdentity(context: context, sourceUUID: sourceUUID, role: "workout-event-\(index)"),
                observation: try segmentObservation(
                    value: segmentValue(for: event.type),
                    interval: event.dateInterval,
                    components: [],
                    context: context
                )
            ))
        }
        for (index, activity) in workout.workoutActivities.enumerated() {
            // An activity that has not ended has no closed interval, and the profile requires one.
            guard let end = activity.endDate else {
                continue
            }
            segments.append((
                identity: try derivedIdentity(
                    context: context,
                    sourceUUID: sourceUUID,
                    role: "workout-activity-\(index)"
                ),
                observation: try segmentObservation(
                    value: try workoutValue(activityType: activity.workoutConfiguration.activityType),
                    interval: DateInterval(start: activity.startDate, end: end),
                    components: try activityComponents(activity),
                    context: context
                )
            ))
        }
        return segments
    }

    private static func segmentObservation(
        value: CodeableConcept,
        interval: DateInterval,
        components: [ObservationComponent],
        context: HealthKitConversionContext
    ) throws -> Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(
                    code: "workout-segment",
                    system: Canonicals.mobileMeasurementCodeSystem
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: [Profile.groveMobileWorkoutSegment])
        observation.subject = context.subject
        observation.effective = .period(Period(
            end: FHIRPrimitive(try DateTime(date: interval.end)),
            start: FHIRPrimitive(try DateTime(date: interval.start))
        ))
        observation.value = .codeableConcept(value)
        observation.component = components.isEmpty ? nil : components
        return observation
    }

    /// The structural classification the segment vocabulary publishes for a workout event.
    static func segmentValue(for type: HKWorkoutEventType) -> CodeableConcept {
        let code: String
        switch type {
        case .pause: code = "pause"
        case .resume: code = "resume"
        case .lap: code = "lap"
        case .marker: code = "marker"
        case .motionPaused: code = "motion-paused"
        case .motionResumed: code = "motion-resumed"
        case .segment: code = "segment-generic"
        case .pauseOrResumeRequest: code = "pause-or-resume-request"
        // A case this SDK does not know is classified rather than dropped: the interval it marks is
        // still a real interval, and refusing the whole workout over it would lose the session.
        @unknown default: code = "unknown"
        }
        return CodeableConcept(coding: [
            Coding(
                code: FHIRPrimitive(FHIRString(stringLiteral: code)),
                system: Canonicals.workoutSegmentTypeCodeSystem
            )
        ])
    }

    /// The statistics an activity reports for its own interval, using the session's component codes.
    ///
    /// An activity that never collected a statistic reports nothing for it, which is absent rather
    /// than zero — the same distinction the session totals make.
    private static func activityComponents(_ activity: HKWorkoutActivity) throws -> [ObservationComponent] {
        let statistics: [WorkoutStatistic] = [
            WorkoutStatistic(componentID: "active-energy-sum", identifier: .activeEnergyBurned, unit: .kilocalorie()),
            WorkoutStatistic(componentID: "step-count-sum", identifier: .stepCount, unit: .count()),
            WorkoutStatistic(componentID: "flights-climbed-sum", identifier: .flightsClimbed, unit: .count()),
            WorkoutStatistic(
                componentID: "swimming-stroke-count-sum",
                identifier: .swimmingStrokeCount,
                unit: .count()
            )
        ]
        var components: [ObservationComponent] = []
        for statistic in statistics {
            guard let quantity = activity.statistics(for: HKQuantityType(statistic.identifier)),
                  let total = quantity.sumQuantity() else {
                continue
            }
            components.append(try component(
                statistic.componentID,
                value: total.doubleValue(for: statistic.unit)
            ))
        }
        return components
    }
}
#endif
