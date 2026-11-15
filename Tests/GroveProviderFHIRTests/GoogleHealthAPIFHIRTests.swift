//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import GroveProviderFHIR
import ModelsR4
import Testing


@Suite
struct GoogleHealthAPIFHIRTests {
    @Test("All structured Google Health tokens emit their declared outputs")
    func structuredCoverage() throws {
        let context = try WithingsFHIRTests.context()
        let date = WithingsFHIRTests.date
        let interval = DateInterval(start: date.addingTimeInterval(-28_800), end: date)
        let day = try ProviderCivilDay(year: 2026, month: 11, day: 1, timeZone: context.sourceTimeZone)
        var sleep = GoogleHealthDataPoint.SleepSummary()
        sleep.minutesAsleep = 420
        sleep.deepMinutes = 60
        sleep.remMinutes = 120
        sleep.lightMinutes = 240
        sleep.awakeMinutes = 60
        let values: [GoogleHealthDataPoint.Value] = [
            .steps(count: 100, interval: interval),
            .distance(millimeters: 1_250, interval: interval),
            .activeEnergy(kilocalories: 25, interval: interval),
            .weight(grams: 72_500, timestamp: date),
            .bodyFat(percentage: 25, timestamp: date),
            .height(millimeters: 1_750, timestamp: date),
            .vo2Max(value: 50, timestamp: date),
            .dailyOxygenSaturation(averagePercentage: 97, day: day),
            .heartRateVariability(timestamp: date, rmssdMilliseconds: 30, sdnnMilliseconds: 25),
            .dailyRestingHeartRate(beatsPerMinute: 65, day: day),
            .dailyRespiratoryRate(breathsPerMinute: 15, day: day),
            .bloodGlucose(milligramsPerDeciliter: 95, timestamp: date),
            .coreBodyTemperature(celsius: 37, timestamp: date),
            .floors(count: 3, interval: interval),
            .basalEnergy(kilocalories: 500, interval: interval),
            .sleep(interval: interval, summary: sleep),
            .exercise(interval: interval, activity: try #require(.init(rawValue: "walking")))
        ]
        let results = try values.map { try GoogleHealthAPIFHIR.convert(.init(id: "native-one", value: $0), context: context) }
        let advertised = ProviderCapabilities.sources(for: .googleHealthAPI).filter { $0.conversionSupport == .structured }
        #expect(Set(results.map(\.sourceToken)) == Set(advertised.map(\.token)))
        #expect(results.allSatisfy { $0.record != nil && $0.omissions.isEmpty })
        try ProviderFixtures.write(results, provider: "google-health-api")
        let hrv = try #require(results.first { $0.sourceToken == "heart-rate-variability" }?.record)
        #expect(hrv.outputFullURLs.count == 2)
        let sleepRecord = try #require(results.first { $0.sourceToken == "sleep" }?.record)
        #expect(sleepRecord.outputFullURLs.count == 5)
        #expect(Set(results.compactMap(\.record?.sourceRecord)).count == values.count)
    }

    @Test("SI input fields preserve the requested exact decimal units")
    func units() throws {
        let record = GoogleHealthDataPoint(id: "native-one", value: .weight(grams: 72_501, timestamp: WithingsFHIRTests.date))
        let result = try GoogleHealthAPIFHIR.convert(record, context: WithingsFHIRTests.context())
        let bytes = try #require(result.record?.json)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: bytes)
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
        guard case .quantity(let quantity) = observation.value else {
            Issue.record("Weight must be a Quantity")
            return
        }
        #expect(quantity.value?.value?.decimal == Decimal(string: "72.501"))
        #expect(quantity.code?.value?.string == "kg")
        #expect(observation.issued == nil)
    }
}
