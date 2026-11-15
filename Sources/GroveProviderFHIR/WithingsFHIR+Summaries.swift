//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


extension WithingsFHIR {
    private struct SummaryField<Value> {
        let token: String
        let value: Value?
        let contract: MeasurementContract
    }

    /// Each populated summary field has the independent source token assigned by the provider catalog.
    public static func convert(_ summary: WithingsSummary, context: ProviderConversionContext) throws -> [ProviderConversionResult] {
        switch summary {
        case let .activity(id, day, values):
            let context = context.forDay(day)
            let effective = ProviderObservation.Effective.interval(day.interval.start, day.interval.end)
            let fields: [SummaryField<Decimal>] = [
                .init(token: "getactivity:steps", value: values.steps.map { Decimal($0) }, contract: MeasurementCatalog.stepCount),
                .init(token: "getactivity:distance", value: values.distance, contract: MeasurementCatalog.distance),
                .init(token: "getactivity:calories", value: values.calories, contract: MeasurementCatalog.activeEnergy)
            ]
            return try fields.compactMap { field in
                guard let value = field.value else {
                    return nil
                }
                let output = try ProviderObservation.scalar(
                    value,
                    contract: field.contract,
                    adapter: Profile.withingsObservation,
                    effective: effective,
                    context: context
                )
                return try ProviderObservation.assemble(provider: .withings, token: field.token, nativeID: id, outputs: [output], context: context)
            }
        case let .sleep(id, interval, values):
            return try sleep(id: id, interval: interval, values: values, context: context)
        case let .workout(id, interval, activity):
            let output = try ProviderObservation.workout(
                activity,
                adapter: Profile.withingsObservation,
                effective: .interval(interval.start, interval.end),
                context: context
            )
            return [
                try ProviderObservation.assemble(
                    provider: .withings,
                    token: "getworkouts:interval",
                    nativeID: id,
                    outputs: output.map { [$0] } ?? [],
                    omissions: output == nil
                        ? [.init(sourceToken: "getworkouts:interval", element: "workout.activity", reason: .missingRequiredEvidence)] : [],
                    context: context
                )
            ]
        }
    }

    private static func sleep(
        id: String,
        interval: DateInterval,
        values: WithingsSummary.Sleep,
        context: ProviderConversionContext
    ) throws -> [ProviderConversionResult] {
        let effective = ProviderObservation.Effective.interval(interval.start, interval.end)
        let durations: [SummaryField<Int>] = [
            .init(token: "getsummary:deepsleepduration", value: values.deepSleepDuration, contract: MeasurementCatalog.deepSleepDuration),
            .init(token: "getsummary:remsleepduration", value: values.remSleepDuration, contract: MeasurementCatalog.remSleepDuration),
            .init(token: "getsummary:lightsleepduration", value: values.lightSleepDuration, contract: MeasurementCatalog.lightSleepDuration),
            .init(token: "getsummary:wakeupduration", value: values.wakeupDuration, contract: MeasurementCatalog.sleepAwakeDuration)
        ]
        var results = try durations.compactMap { field -> ProviderConversionResult? in
            guard let seconds = field.value else {
                return nil
            }
            guard seconds >= 0, Double(seconds) <= interval.duration else { throw ProviderConversionError.invalidQuantity(field.contract.id) }
            let output = try ProviderObservation.scalar(
                Decimal(seconds) / 3_600,
                contract: field.contract,
                adapter: Profile.withingsObservation,
                effective: effective,
                context: context
            )
            return try ProviderObservation.assemble(provider: .withings, token: field.token, nativeID: id, outputs: [output], context: context)
        }
        let averages: [SummaryField<Decimal>] = [
            .init(token: "getsummary:hr_average", value: values.averageHeartRate, contract: MeasurementCatalog.sleepHeartRate),
            .init(token: "getsummary:rr_average", value: values.averageRespiratoryRate, contract: MeasurementCatalog.respiratoryRateAverage)
        ]
        results += try averages.compactMap { field in
            guard let value = field.value else {
                return nil
            }
            let output = try ProviderObservation.scalar(
                value,
                contract: field.contract,
                adapter: Profile.withingsObservation,
                effective: effective,
                method: "session-mean",
                context: context
            )
            return try ProviderObservation.assemble(provider: .withings, token: field.token, nativeID: id, outputs: [output], context: context)
        }
        return results
    }
}
