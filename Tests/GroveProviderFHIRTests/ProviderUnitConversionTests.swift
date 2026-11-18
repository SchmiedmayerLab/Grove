//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveProviderFHIR
import ModelsR4
import Testing


@Suite
struct ProviderUnitConversionTests {
    private struct Expected {
        let contract: MeasurementContract
        let value: String
    }

    @Test("Withings measure scaling, activity totals and sleep stages state the contract's unit")
    func withingsUnits() throws {
        let context = try WithingsFHIRTests.context()
        var results = try ProviderFHIRConverter.convert(
            WithingsMeasureGroup(
                id: "group",
                date: WithingsFHIRTests.date,
                measures: [.init(type: 1, value: 72_501, unit: -3), .init(type: 4, value: 1_755, unit: -3)]
            ),
            context: context
        )
        var activity = WithingsSummary.Activity()
        activity.distance = 750
        activity.calories = 100
        let day = try ProviderCivilDay(year: 2026, month: 11, day: 1, timeZone: context.sourceTimeZone)
        results += try ProviderFHIRConverter.convert(WithingsSummary.activity(id: "activity", day: day, values: activity), context: context)
        var sleep = WithingsSummary.Sleep()
        sleep.deepSleepDuration = 5_400
        sleep.remSleepDuration = 7_200
        sleep.lightSleepDuration = 14_430
        sleep.wakeupDuration = 3_600
        let interval = DateInterval(start: WithingsFHIRTests.date.addingTimeInterval(-28_800), end: WithingsFHIRTests.date)
        results += try ProviderFHIRConverter.convert(WithingsSummary.sleep(id: "sleep", interval: interval, values: sleep), context: context)
        try Self.expect(results, [
            Expected(contract: MeasurementCatalog.bodyWeight, value: "72.501"),
            Expected(contract: MeasurementCatalog.bodyHeight, value: "175.5"),
            Expected(contract: MeasurementCatalog.distance, value: "750"),
            Expected(contract: MeasurementCatalog.activeEnergy, value: "100"),
            Expected(contract: MeasurementCatalog.deepSleepDuration, value: "90"),
            Expected(contract: MeasurementCatalog.remSleepDuration, value: "120"),
            Expected(contract: MeasurementCatalog.lightSleepDuration, value: "240.5"),
            Expected(contract: MeasurementCatalog.sleepAwakeDuration, value: "60")
        ])
    }

    @Test("Oura activity totals and sleep durations state the contract's unit")
    func ouraUnits() throws {
        let context = try OuraFHIRTests.context()
        let day = try ProviderCivilDay(year: 2026, month: 11, day: 1, timeZone: context.sourceTimeZone)
        var activity = OuraActivityRecord(id: "activity", day: day)
        activity.activeCalories = 100
        activity.equivalentWalkingDistance = 750
        let end = WithingsFHIRTests.date
        var sleep = try OuraSleepRecord(id: "sleep", bedtime: ProviderFixtures.interval(end.addingTimeInterval(-28_800), end))
        sleep.totalSleepDuration = 25_200
        sleep.deepSleepDuration = 5_400
        sleep.remSleepDuration = 7_200
        sleep.lightSleepDuration = 14_430
        sleep.awakeTime = 3_600
        let results = try [OuraRecord.dailyActivity(activity), .sleep(sleep)].map { try ProviderFHIRConverter.convert($0, context: context) }
        try Self.expect(results, [
            Expected(contract: MeasurementCatalog.distance, value: "750"),
            Expected(contract: MeasurementCatalog.activeEnergy, value: "100"),
            Expected(contract: MeasurementCatalog.sleepDuration, value: "7"),
            Expected(contract: MeasurementCatalog.deepSleepDuration, value: "90"),
            Expected(contract: MeasurementCatalog.remSleepDuration, value: "120"),
            Expected(contract: MeasurementCatalog.lightSleepDuration, value: "240.5"),
            Expected(contract: MeasurementCatalog.sleepAwakeDuration, value: "60")
        ])
    }

    @Test("Google Health SI fields and sleep minutes state the contract's unit")
    func googleHealthUnits() throws {
        let context = try WithingsFHIRTests.context()
        let date = try ProviderFixtures.timestamp(WithingsFHIRTests.date)
        let interval = try ProviderFixtures.interval(WithingsFHIRTests.date.addingTimeInterval(-28_800), WithingsFHIRTests.date)
        var sleep = GoogleHealthDataPoint.SleepSummary()
        sleep.minutesAsleep = 450
        sleep.deepMinutes = 90
        sleep.remMinutes = 120
        sleep.lightMinutes = 240
        sleep.awakeMinutes = 60
        let values: [GoogleHealthDataPoint.Value] = [
            .distance(millimeters: 1_250, interval: interval),
            .weight(grams: 72_501, timestamp: date),
            .height(millimeters: 1_755, timestamp: date),
            .activeEnergy(kilocalories: 25, interval: interval),
            .basalEnergy(kilocalories: 500, interval: interval),
            .sleep(interval: interval, summary: sleep)
        ]
        let results = try values.map { try ProviderFHIRConverter.convert(GoogleHealthDataPoint(id: "native-one", value: $0), context: context) }
        try Self.expect(results, [
            Expected(contract: MeasurementCatalog.distance, value: "1.25"),
            Expected(contract: MeasurementCatalog.bodyWeight, value: "72.501"),
            Expected(contract: MeasurementCatalog.bodyHeight, value: "175.5"),
            Expected(contract: MeasurementCatalog.activeEnergy, value: "25"),
            Expected(contract: MeasurementCatalog.basalEnergy, value: "500"),
            Expected(contract: MeasurementCatalog.sleepDuration, value: "7.5"),
            Expected(contract: MeasurementCatalog.deepSleepDuration, value: "90"),
            Expected(contract: MeasurementCatalog.remSleepDuration, value: "120"),
            Expected(contract: MeasurementCatalog.lightSleepDuration, value: "240"),
            Expected(contract: MeasurementCatalog.sleepAwakeDuration, value: "60")
        ])
    }

    @Test("A duration is stated in its contract's time unit, and a non-time unit is refused")
    func durationUnits() throws {
        #expect(MeasurementCatalog.sleepDuration.quantity?.code == "h")
        #expect(try ProviderObservation.duration(seconds: 5_400, in: MeasurementCatalog.sleepDuration) == Decimal(string: "1.5"))
        #expect(try ProviderObservation.duration(seconds: 5_400, in: MeasurementCatalog.deepSleepDuration) == 90)
        #expect(throws: ProviderConversionError.invalidContract(MeasurementCatalog.distance.id)) {
            try ProviderObservation.duration(seconds: 60, in: MeasurementCatalog.distance)
        }
    }

    @Test("Every native recording stream is advertised as its provider's native recording token")
    func nativeRecordingTokens() async throws {
        let bytes = Data("{\"value\": 1}".utf8)
        let chunks = AsyncStream<Data> { continuation in
            continuation.yield(bytes)
            continuation.finish()
        }
        let file = try await RecordingFile.stage(chunks: chunks, maximumByteCount: bytes.count)
        for provider in ProviderCapabilities.Provider.allCases {
            let context = try provider == .oura ? OuraFHIRTests.context() : WithingsFHIRTests.context()
            let converted = try ProviderNativeRecording.Source.allCases.filter { $0.rawValue.hasPrefix(provider.rawValue + "/") }.map {
                let recording = try ProviderNativeRecording(
                    id: "native-one",
                    source: $0,
                    title: "Fixture",
                    file: file,
                    attachmentPath: "recording.json",
                    admission: .verifiedSanitizedInput
                )
                return try ProviderFHIRConverter.convert(recording, context: context).sourceToken
            }
            let advertised = ProviderCapabilities.sources(for: provider).filter { $0.conversionSupport == .nativeRecording }.map(\.token)
            #expect(Set(converted) == Set(advertised))
            #expect(!converted.isEmpty)
        }
    }
}


extension ProviderUnitConversionTests {
    private static func expect(_ results: [ProviderConversionResult], _ expected: [Expected]) throws {
        let observations = try results.flatMap { result in
            let record = try #require(result.record)
            let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
            return bundle.entry?.compactMap { $0.resource?.get() as? Observation } ?? []
        }
        for expectation in expected {
            let contract = expectation.contract
            let observation = try #require(observations.first { $0.meta?.profile?.contains(contract.profile) == true })
            guard case .quantity(let quantity) = observation.value else {
                Issue.record("\(contract.id) must state a Quantity")
                continue
            }
            #expect(quantity.value?.value?.decimal == Decimal(string: expectation.value), "\(contract.id)")
            #expect(quantity.code?.value?.string == contract.quantity?.code, "\(contract.id)")
            #expect(quantity.unit?.value?.string == contract.quantity?.unit, "\(contract.id)")
            #expect(quantity.system?.value?.url.absoluteString == "http://unitsofmeasure.org", "\(contract.id)")
        }
    }
}
