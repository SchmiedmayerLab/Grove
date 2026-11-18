//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


/// Converts the exact typed Google Health fields admitted by the guide.
enum GoogleHealthConversion {
    private struct Content {
        let token: String
        let outputs: [ExchangeOutputDraft]
    }

    /// Multiple admitted fields of one data point share one source record and one complete conversion Provenance.
    static func convert(_ record: GoogleHealthDataPoint, context: ProviderConversionContext) throws -> ProviderConversionResult {
        let content = try content(record.value, context: context)
        return try ProviderObservation.assemble(
            provider: .googleHealthAPI,
            token: content.token,
            nativeID: record.id,
            outputs: content.outputs,
            omissions: content.outputs.isEmpty ? [.init(sourceToken: content.token, element: content.token, reason: .missingRequiredEvidence)] : [],
            context: context
        )
    }


    // This closed switch binds the provider's concrete fields, units and temporal shapes to generated contracts.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func content(_ value: GoogleHealthDataPoint.Value, context: ProviderConversionContext) throws -> Content {
        let effective = value.effective
        switch value {
        case .steps(let count, _):
            return try scalar(Decimal(count), token: "steps", contract: MeasurementCatalog.stepCount, effective: effective, context: context)
        case .distance(let millimeters, _):
            return try scalar(
                millimeters / 1_000,
                token: "distance",
                contract: MeasurementCatalog.distance,
                effective: effective,
                context: context
            )
        case .activeEnergy(let calories, _):
            return try scalar(
                calories,
                token: "active-energy-burned",
                contract: MeasurementCatalog.activeEnergy,
                effective: effective,
                context: context
            )
        case .weight(let grams, _):
            return try scalar(
                grams / 1_000,
                token: "weight",
                contract: MeasurementCatalog.bodyWeight,
                effective: effective,
                context: context
            )
        case .bodyFat(let percentage, _):
            return try scalar(
                percentage,
                token: "body-fat",
                contract: MeasurementCatalog.bodyFatPercentage,
                effective: effective,
                context: context
            )
        case .height(let millimeters, _):
            return try scalar(
                millimeters / 10,
                token: "height",
                contract: MeasurementCatalog.bodyHeight,
                effective: effective,
                context: context
            )
        case .vo2Max(let value, _):
            return try scalar(value, token: "vo2-max", contract: MeasurementCatalog.vo2Max, effective: effective, context: context)
        case let .dailyOxygenSaturation(value, day):
            return try scalar(
                value,
                token: "daily-oxygen-saturation",
                contract: MeasurementCatalog.oxygenSaturationDailyAverage,
                effective: day.interval.effective,
                context: context.forDay(day)
            )
        case let .dailyRestingHeartRate(value, day):
            return try scalar(
                value,
                token: "daily-resting-heart-rate",
                contract: GoogleHealthMeasurementCatalog.restingHeartRateDailyAverage,
                effective: day.interval.effective,
                context: context.forDay(day)
            )
        case let .dailyRespiratoryRate(value, day):
            let output = try ProviderObservation.scalar(
                value,
                contract: MeasurementCatalog.respiratoryRateAverage,
                adapter: Profile.googleHealthObservation,
                effective: day.interval.effective,
                method: "daily-mean",
                context: context.forDay(day)
            )
            return .init(token: "daily-respiratory-rate", outputs: [output])
        case let .heartRateVariability(_, rmssd, sdnn):
            let values: [(Decimal?, MeasurementContract)] = [
                (rmssd, MeasurementCatalog.heartRateVariabilityRmssd), (sdnn, MeasurementCatalog.heartRateVariabilitySdnn)
            ]
            let outputs = try values.compactMap { value, contract in
                try value.map {
                    try ProviderObservation.scalar(
                        $0,
                        contract: contract,
                        adapter: Profile.googleHealthObservation,
                        effective: effective,
                        context: context
                    )
                }
            }
            return .init(token: "heart-rate-variability", outputs: outputs)
        case .bloodGlucose(let value, _):
            return try scalar(
                value,
                token: "blood-glucose",
                contract: MeasurementCatalog.bloodGlucoseUnspecifiedSpecimen,
                effective: effective,
                context: context
            )
        case .coreBodyTemperature(let value, _):
            return try scalar(
                value,
                token: "core-body-temperature",
                contract: MeasurementCatalog.bodyTemperature,
                effective: effective,
                context: context
            )
        case .floors(let count, _):
            return try scalar(
                Decimal(count),
                token: "floors",
                contract: MeasurementCatalog.flightsClimbed,
                effective: effective,
                context: context
            )
        case .basalEnergy(let calories, _):
            return try scalar(
                calories,
                token: "basal-energy-burned",
                contract: MeasurementCatalog.basalEnergy,
                effective: effective,
                context: context
            )
        case .sleep(_, let summary):
            return try sleep(summary, effective: effective, context: context)
        case .exercise(_, let activity):
            let output = try ProviderObservation.workout(
                activity,
                adapter: Profile.googleHealthObservation,
                effective: effective,
                context: context
            )
            return .init(token: "exercise", outputs: output.map { [$0] } ?? [])
        }
    }

    private static func scalar(
        _ value: Decimal,
        token: String,
        contract: MeasurementContract,
        effective: ProviderObservation.Effective,
        context: ProviderConversionContext
    ) throws -> Content {
        let output = try ProviderObservation.scalar(
            value,
            contract: contract,
            adapter: Profile.googleHealthObservation,
            effective: effective,
            context: context
        )
        return .init(token: token, outputs: [output])
    }

    private static func sleep(
        _ summary: GoogleHealthDataPoint.SleepSummary,
        effective: ProviderObservation.Effective,
        context: ProviderConversionContext
    ) throws -> Content {
        let durations: [(Int?, MeasurementContract)] = [
            (summary.minutesAsleep, MeasurementCatalog.sleepDuration),
            (summary.deepMinutes, MeasurementCatalog.deepSleepDuration),
            (summary.remMinutes, MeasurementCatalog.remSleepDuration),
            (summary.lightMinutes, MeasurementCatalog.lightSleepDuration),
            (summary.awakeMinutes, MeasurementCatalog.sleepAwakeDuration)
        ]
        let outputs = try durations.compactMap { minutes, contract -> ExchangeOutputDraft? in
            guard let minutes else {
                return nil
            }
            guard minutes >= 0, effective.contains(minutes: minutes) else {
                throw ProviderConversionError.invalidQuantity(contract.id)
            }
            return try ProviderObservation.scalar(
                ProviderObservation.duration(seconds: Decimal(minutes) * 60, in: contract),
                contract: contract,
                adapter: Profile.googleHealthObservation,
                effective: effective,
                context: context
            )
        }
        return .init(token: "sleep", outputs: outputs)
    }
}


extension DateInterval {
    var effective: ProviderObservation.Effective { .interval(start, end) }
}
