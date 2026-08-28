//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// Segment construction stays contiguous so interval, identity, and reference ordering are auditable.
// swiftlint:disable function_body_length function_parameter_count

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
        sourceRecord: BusinessIdentifier,
        sourceUUID: String
    ) throws -> [(identity: BusinessIdentifier, observation: Observation)] {
        var segments: [(identity: BusinessIdentifier, observation: Observation)] = []
        var eventOccurrences: [String: Int] = [:]
        for event in workout.workoutEvents ?? [] {
            let coordinate = try segmentCoordinate(
                kind: "event-\(segmentCode(for: event.type))",
                interval: event.dateInterval
            )
            let occurrence = eventOccurrences[coordinate, default: 0]
            eventOccurrences[coordinate] = occurrence + 1
            let identity = try context.identityScope.sourceOutput(
                adapterID: "healthkit",
                sourceType: workout.sampleType.identifier,
                repositoryScope: context.repositoryScope,
                nativeRecordID: sourceUUID,
                outputRole: "workout-segment",
                outputDiscriminator: "\(coordinate):\(occurrence)"
            )
            segments.append((
                identity: identity,
                observation: try segmentObservation(
                    value: segmentValue(for: event.type),
                    interval: event.dateInterval,
                    components: [],
                    sourceTypeIdentifier: workout.sampleType.identifier,
                    context: context,
                    sourceRecord: sourceRecord,
                    output: identity
                )
            ))
        }
        var activityOccurrences: [String: Int] = [:]
        for activity in workout.workoutActivities {
            // An activity that has not ended has no closed interval, and the profile requires one.
            guard let end = activity.endDate else {
                continue
            }
            let interval = DateInterval(start: activity.startDate, end: end)
            let coordinate = try segmentCoordinate(
                kind: "activity-\(activity.workoutConfiguration.activityType.rawValue)",
                interval: interval
            )
            let occurrence = activityOccurrences[coordinate, default: 0]
            activityOccurrences[coordinate] = occurrence + 1
            let identity = try context.identityScope.sourceOutput(
                adapterID: "healthkit",
                sourceType: workout.sampleType.identifier,
                repositoryScope: context.repositoryScope,
                nativeRecordID: sourceUUID,
                outputRole: "workout-segment",
                outputDiscriminator: "\(coordinate):\(occurrence)"
            )
            segments.append((
                identity: identity,
                observation: try segmentObservation(
                    value: try workoutValue(activityType: activity.workoutConfiguration.activityType),
                    interval: interval,
                    components: try activityComponents(activity),
                    sourceTypeIdentifier: workout.sampleType.identifier,
                    context: context,
                    sourceRecord: sourceRecord,
                    output: identity
                )
            ))
        }
        return segments
    }

    /// Stable source coordinates keep child identities invariant when HealthKit reorders arrays.
    /// Only exact duplicate coordinates receive an occurrence suffix; those records are otherwise
    /// indistinguishable under the published workout-segment contract.
    private static func segmentCoordinate(kind: String, interval: DateInterval) throws -> String {
        let start = interval.start.timeIntervalSince1970
        let end = interval.end.timeIntervalSince1970
        guard start.isFinite, end.isFinite, end >= start else {
            throw HealthKitConversionError.invalidEffectivePeriod(
                sampleType: HKWorkoutType.workoutType().identifier
            )
        }
        return "\(kind):\(String(groveFHIRPlainDecimal: start)):\(String(groveFHIRPlainDecimal: end))"
    }

    private static func segmentObservation(
        value: CodeableConcept,
        interval: DateInterval,
        components: [ObservationComponent],
        sourceTypeIdentifier: String,
        context: HealthKitConversionContext,
        sourceRecord: BusinessIdentifier,
        output: BusinessIdentifier
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
        applySourceTypeLineage(sourceTypeIdentifier, to: &observation)
        observation.meta = Meta(profile: [Profile.groveMobileWorkoutSegment])
        observation.identifier = [sourceRecord.fhirIdentifier, output.fhirIdentifier]
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
        let code = segmentCode(for: type)
        return CodeableConcept(coding: [
            Coding(
                code: FHIRPrimitive(FHIRString(stringLiteral: code)),
                system: Canonicals.workoutSegmentTypeCodeSystem
            )
        ])
    }

    private static func segmentCode(for type: HKWorkoutEventType) -> String {
        switch type {
        case .pause: "pause"
        case .resume: "resume"
        case .lap: "lap"
        case .marker: "marker"
        case .motionPaused: "motion-paused"
        case .motionResumed: "motion-resumed"
        case .segment: "segment-generic"
        case .pauseOrResumeRequest: "pause-or-resume-request"
        // A case this SDK does not know is classified rather than dropped: the interval it marks is
        // still a real interval, and refusing the whole workout over it would lose the session.
        @unknown default: "unknown"
        }
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
