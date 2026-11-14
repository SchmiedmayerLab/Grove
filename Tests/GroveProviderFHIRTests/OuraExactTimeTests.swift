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


struct OuraExactTimeTests {
    @Test("Sleep and workout keep independent source offsets through a daylight-saving transition")
    func exactSessionBounds() throws {
        let start = try ProviderTimestamp("2026-11-01T01:30:00.123456789-07:00")
        let end = try ProviderTimestamp("2026-11-01T01:30:00.123456788-08:00")
        let interval = try ProviderInterval(start: start, end: end)
        var sleep = OuraSleepRecord(id: "precise-sleep", sourceInterval: interval)
        sleep.totalSleepDuration = 3_599
        sleep.lowestHeartRate = 50
        sleep.averageBreath = 15
        #expect(sleep.bedtimeStart == nil && sleep.bedtimeEnd == nil)
        let records: [OuraRecord] = [
            .sleep(sleep), .exactWorkout(id: "precise-workout", interval: interval, activity: try #require(.init(rawValue: "walking")))
        ]
        let results = try records.map { try OuraFHIR.convert($0, context: OuraFHIRTests.context()) }
        for result in results {
            #expect(result.omissions.isEmpty)
            let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: #require(result.record?.json))
            let observations = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation })
            try #require(!observations.isEmpty)
            for observation in observations {
                guard case .period(let period) = observation.effective else {
                    Issue.record("Source session must be a complete Period")
                    continue
                }
                #expect(period.start?.value?.description == start.originalValue)
                #expect(period.end?.value?.description == end.originalValue)
            }
        }
        try ProviderFixtures.write(results, provider: "oura-exact")
        sleep.totalSleepDuration = 3_600
        #expect(throws: ProviderConversionError.self) { try OuraFHIR.convert(.sleep(sleep), context: OuraFHIRTests.context()) }
    }

    @Test("An exact VO2 timestamp retains source spelling and stable logical identity")
    func exactEstimate() throws {
        let timestamp = try ProviderTimestamp("2026-11-01T01:30:00.123456789-07:00")
        let value = OuraRecord.exactVO2Max(id: "precise-estimate", timestamp: timestamp, value: 45)
        let first = try OuraFHIR.convert(value, context: OuraFHIRTests.context())
        let second = try OuraFHIR.convert(value, context: OuraFHIRTests.context())
        #expect(first.record?.json == second.record?.json)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: #require(first.record?.json))
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
        guard case .dateTime(let effective) = observation.effective else {
            Issue.record("VO2 estimate must retain its source instant")
            return
        }
        #expect(effective.value?.description == timestamp.originalValue)
        try ProviderFixtures.write([first], provider: "oura-exact")
    }

    @Test("Exact workout bounds alone cannot invent the source activity")
    func missingActivity() throws {
        let interval = try ProviderInterval(
            start: ProviderTimestamp("2026-11-01T08:00:00.000000001Z"), end: ProviderTimestamp("2026-11-01T09:00:00.000000001Z")
        )
        let result = try OuraFHIR.convert(.exactWorkout(id: "workout", interval: interval), context: OuraFHIRTests.context())
        #expect(result.record == nil)
        #expect(result.omissions.first?.reason == .missingRequiredEvidence)
    }
}
