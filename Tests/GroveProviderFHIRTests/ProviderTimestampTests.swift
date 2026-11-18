//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveProviderFHIR
import ModelsR4
import Testing


@Suite
struct ProviderTimestampTests {
    @Test("Exact instant comparison preserves offsets and nanoseconds")
    func exactOrdering() throws {
        let utc = try ProviderTimestamp("2026-11-01T08:30:00.123456789Z")
        let offset = try ProviderTimestamp("2026-11-01T01:30:00.123456789-07:00")
        let next = try ProviderTimestamp("2026-11-01T08:30:00.123456790Z")
        #expect(utc == offset)
        #expect(Set([utc, offset]).count == 1)
        #expect(utc < next)
        #expect(offset.originalValue == "2026-11-01T01:30:00.123456789-07:00")
        #expect(try ProviderInterval(start: utc, end: next).duration == Decimal(string: "0.000000001"))
        #expect(throws: ProviderConversionError.invalidInterval) { try ProviderInterval(start: utc, end: offset) }
        #expect(throws: ProviderConversionError.invalidInterval) { try ProviderInterval(start: next, end: utc) }
        #expect(try ProviderTimestamp("1969-12-31T23:59:59.999999999Z") < ProviderTimestamp("1970-01-01T00:00:00Z"))
        #expect(try ProviderTimestamp("2024-02-29T23:59:59Z") < ProviderTimestamp("2024-03-01T00:00:00Z"))
    }

    @Test("Malformed dates and unsupported precision cannot be normalized silently", arguments: [
        "2026-02-29T00:00:00Z", "2024-02-30T00:00:00Z", "2026-04-31T00:00:00Z",
        "2026-00-01T00:00:00Z", "2026-01-00T00:00:00Z", "0000-01-01T00:00:00Z",
        "2026-01-01T24:00:00Z", "2026-01-01T00:00:60Z", "2026-01-01T00:00:00-00:00",
        "2026-01-01T00:00:00.1234567890Z", "2026-01-01T00:00:00.Z", "2026-01-01T00:00:00",
        "2026-01-01T00:00:00Z\n", " 2026-01-01T00:00:00Z", "2026-01-01T00:00:00+25:00"
    ])
    func rejectsInvalidSource(_ value: String) {
        #expect(throws: ProviderTimestamp.ValidationError.self) { try ProviderTimestamp(value) }
    }

    @Test("Every Google source value keeps its exact FHIR temporal bounds")
    func googleVariantsKeepSourceTimes() throws {
        let start = try ProviderTimestamp("2026-11-01T01:30:00.123456789-07:00")
        let end = try ProviderTimestamp("2026-11-01T01:30:00.123456788-08:00")
        let interval = try ProviderInterval(start: start, end: end)
        var summary = GoogleHealthDataPoint.SleepSummary()
        summary.minutesAsleep = 59
        let values: [GoogleHealthDataPoint.Value] = [
            .steps(count: 10, interval: interval), .distance(millimeters: 5_000, interval: interval),
            .activeEnergy(kilocalories: 30, interval: interval), .weight(grams: 72_500, timestamp: start),
            .bodyFat(percentage: 25, timestamp: start), .height(millimeters: 1_750, timestamp: start),
            .vo2Max(value: 50, timestamp: start),
            .heartRateVariability(timestamp: start, rmssdMilliseconds: 30, sdnnMilliseconds: 25),
            .bloodGlucose(milligramsPerDeciliter: 95, timestamp: start), .coreBodyTemperature(celsius: 37, timestamp: start),
            .floors(count: 3, interval: interval), .basalEnergy(kilocalories: 500, interval: interval),
            .sleep(interval: interval, summary: summary),
            .exercise(interval: interval, activity: try #require(.init(rawValue: "walking")))
        ]
        for value in values {
            let result = try ProviderFHIRConverter.convert(GoogleHealthDataPoint(id: "exact-source", value: value), context: WithingsFHIRTests.context())
            let bytes = try #require(result.record?.json)
            let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: bytes)
            let observations = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation })
            try #require(!observations.isEmpty)
            for observation in observations {
                switch observation.effective {
                case .dateTime(let timestamp):
                    #expect(timestamp.value?.description == start.originalValue)
                case .period(let period):
                    #expect(period.start?.value?.description == start.originalValue)
                    #expect(period.end?.value?.description == end.originalValue)
                default:
                    Issue.record("Source observation must retain its complete temporal shape")
                }
            }
        }
    }

    @Test("A nanosecond correction changes content identity but retains source identity")
    func exactCorrectionAndSleepBoundary() throws {
        let start = try ProviderTimestamp("2026-11-01T08:30:00.123456789Z")
        let correction = try ProviderTimestamp("2026-11-01T08:30:00.123456790Z")
        let context = try WithingsFHIRTests.context()
        let first = try ProviderFHIRConverter.convert(GoogleHealthDataPoint(id: "one", value: .weight(grams: 72_500, timestamp: start)), context: context)
        let second = try ProviderFHIRConverter.convert(
            GoogleHealthDataPoint(id: "one", value: .weight(grams: 72_500, timestamp: correction)),
            context: context
        )
        #expect(first.record?.sourceRecord == second.record?.sourceRecord)
        #expect(first.record?.json != second.record?.json)
        let end = try ProviderTimestamp("2026-11-01T08:31:00.123456788Z")
        let interval = try ProviderInterval(start: start, end: end)
        var summary = GoogleHealthDataPoint.SleepSummary()
        summary.minutesAsleep = 1
        #expect(throws: ProviderConversionError.self) {
            try ProviderFHIRConverter.convert(GoogleHealthDataPoint(id: "sleep", value: .sleep(interval: interval, summary: summary)), context: context)
        }
    }
}
