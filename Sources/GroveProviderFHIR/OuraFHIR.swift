//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


/// Converts Oura documents without fetching, resampling or allocating delivery sequences.
public enum OuraFHIR {
    /// Converts one document into a complete record, with omissions for unsupported or incomplete source evidence.
    public static func convert(_ record: OuraRecord, context: ProviderConversionContext) throws -> ProviderConversionResult {
        switch record {
        case .dailyActivity(let activity):
            return try dailyActivity(activity, context: context)
        case .sleep(let record):
            return try sleep(record, context: context)
        case let .dailyOxygenSaturation(id, day, average):
            return try dailyScalar(
                id: id,
                token: "daily_spo2",
                day: day,
                value: average,
                contract: MeasurementCatalog.oxygenSaturationDailyAverage,
                context: context
            )
        case let .cardiovascularAge(id, day, years):
            return try dailyScalar(
                id: id,
                token: "daily_cardiovascular_age",
                day: day,
                value: years.map { Decimal($0) },
                contract: OuraMeasurementCatalog.ouraCardiovascularAge,
                context: context
            )
        case let .readiness(id, day, score):
            return try dailyScalar(
                id: id,
                token: "daily_readiness",
                day: day,
                value: score.map { Decimal($0) },
                contract: OuraMeasurementCatalog.ouraReadinessScore,
                context: context
            )
        case let .vo2Max(id, timestamp, value):
            return try vo2Max(id: id, value: value, effective: .instant(timestamp), context: context)
        case let .exactVO2Max(id, timestamp, value):
            return try vo2Max(id: id, value: value, effective: .exactInstant(timestamp), context: context)
        case let .workout(id, start, end, activity):
            return try workout(id: id, activity: activity, effective: .interval(start, end), context: context)
        case let .exactWorkout(id, interval, activity):
            return try workout(id: id, activity: activity, effective: .exactInterval(interval), context: context)
        }
    }

    private static func vo2Max(
        id: String, value: Decimal?, effective: ProviderObservation.Effective, context: ProviderConversionContext
    ) throws -> ProviderConversionResult {
        let output = try scalar(value, contract: MeasurementCatalog.vo2Max, effective: effective, context: context)
        return try assemble(id: id, token: "vO2_max", outputs: output.map { [$0] } ?? [], context: context)
    }

    private static func workout(
        id: String, activity: ProviderWorkoutActivity?, effective: ProviderObservation.Effective, context: ProviderConversionContext
    ) throws -> ProviderConversionResult {
        let output = try ProviderObservation.workout(activity, adapter: Profile.ouraObservation, effective: effective, context: context)
        return try assemble(
            id: id,
            token: "workout",
            outputs: output.map { [$0] } ?? [],
            omissions: output == nil ? [.init(sourceToken: "workout", element: "workout.activity", reason: .missingRequiredEvidence)] : [],
            context: context
        )
    }

    private static func dailyActivity(_ activity: OuraActivityRecord, context: ProviderConversionContext) throws -> ProviderConversionResult {
        let day = activity.day
        let context = context.forDay(day)
        let interval = try day.interval(startingAt: 4)
        let effective = ProviderObservation.Effective.interval(interval.start, interval.end)
        let outputs = try [
            scalar(activity.steps.map { Decimal($0) }, contract: MeasurementCatalog.stepCount, effective: effective, context: context),
            scalar(activity.activeCalories, contract: MeasurementCatalog.activeEnergy, effective: effective, context: context),
            scalar(activity.equivalentWalkingDistance, contract: MeasurementCatalog.distance, effective: effective, context: context)
        ].compactMap { $0 }
        return try assemble(id: activity.id, token: "daily_activity", outputs: outputs, context: context)
    }

    // Keep the source coordinate, value and semantic contract explicit at this boundary.
    // swiftlint:disable:next function_parameter_count
    private static func dailyScalar(
        id: String,
        token: String,
        day: ProviderCivilDay,
        value: Decimal?,
        contract: MeasurementContract,
        context: ProviderConversionContext
    ) throws -> ProviderConversionResult {
        let context = context.forDay(day)
        let output = try scalar(value, contract: contract, effective: .interval(day.interval.start, day.interval.end), context: context)
        return try assemble(id: id, token: token, outputs: output.map { [$0] } ?? [], context: context)
    }

    private static func scalar(
        _ value: Decimal?,
        contract: MeasurementContract,
        effective: ProviderObservation.Effective,
        method: String? = nil,
        context: ProviderConversionContext
    ) throws -> ExchangeOutputDraft? {
        try value.map {
            try ProviderObservation.scalar(
                $0,
                contract: contract,
                adapter: Profile.ouraObservation,
                effective: effective,
                method: method,
                context: context
            )
        }
    }

    private static func assemble(
        id: String,
        token: String,
        outputs: [ExchangeOutputDraft],
        omissions: [ProviderConversionResult.Omission] = [],
        context: ProviderConversionContext
    ) throws -> ProviderConversionResult {
        try ProviderObservation.assemble(provider: .oura, token: token, nativeID: id, outputs: outputs, omissions: omissions, context: context)
    }
}


extension OuraFHIR {
    private static func sleep(_ record: OuraSleepRecord, context: ProviderConversionContext) throws -> ProviderConversionResult {
        var omissions: [ProviderConversionResult.Omission] = []
        if record.averageHRV != nil {
            omissions.append(.init(sourceToken: "sleep", element: "average_hrv", reason: .notAdmitted))
        }
        guard let bounds = try record.measurementBounds else {
            omissions.append(.init(sourceToken: "sleep", element: "bedtime_start/bedtime_end", reason: .missingRequiredEvidence))
            return try assemble(id: record.id, token: "sleep", outputs: [], omissions: omissions, context: context)
        }
        let effective = bounds.effective
        let durations: [(Int?, MeasurementContract)] = [
            (record.totalSleepDuration, MeasurementCatalog.sleepDuration),
            (record.deepSleepDuration, MeasurementCatalog.deepSleepDuration),
            (record.remSleepDuration, MeasurementCatalog.remSleepDuration),
            (record.lightSleepDuration, MeasurementCatalog.lightSleepDuration),
            (record.awakeTime, MeasurementCatalog.sleepAwakeDuration)
        ]
        var outputs = try durations.compactMap { seconds, contract -> ExchangeOutputDraft? in
            guard let seconds else {
                return nil
            }
            guard seconds >= 0, Decimal(seconds) <= bounds.duration else {
                throw ProviderConversionError.invalidQuantity(contract.id)
            }
            return try scalar(Decimal(seconds) / 3_600, contract: contract, effective: effective, context: context)
        }
        outputs += try [
            scalar(
                record.lowestHeartRate,
                contract: MeasurementCatalog.sleepHeartRate,
                effective: effective,
                method: "session-minimum",
                context: context
            ),
            scalar(
                record.averageBreath,
                contract: MeasurementCatalog.respiratoryRateAverage,
                effective: effective,
                method: "session-mean",
                context: context
            )
        ].compactMap { $0 }
        return try assemble(id: record.id, token: "sleep", outputs: outputs, omissions: omissions, context: context)
    }
}


extension ProviderConversionContext {
    func forDay(_ day: ProviderCivilDay) -> Self {
        .init(
            producer: producer,
            scope: scope,
            instant: instant,
            sourceTimeZone: day.timeZone,
            recordingDevice: recordingDevice,
            sourceApplication: sourceApplication
        )
    }
}
