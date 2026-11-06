//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveQuestionnaireExtraction
import ModelsR4
import Testing


/// Holds the exporter's records to their bytes.
///
/// `QuestionnaireGraphBaselines.json` holds, per case, the `ExchangeRecord.json` of the same pair and conversion instant.
/// Those bytes are the wire format: a record's version digests them, so any change here is a new version of every record
/// the case stands for, and is one review reads in the diff. The `guide` case states the guide's pair, whose keys
/// `ObservationExtractionTests` holds to the guide's own bundle.
@Suite("Questionnaire Record Bytes")
struct QuestionnaireGraphComparisonTests {
    private typealias Fixtures = QuestionnaireExportFixtures

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        /// The conversion instant, as seconds since 1970.
        let instant: TimeInterval
        /// What `Bundle.timestamp` and `Provenance.recorded` state.
        let recorded: String
        /// What `Provenance.occurredDateTime` states.
        let occurred: String

        var testDescription: String { name }
    }

    static let cases = [
        Case(name: "guide", instant: 1_787_931_125, recorded: "2026-08-28T15:32:05Z", occurred: "2026-08-28T08:32:05-07:00"),
        Case(
            name: "fractional",
            instant: 1_787_931_125.1234567,
            recorded: "2026-08-28T15:32:05.123Z",
            occurred: "2026-08-28T08:32:05.123-07:00"
        ),
        // Authored at a fractional instant east of UTC, no author, and a writer without build or host.
        Case(
            name: "positive-offset",
            instant: 1_788_010_000.9876,
            recorded: "2026-08-29T13:26:40.988Z",
            occurred: "2026-08-29T18:56:40.988+05:30"
        ),
        // Authored in UTC by a writer with a host and no build; the fraction rounds away.
        Case(name: "utc", instant: 1_787_931_125.0004, recorded: "2026-08-28T15:32:05Z", occurred: "2026-08-28T15:32:05Z")
    ]

    /// The row of the guide's pair withdrawn a day after the guide's instant.
    static let retraction = "retraction"

    private static func pair(for name: String) throws -> QuestionnaireFHIRExporter.Record {
        switch name {
        case "positive-offset":
            try Fixtures.guideRecord { response in
                response.authored = FHIRPrimitive(DateTime(stringLiteral: "2026-08-29T06:02:00.25+05:30"))
                response.author = nil
                response.apply(writerContext: try Fixtures.writer())
            }
        case "utc":
            try Fixtures.guideRecord { response in
                response.authored = FHIRPrimitive(DateTime(stringLiteral: "2026-08-28T15:32:00Z"))
                response.apply(writerContext: try Fixtures.writer(hostModel: "iPhone18,2", hostOperatingSystemVersion: "27.0"))
            }
        default:
            try Fixtures.guideRecord()
        }
    }

    /// The canonical bytes of the row `name`, whose number lexemes the lossless parse keeps.
    private static func baseline(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "QuestionnaireGraphBaselines", withExtension: "json"))
        guard case .object(let baselines) = try LosslessJSONValue(parsing: Data(contentsOf: url)) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try #require(baselines[name]).canonicalBytes()
    }

    /// The exporter's record of `testCase`.
    static func record(_ testCase: Case) async throws -> ExchangeRecord {
        let exports = try await Fixtures.collect(
            Fixtures.exporter(Fixtures.producer()),
            [try Self.pair(for: testCase.name)],
            at: Date(timeIntervalSince1970: testCase.instant)
        )
        return try #require(exports.first?.record)
    }

    /// The guide pair's retraction, a day after the guide's instant.
    static func retractionRecord() async throws -> ExchangeRecord {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let withdrawnAt = Fixtures.instant.addingTimeInterval(86_400)
        var retractions: [QuestionnaireFHIRExporter.Retraction] = []
        try await exporter.retract([.init(record: Fixtures.guideRecord(), withdrawnAt: withdrawnAt)], at: withdrawnAt) { retractions.append($0) }
        return try #require(retractions.first?.record)
    }

    @Test("Each record states its baseline's bytes", arguments: Self.cases)
    func matchesTheBaseline(_ testCase: Case) async throws {
        let record = try await Self.record(testCase)
        #expect(String(decoding: record.json, as: UTF8.self) == String(decoding: try Self.baseline(testCase.name), as: UTF8.self))
    }

    @Test("Each record states the conversion instant, in UTC and at the response's authored offset", arguments: Self.cases)
    func statesItsInstants(_ testCase: Case) async throws {
        let record = try await Self.record(testCase)
        let provenance = try record.provenance
        #expect(try record.bundle.timestamp?.value?.description == testCase.recorded)
        #expect(provenance.recorded.value?.description == testCase.recorded)
        guard case .dateTime(let occurred)? = provenance.occurred else {
            Issue.record("the Provenance states no occurred time")
            return
        }
        #expect(occurred.value?.description == testCase.occurred)
    }

    @Test("The guide pair's retraction states its baseline's bytes")
    func retractionMatchesTheBaseline() async throws {
        let record = try await Self.retractionRecord()
        #expect(String(decoding: record.json, as: UTF8.self) == String(decoding: try Self.baseline(Self.retraction), as: UTF8.self))
    }
}
