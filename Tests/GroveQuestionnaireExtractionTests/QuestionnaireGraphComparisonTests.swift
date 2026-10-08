//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import GroveFHIRContract
@testable import GroveQuestionnaireExtraction
import ModelsR4
import Testing


/// Holds the exporter's graphs to the bytes the projection emitted before it moved onto the shared producer and Device
/// and Provenance builders, admitting only the approved changes.
///
/// `QuestionnaireGraphBaselines.json` holds, per case, the graph JSON of `QuestionnaireExchangeProjection` at 48911aa0
/// for the same pair, event and conversion instant. The approved changes are exactly:
/// - every Device version coding states its display: `MDC_ID_PROD_SPEC_SW`, `Build`, `Operating system version`;
/// - `Bundle.timestamp`, `Provenance.recorded` and `Provenance.occurredDateTime` state the reservation's millisecond,
///   rendered by `ExchangeInstant`: in UTC, and `occurred` at the response's authored offset.
///
/// Everything else, from the entry order and every identity to the Observations and the response copy, is compared
/// byte for byte. The event is the ledger's, pinned to the baseline's, and no study is enrolled: a study context is the
/// third approved change, pinned by the exporter tests.
@Suite("Questionnaire Graph Bytes Against the Pre-Exporter Projection")
struct QuestionnaireGraphComparisonTests {
    private typealias Fixtures = QuestionnaireExportFixtures

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        /// The conversion instant, as seconds since 1970.
        let instant: TimeInterval
        /// What `Bundle.timestamp` and `Provenance.recorded` state now.
        let recorded: String
        /// What `Provenance.occurredDateTime` states now.
        let occurred: String

        var testDescription: String { name }
    }

    /// One case's wire bytes, their SHA-256 (base64url without padding), and the output revisions they last changed
    /// under.
    struct Revision: Sendable, CustomTestStringConvertible {
        let name: String
        let digest: String
        let assembler: UInt
        let questionnaire: UInt

        var testDescription: String { name }
    }

    static let cases = [
        // The guide's whole-second instant states the same bytes as before.
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

    /// The row of the guide's pair withdrawn a day after the guide's instant, which has no pre-exporter baseline.
    static let retraction = "retraction"

    /// Ties the bytes above, and the retraction's, to the output revisions the exporter's context fingerprint states.
    ///
    /// An exact redelivery is byte-identical only while the projection emits the same bytes for equal inputs, so any
    /// change to a case's `ExchangeGraph.json`, whether through the baseline or the approved changes, fails here until
    /// its row is updated, and the updated row must carry the bumped `ExchangeGraphAssembler.outputRevision` or
    /// `QuestionnaireExchangeProjection.outputRevision` when an output changed, which review checks in the diff.
    static let revisions = [
        Revision(name: "fractional", digest: "VQp5RruS7F5tWOE9aAzW3ekOrSLWms_Riz0Rgbe4LcY", assembler: 1, questionnaire: 1),
        Revision(name: "guide", digest: "xeDuynS1-jIdoAvYrsC-XkLYCx-xtpNamXzQjnJZGSA", assembler: 1, questionnaire: 1),
        Revision(name: "positive-offset", digest: "DNKXJaEUmirKNv8kom-DOykm02plWm-x_FhcmbD-KAw", assembler: 1, questionnaire: 1),
        Revision(name: retraction, digest: "NRvnnCMJ8vH79ZP5s8fGJfcs86RuWHCd2bg3Tavhbls", assembler: 1, questionnaire: 1),
        Revision(name: "utc", digest: "Cbmq9hnxZ109PJuV2HnYzpkEY9UwFs5nd_ipOrINoVA", assembler: 1, questionnaire: 1)
    ]

    private static func record(for name: String) throws -> QuestionnaireFHIRExporter.Record {
        switch name {
        case "positive-offset":
            try Fixtures.guideRecord { response in
                response.authored = FHIRPrimitive(DateTime(stringLiteral: "2026-08-29T06:02:00.25+05:30"))
                response.author = nil
                response.apply(writerContext: try Fixtures.writer(build: nil, host: nil))
            }
        case "utc":
            try Fixtures.guideRecord { response in
                response.authored = FHIRPrimitive(DateTime(stringLiteral: "2026-08-28T15:32:00Z"))
                response.apply(writerContext: try Fixtures.writer(build: nil, host: ("iPhone18,2", "27.0")))
            }
        default:
            try Fixtures.guideRecord()
        }
    }

    private static func baseline(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "QuestionnaireGraphBaselines", withExtension: "json"))
        let baselines = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(baselines[name] as? [String: Any])
    }

    /// The JSON text of `object` with sorted keys, so equal content compares equal whatever its key order.
    private static func canonical(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    /// The baseline with the approved changes applied, each checked against the value it replaces.
    private static func applyingApprovedChanges(to baseline: [String: Any], _ testCase: Case) throws -> [String: Any] {
        var bundle = baseline
        bundle["timestamp"] = try restated(bundle["timestamp"], as: testCase.recorded)
        var entries = try #require(bundle["entry"] as? [[String: Any]])
        for index in entries.indices {
            var resource = try #require(entries[index]["resource"] as? [String: Any])
            switch resource["resourceType"] as? String {
            case "Device":
                resource["version"] = try (resource["version"] as? [[String: Any]] ?? []).map(statingDisplay)
            case "Provenance":
                resource["recorded"] = try restated(resource["recorded"], as: testCase.recorded)
                resource["occurredDateTime"] = try restated(resource["occurredDateTime"], as: testCase.occurred)
            default:
                break
            }
            entries[index]["resource"] = resource
        }
        bundle["entry"] = entries
        return bundle
    }

    /// `lexeme`, after checking that the baseline's `value` names the same instant to the millisecond.
    private static func restated(_ value: Any?, as lexeme: String) throws -> String {
        let before = try DateTime(try #require(value as? String)).asNSDate()
        let after = try DateTime(lexeme).asNSDate()
        #expect(abs(before.timeIntervalSince(after)) <= 0.000_5, "\(value ?? "nil") is not \(lexeme) to the millisecond")
        return lexeme
    }

    /// The version with its type coding's display, which the baseline did not state.
    private static func statingDisplay(_ version: [String: Any]) throws -> [String: Any] {
        let displays = ["531975": "MDC_ID_PROD_SPEC_SW", "build": "Build", "os-version": "Operating system version"]
        var version = version
        var type = try #require(version["type"] as? [String: Any])
        var codings = try #require(type["coding"] as? [[String: Any]])
        for index in codings.indices {
            let code = try #require(codings[index]["code"] as? String)
            #expect(codings[index]["display"] == nil)
            let display: String = try #require(displays[code], "no display for version code \(code)")
            codings[index]["display"] = display
        }
        type["coding"] = codings
        version["type"] = type
        return version
    }

    /// The exporter's graph of `testCase`, under the baseline's event.
    private static func graph(_ testCase: Case) async throws -> ExchangeGraph {
        let exporter = try Fixtures.exporter(Fixtures.producer(pinning: Fixtures.producerInstance))
        let (exports, _) = try await Fixtures.collect(
            exporter,
            [try Self.record(for: testCase.name)],
            at: Date(timeIntervalSince1970: testCase.instant)
        )
        return try #require(exports.first?.graph)
    }

    /// The wire bytes `row` pins: its case's graph, or the guide pair's retraction under the baseline's producer.
    private static func bytes(of row: Revision) async throws -> Data {
        guard row.name == retraction else {
            return try await graph(#require(cases.first { $0.name == row.name })).json
        }
        let exporter = try Fixtures.exporter(Fixtures.producer(pinning: Fixtures.producerInstance))
        let withdrawnAt = Fixtures.instant.addingTimeInterval(86_400)
        var retractions: [QuestionnaireFHIRExporter.Retraction] = []
        _ = try await exporter.retract([.init(record: Fixtures.guideRecord(), withdrawnAt: withdrawnAt)], at: withdrawnAt) { retractions.append($0) }
        return try #require(retractions.first?.graph).json
    }

    @Test("The exporter's graph is the baseline with only the approved changes", arguments: Self.cases)
    func matchesTheBaselineUpToTheApprovedChanges(_ testCase: Case) async throws {
        let graph = try await Self.graph(testCase)
        let expected = try Self.applyingApprovedChanges(to: Self.baseline(testCase.name), testCase)
        #expect(try Self.canonical(JSONSerialization.jsonObject(with: graph.json)) == Self.canonical(expected))
    }

    @Test("Each row's bytes match its digest, whose revisions the code has reached", arguments: Self.revisions)
    func bytesMatchTheirRevision(_ row: Revision) async throws {
        #expect(Set(Self.revisions.map(\.name)) == Set(Self.cases.map(\.name) + [Self.retraction]))
        let digest = Data(SHA256.hash(data: try await Self.bytes(of: row))).base64URLEncodedStringWithoutPadding
        #expect(digest == row.digest, "\(row.name) changed to \(digest): update its row, with the bumped output revision if an output changed")
        #expect(row.assembler <= ExchangeGraphAssembler.outputRevision)
        #expect(row.questionnaire <= QuestionnaireExchangeProjection.outputRevision)
    }
}
