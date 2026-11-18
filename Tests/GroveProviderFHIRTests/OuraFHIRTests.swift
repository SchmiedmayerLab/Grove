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
struct OuraFHIRTests {
    static func context() throws -> ProviderConversionContext {
        let original = try WithingsFHIRTests.context()
        return try .init(
            producer: original.producer,
            scope: .global(BusinessIdentifier(system: "https://cloud.ouraring.com/document-id", value: "global")),
            instant: original.instant,
            sourceTimeZone: original.sourceTimeZone
        )
    }

    private static func observations(_ result: ProviderConversionResult) throws -> [Observation] {
        let record = try #require(result.record)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        return bundle.entry?.compactMap { $0.resource?.get() as? Observation } ?? []
    }

    @Test("Every advertised structured Oura source has a positive conversion fixture")
    func structuredCoverage() throws {
        let context = try Self.context()
        let date = WithingsFHIRTests.date
        let day = try ProviderCivilDay(year: 2026, month: 11, day: 1, timeZone: context.sourceTimeZone)
        var activity = OuraActivityRecord(id: "activity", day: day)
        activity.steps = 1_000
        activity.activeCalories = 100
        activity.equivalentWalkingDistance = 750
        var sleep = try OuraSleepRecord(id: "sleep", bedtime: ProviderFixtures.interval(date.addingTimeInterval(-28_800), date))
        sleep.totalSleepDuration = 25_200
        sleep.deepSleepDuration = 3_600
        sleep.remSleepDuration = 7_200
        sleep.lightSleepDuration = 14_400
        sleep.awakeTime = 3_600
        sleep.lowestHeartRate = 50
        sleep.averageBreath = 15
        let records: [OuraRecord] = [
            .dailyActivity(activity), .sleep(sleep),
            .dailyOxygenSaturation(id: "oxygen", day: day, average: 97),
            .workout(
                id: "workout",
                interval: try ProviderFixtures.interval(date.addingTimeInterval(-3_600), date),
                activity: try #require(.init(rawValue: "walking"))
            ),
            .vo2Max(id: "vo2", timestamp: try ProviderFixtures.timestamp(date), value: 50),
            .cardiovascularAge(id: "age", day: day, years: 40),
            .readiness(id: "readiness", day: day, score: 80)
        ]
        let results = try records.map { try ProviderFHIRConverter.convert($0, context: context) }
        let advertised = ProviderCapabilities.sources(for: .oura).filter { $0.conversionSupport == .structured }
        #expect(Set(results.map(\.sourceToken)) == Set(advertised.map(\.token)))
        #expect(results.allSatisfy { $0.record != nil && $0.omissions.isEmpty })
        let activityOutputs = try Self.observations(results[0])
        #expect(activityOutputs.contains { $0.meta?.profile?.contains(Profile.groveMobileDistance) == true })
        try ProviderFixtures.write(results, provider: "oura")
    }

    @Test("A civil day follows both DST transitions and rejects nonexistent calendar dates", arguments: [(3, 8, 23), (11, 1, 25)])
    func civilDay(month: Int, day: Int, hours: Int) throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let civil = try ProviderCivilDay(year: 2026, month: month, day: day, timeZone: zone)
        #expect(civil.interval.duration == Double(hours * 3_600))
        #expect(throws: ProviderConversionError.invalidCivilDay) {
            try ProviderCivilDay(year: 2026, month: 2, day: 30, timeZone: zone)
        }
        let result = try ProviderFHIRConverter.convert(OuraRecord.readiness(id: "readiness-one", day: civil, score: 80), context: Self.context())
        let observation = try Self.observations(result).first
        #expect(observation?.meta?.profile == [Profile.ouraReadinessScore, Profile.ouraObservation])
        #expect(observation?.issued == nil)
        guard case .period(let period) = observation?.effective else {
            Issue.record("Readiness must retain a complete civil-day Period")
            return
        }
        #expect(period.start != period.end)
    }

    @Test("Oura activity days start at 04:00 and retain daylight-saving changes", arguments: [(3, 7, 23), (11, 1, 24)])
    func activityBoundary(month: Int, day: Int, hours: Int) throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let sourceDay = try ProviderCivilDay(year: 2026, month: month, day: day, timeZone: zone)
        let activityInterval = try sourceDay.interval(startingAt: 4)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.hour, from: activityInterval.start) == 4)
        #expect(calendar.component(.day, from: activityInterval.start) == day)
        #expect(calendar.component(.hour, from: activityInterval.end) == 4)
        #expect(activityInterval.duration == Double(hours * 3_600))
        var source = OuraActivityRecord(id: "activity-boundary", day: sourceDay)
        source.steps = 100
        let result = try ProviderFHIRConverter.convert(OuraRecord.dailyActivity(source), context: Self.context())
        let observation = try Self.observations(result).first
        guard case .period(let period) = observation?.effective else {
            Issue.record("An activity day must retain its 04:00 boundaries")
            return
        }
        #expect(period.start?.value?.description.contains("T04:00:00") == true)
        #expect(period.end?.value?.description.contains("T04:00:00") == true)
        #expect(throws: ProviderConversionError.invalidCivilDay) { try sourceDay.interval(startingAt: 24) }
    }

    @Test("One sleep document preserves distinct aggregate methods and all output Provenance targets")
    func sleepOutputs() throws {
        let end = WithingsFHIRTests.date
        var source = try OuraSleepRecord(id: "sleep-one", bedtime: ProviderFixtures.interval(end.addingTimeInterval(-28_800), end))
        source.totalSleepDuration = 25_200
        source.deepSleepDuration = 3_600
        source.remSleepDuration = 7_200
        source.lightSleepDuration = 14_400
        source.awakeTime = 3_600
        source.lowestHeartRate = 50
        source.averageBreath = 15
        source.averageHRV = 30
        let result = try ProviderFHIRConverter.convert(OuraRecord.sleep(source), context: Self.context())
        let record = try #require(result.record)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: record.json)
        let observations = try Self.observations(result)
        #expect(observations.count == 7)
        let methods = observations.compactMap { $0.method?.coding?.first?.code?.value?.string }
        #expect(methods.contains("session-minimum"))
        #expect(methods.contains("session-mean"))
        #expect(result.omissions.map(\.element) == ["average_hrv"])
        let provenance = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Provenance }.first)
        #expect(provenance.target.count == 7)
        #expect(try ProviderFHIRConverter.convert(OuraRecord.sleep(source), context: Self.context()).record?.json == record.json)
    }

    @Test("Missing sleep bounds and the wrong provider key space never emit a record")
    func sourceEvidence() throws {
        var missing = OuraSleepRecord(id: "sleep-one", bedtime: nil)
        missing.totalSleepDuration = 3_600
        let result = try ProviderFHIRConverter.convert(OuraRecord.sleep(missing), context: Self.context())
        #expect(result.record == nil)
        #expect(result.omissions.first?.reason == .missingRequiredEvidence)
        #expect(throws: ProviderConversionError.invalidScope) {
            try ProviderFHIRConverter.convert(
                .vo2Max(id: "vo2", timestamp: ProviderFixtures.timestamp(WithingsFHIRTests.date), value: 50),
                context: WithingsFHIRTests.context()
            )
        }
    }
}
