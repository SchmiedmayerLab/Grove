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


/// Coordinates use the source's exact binary64 instant, independently of the wire Period's precision.
@available(iOS 18, macOS 15, watchOS 11, *)
enum HealthKitWorkoutSegmentIdentity {
    static func instant(_ date: Date) throws(HealthKitConversionError.ValueFailure) -> String {
        let seconds = date.timeIntervalSinceReferenceDate
        guard seconds.isFinite, seconds >= -63_113_904_000, seconds < 252_423_993_600 else {
            throw .effectivePeriodInvalid
        }
        // Split before adding the epoch offset. The signed fractional remainder is exact; multiplying it stays
        // below 2^52, so FMA recovers the rounding error and resolves a binary64 product that landed on a tie.
        let whole = Int64(seconds.rounded(.towardZero))
        let fraction = seconds.truncatingRemainder(dividingBy: 1)
        let product = fraction * 1_000_000_000
        let error = (-product).addingProduct(fraction, 1_000_000_000)
        let isTie = (product - product.rounded(.towardZero)).magnitude == 0.5
        let rule: FloatingPointRoundingRule = isTie && error != 0 ? (error > 0 ? .up : .down) : .toNearestOrEven
        let (carry, nanoseconds) = ExchangeInstant.floorDivide(Int64(product.rounded(rule)), by: 1_000_000_000)
        let epochSeconds = whole + 978_307_200 + carry
        let (days, secondOfDay) = ExchangeInstant.floorDivide(epochSeconds, by: 86_400)
        let civil = ExchangeInstant.civilDate(fromDays: days)
        guard (1...9_999).contains(civil.year) else {
            throw .effectivePeriodInvalid
        }
        return ExchangeInstant.padded(civil.year, width: 4)
            + "-" + ExchangeInstant.padded(civil.month, width: 2)
            + "-" + ExchangeInstant.padded(civil.day, width: 2)
            + "T" + ExchangeInstant.padded(secondOfDay / 3_600, width: 2)
            + ":" + ExchangeInstant.padded(secondOfDay / 60 % 60, width: 2)
            + ":" + ExchangeInstant.padded(secondOfDay % 60, width: 2)
            + "." + ExchangeInstant.padded(nanoseconds, width: 9) + "Z"
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitWorkoutContent {
    private struct Segment {
        let start: Date
        let end: Date
        let kind: String
        let raw: String
        let value: CodeableConcept
        let components: [ObservationComponent]
        let known: Bool
    }

    private static let eventCodes: [Int: (shared: String, platform: String)] = [
        1: ("pause", "pause"), 2: ("resume", "resume"), 3: ("lap", "lap"), 4: ("marker", "marker"),
        5: ("motion-paused", "motionPaused"), 6: ("motion-resumed", "motionResumed"),
        7: ("segment-generic", "segment"), 8: ("pause-or-resume-request", "pauseOrResumeRequest")
    ]

    static func unmappedValue(_ raw: String) -> Extension {
        Extension(url: Canonicals.healthKitUnmappedSourceValue, value: .string(raw.asFHIRStringPrimitive()))
    }

    /// Every session event followed by every activity, including a single activity; activity events are not duplicated.
    func segments(_ workout: HKWorkout, metadata: HealthKitSampleMetadata) throws -> [ExchangeOutputDraft] {
        let zone = try metadata.timeZone()
        guard let system = MeasurementCatalog.workoutSegment.resultCodeSystem else {
            throw HealthKitConversionError.notYetConvertible(.workout)
        }
        var occurrences: [String: Int] = [:]
        var result: [ExchangeOutputDraft] = []
        for event in workout.workoutEvents ?? [] {
            let mapping = Self.eventCodes[event.type.rawValue]
            var codings = [Coding(mapping?.shared ?? "unknown", system: system)]
            if let mapping {
                codings.append(Coding(mapping.platform, system: Canonicals.healthKitWorkoutEventType))
            }
            let segment = Segment(
                start: event.dateInterval.start,
                end: event.dateInterval.end,
                kind: "event",
                raw: String(event.type.rawValue),
                value: CodeableConcept(coding: codings),
                components: [],
                known: mapping != nil
            )
            result.append(try output(for: segment, in: workout, zone: zone, occurrences: &occurrences))
        }
        for segment in workout.workoutActivities {
            guard let end = segment.endDate else {
                throw HealthKitConversionError.ValueFailure.workoutActivityEndMissing
            }
            let raw = segment.workoutConfiguration.activityType.rawValue
            let activity = self.activity(raw)
            var components = [try activeDuration.component(segment.duration)]
            for statistic in statistics {
                if let recorded = segment.statistics(for: HKQuantityType(statistic.quantityType(of: activity))),
                   let quantity = statistic.read(recorded) {
                    components.append(try statistic.template.component(quantity.doubleValue(for: statistic.unit)))
                }
            }
            let content = Segment(
                start: segment.startDate,
                end: end,
                kind: "activity",
                raw: String(raw),
                value: activity.value,
                components: components,
                known: activities[raw] != nil
            )
            result.append(try output(for: content, in: workout, zone: zone, occurrences: &occurrences))
        }
        return result
    }
    private func output(
        for segment: Segment,
        in workout: HKWorkout,
        zone: TimeZone?,
        occurrences: inout [String: Int]
    ) throws -> ExchangeOutputDraft {
        let contract = MeasurementCatalog.workoutSegment
        guard segment.start >= workout.startDate, segment.end <= workout.endDate, segment.start <= segment.end else {
            throw HealthKitConversionError.ValueFailure.effectivePeriodInvalid
        }
        let start = try HealthKitWorkoutSegmentIdentity.instant(segment.start)
        let end = try HealthKitWorkoutSegmentIdentity.instant(segment.end)
        let coordinate = "\(start)|\(end)|\(segment.kind)|\(segment.raw)"
        let occurrence = occurrences[coordinate, default: 0]
        occurrences[coordinate] = occurrence + 1
        guard let coding = segment.value.coding?.first, let code = coding.code?.value?.string,
              let system = coding.system?.value?.url.absoluteString,
              contract.admitsResult(code: code, system: system) else {
            throw HealthKitConversionError.notYetConvertible(.workout)
        }
        var observation = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [Coding(contract.code)]),
            sourceType: .workout,
            profiles: ProfileClaims.observation(sharedMeasurement: contract.profile, adapter: Profile.healthkitObservation)
        )
        observation.effective = .period(try HealthKitEffectiveTime.period(start: segment.start, end: segment.end, zone: zone))
        observation.value = .codeableConcept(segment.value)
        observation.component = segment.components.isEmpty ? nil : segment.components
        if !segment.known {
            observation.extension = (observation.extension ?? []) + [Self.unmappedValue(segment.raw)]
        }
        return ExchangeOutputDraft(
            role: "workout-segment",
            discriminator: "\(coordinate)|\(occurrence)",
            resource: .observation(observation),
            links: .all,
            memberOfPrimary: true
        )
    }
}

#endif
