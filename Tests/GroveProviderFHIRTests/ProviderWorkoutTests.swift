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
struct ProviderWorkoutTests {
    @Test("An interval without an evidenced activity never emits an invalid workout or a guessed other activity")
    func missingActivity() throws {
        let context = try WithingsFHIRTests.context()
        let interval = DateInterval(start: WithingsFHIRTests.date.addingTimeInterval(-3_600), end: WithingsFHIRTests.date)
        let results =
            try WithingsFHIR.convert(.workout(id: "one", interval: interval), context: context) + [
                OuraFHIR.convert(.workout(id: "one", start: interval.start, end: interval.end), context: OuraFHIRTests.context()),
                GoogleHealthAPIFHIR.convert(.init(id: "one", value: .exercise(interval: interval)), context: context)
            ]
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.record == nil && $0.omissions.first?.reason == .missingRequiredEvidence })
        #expect(ProviderWorkoutActivity(rawValue: "unknown") == nil)
    }

    @Test("An evidenced activity becomes the required coded workout value")
    func codedActivity() throws {
        let interval = DateInterval(start: WithingsFHIRTests.date.addingTimeInterval(-3_600), end: WithingsFHIRTests.date)
        let activity = try #require(ProviderWorkoutActivity(rawValue: "walking"))
        let result = try GoogleHealthAPIFHIR.convert(
            .init(id: "one", value: .exercise(interval: interval, activity: activity)),
            context: WithingsFHIRTests.context()
        )
        let bytes = try #require(result.record?.json)
        let bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: bytes)
        let observation = try #require(bundle.entry?.compactMap { $0.resource?.get() as? Observation }.first)
        guard case .codeableConcept(let value) = observation.value else {
            Issue.record("A workout requires its source-supported activity value")
            return
        }
        #expect(value.coding?.first?.code?.value?.string == activity.rawValue)
        #expect(value.coding?.first?.system?.value?.url.absoluteString == "https://grovealliance.org/fhir/mobile/CodeSystem/grove-workout-activity")
    }
}
