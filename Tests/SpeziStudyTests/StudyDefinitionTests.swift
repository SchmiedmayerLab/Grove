//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length

import Foundation
import struct ModelsR4.Questionnaire
import SpeziFoundation
import SpeziHealthKit
import SpeziHealthKitBulkExport
@testable import SpeziStudyDefinition
import Testing


@Suite
struct StudyDefinitionTests {
    @Test
    func studyEncodingAndDecoding() throws {
        let data = try JSONEncoder().encode(Self.testStudyBundle)
        let decodedStudy = try JSONDecoder().decode(StudyDefinition.self, from: data, configuration: .init(allowTrivialSchemaMigrations: true))
        #expect(try decodedStudy == Self.testStudyBundle)
    }
    
    @Test
    func decodedStudyVersionExtraction() throws {
        let input1 = try JSONEncoder().encode(Self.testStudyBundle)
        #expect(try StudyDefinition.schemaVersion(of: input1, using: JSONDecoder()) == StudyDefinition.schemaVersion)
        
        let input2 = Data(#"{"schemaVersion":"1.2.3", "glorb": "florb"}"#.utf8)
        #expect(try StudyDefinition.schemaVersion(of: input2, using: JSONDecoder()) == Version(1, 2, 3))
    }
    
    @Test
    func componentScheduleDescriptions() {
        typealias Schedule = StudyDefinition.ComponentSchedule.ScheduleDefinition
        #expect(Schedule.once(.date(.init(
            timeZone: .losAngeles, year: 2025, month: 06, day: 27, hour: 13, minute: 37
        ))).description == "once; at 2025-06-27T20:37:00Z")
        #expect(Schedule.once(.date(.init(
            timeZone: .berlin, year: 2025, month: 06, day: 27, hour: 13, minute: 37
        ))).description == "once; at 2025-06-27T11:37:00Z")
        #expect(Schedule.repeated(.daily(interval: 1, hour: 12, minute: 00)).description == "daily @ 12:00")
        #expect(Schedule.repeated(.daily(interval: 1, hour: 12, minute: 00, second: 9)).description == "daily @ 12:00:09")
        #expect(Schedule.repeated(.daily(interval: 1, hour: 09, minute: 07)).description == "daily @ 09:07")
        #expect(Schedule.repeated(.daily(interval: 2, hour: 09, minute: 07)).description == "every 2nd day @ 09:07")
        #expect(Schedule.repeated(.daily(interval: 3, hour: 09, minute: 07)).description == "every 3rd day @ 09:07")
        #expect(Schedule.repeated(.daily(interval: 4, hour: 09, minute: 07)).description == "every 4th day @ 09:07")
        #expect(Schedule.repeated(.daily(interval: 1, hour: 12, minute: 00), offset: .init(day: 2)).description == "daily @ 12:00; offset by day: 2")
        #expect(Schedule.repeated(.daily(interval: 1, hour: 12, minute: 00), offset: .init(day: 2, hour: 12)).description == "daily @ 12:00; offset by day: 2 hour: 12")
        #expect(Schedule.repeated(.daily(interval: 1, hour: 09, minute: 07), offset: .init(minute: 12)).description == "daily @ 09:07; offset by minute: 12")
        #expect(Schedule.repeated(.daily(interval: 2, hour: 09, minute: 07), offset: .init(hour: 17)).description == "every 2nd day @ 09:07; offset by hour: 17")
        #expect(Schedule.repeated(.daily(interval: 3, hour: 09, minute: 07), offset: .init(weekOfYear: 1)).description == "every 3rd day @ 09:07; offset by weekOfYear: 1")
        #expect(Schedule.repeated(.daily(interval: 4, hour: 09, minute: 07), offset: .init(weekOfYear: 2)).description == "every 4th day @ 09:07; offset by weekOfYear: 2")
        #expect(Schedule.once(.event(.enrollment)).description == "once; at enrollment")
        #expect(Schedule.once(.event(.enrollment, offsetInDays: 2)).description == "once; at enrollment + 2 days")
        #expect(Schedule.once(.event(.enrollment, offsetInDays: 2, time: .init(hour: 9, minute: 41))).description == "once; at enrollment + 2 days; at 09:41")
    }
}


extension Locale.Language {
    static let english = Locale.Language(identifier: "en")
    static let spanish = Locale.Language(identifier: "es")
    static let german = Locale.Language(identifier: "de")
    static let french = Locale.Language(identifier: "fr")
}


extension Questionnaire {
    static func named(_ name: String) throws -> Questionnaire {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw NSError(
                domain: "edu.stanford.spezi",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load data"]
            )
        }
        return try JSONDecoder().decode(Questionnaire.self, from: data)
    }
}


// MARK: Test Study

extension StudyDefinitionTests {
    static var testStudyBundle: StudyDefinition {
        get throws {
            try StudyBundleTests.testStudyBundle.studyDefinition
        }
    }
}
