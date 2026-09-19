//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import FHIRModelsExtensions
import Foundation
import ModelsR4
import Testing


@Suite
struct TimeZoneTests {
    @Test(arguments: [
        ("Europe/Berlin", "2025-10-26T00:55:00Z", "2025-10-26T01:05:00Z"),
        ("America/Los_Angeles", "2025-11-02T08:55:00Z", "2025-11-02T09:05:00Z"),
        ("Europe/Berlin", "2025-10-26T01:05:00Z", "2025-10-26T01:05:00Z")
    ])
    func repeatedHourPreservesInstants(_ zoneName: String, _ startText: String, _ endText: String) throws {
        let zone = try #require(TimeZone(identifier: zoneName))
        let start = try #require(ISO8601DateFormatter().date(from: startText))
        let end = try #require(ISO8601DateFormatter().date(from: endText))
        var observation = Observation(code: CodeableConcept(), status: FHIRPrimitive(.final))
        try observation.setEffective(startDate: start, endDate: end, timeZone: zone)
        let decoded = try JSONDecoder().decode(Observation.self, from: JSONEncoder().encode(observation))
        switch try #require(decoded.effective) {
        case .period(let period):
            #expect(try #require(period.start?.value).asNSDate() == start)
            #expect(try #require(period.end?.value).asNSDate() == end)
        case .dateTime(let value):
            #expect(start == end)
            #expect(try #require(value.value).asNSDate() == start)
        default:
            Issue.record("Unexpected effective value")
        }
    }

    /// Tests creating a `Period` instance using different time zones for start and end date.
    @Test
    func multiTimeZonePeriod() throws {
        let timeZoneLA = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let timeZoneDE = try #require(TimeZone(identifier: "Europe/Berlin"))
        
        // we're choosing this exact date bc at that point in time, LA was already in DST, while germany was not.
        let startDateLA = try #require(Calendar.current.date(from: .init(timeZone: timeZoneLA, year: 2025, month: 3, day: 14, hour: 7)))
        let startDateDE = try #require(Calendar.current.date(from: .init(timeZone: timeZoneDE, year: 2025, month: 3, day: 14, hour: 15)))
        let endDateLA = try #require(Calendar.current.date(from: .init(timeZone: timeZoneLA, year: 2025, month: 3, day: 14, hour: 7, minute: 30)))
        let endDateDE = try #require(Calendar.current.date(from: .init(timeZone: timeZoneDE, year: 2025, month: 3, day: 14, hour: 15, minute: 30)))
        
        #expect(try DateTime(date: startDateLA, timeZone: timeZoneLA).asNSDate() == DateTime(date: startDateDE, timeZone: timeZoneDE).asNSDate())
        
        #expect(try DateTime(date: endDateLA, timeZone: timeZoneLA).asNSDate() == DateTime(date: endDateDE, timeZone: timeZoneDE).asNSDate())
        
        let period1 = Period(
            end: FHIRPrimitive(try DateTime(date: startDateLA, timeZone: timeZoneLA)),
            start: FHIRPrimitive(try DateTime(date: endDateDE, timeZone: timeZoneDE))
        )
        let period2 = Period(
            end: FHIRPrimitive(try DateTime(date: startDateDE, timeZone: timeZoneDE)),
            start: FHIRPrimitive(try DateTime(date: endDateLA, timeZone: timeZoneLA))
        )
        
        #expect(try #require(period1.start?.value).asNSDate() == #require(period2.start?.value).asNSDate())
        #expect(try #require(period1.end?.value).asNSDate() == #require(period2.end?.value).asNSDate())
    }
}
