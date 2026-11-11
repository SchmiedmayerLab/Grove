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


/// Emits the projected exchange bundle for inspection and future conformance wiring.
///
/// The producer validator cannot yet accept a response bundle: its semantic-vector coverage
/// pins one canonical value and instant per measurement, and observation-based extraction
/// gives every measurement in one response the same authored instant, so a response bundle
/// can never match per-measurement vectors. Until the guides define how vectors apply to
/// response bundles, the bundle's conformance is enforced by the exchange graph validation
/// at construction and by the canonical identity vectors in the extraction tests.
@Suite("Extraction Conformance Fixtures")
struct ExtractionConformanceFixtureTests {
    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/extraction-fixtures/questionnaire")
    }

    @Test
    func writeExtractionConformanceFixtures() throws {
        let record = try ObservationExtractionTests.projectedRecord()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try FileManager.default.createDirectory(
            at: Self.fixtureDirectory,
            withIntermediateDirectories: true
        )
        try encoder.encode(record.bundle).write(
            to: Self.fixtureDirectory.appendingPathComponent("extraction-exchange-bundle.json")
        )
    }

    /// Writes the guide's response and a second one as one Bundle, and their withdrawals as another, as an upload packs them.
    @Test
    func writePackedBundles() async throws {
        let records = try [
            QuestionnaireExportFixtures.guideRecord(),
            QuestionnaireExportFixtures.guideRecord { response in
                response.identifier = Identifier(system: response.identifier?.system, value: "home-vitals-2026-08-29")
            }
        ]
        let exporter = try QuestionnaireExportFixtures.exporter(QuestionnaireExportFixtures.producer(studies: [
            QuestionnaireExportFixtures.study("study-a"),
            QuestionnaireExportFixtures.study("study-b")
        ]))
        var active = ExchangeBundlePacker(kind: .active)
        for export in try await QuestionnaireExportFixtures.collect(exporter, records) {
            #expect(try active.insert(try #require(export.record)) == .inserted)
        }
        var retraction = ExchangeBundlePacker(kind: .retraction)
        let instant = QuestionnaireExportFixtures.instant
        try await exporter.retract(records.map { .init(record: $0, withdrawnAt: instant) }, at: instant) { withdrawal in
            let result = try retraction.insert(try #require(withdrawal.record))
            #expect(result == .inserted)
        }
        try FileManager.default.createDirectory(at: Self.fixtureDirectory, withIntermediateDirectories: true)
        try active.bundle(packedAt: instant).json.write(to: Self.fixtureDirectory.appendingPathComponent("packed-exchange-bundle.json"))
        try retraction.bundle(packedAt: instant).json.write(to: Self.fixtureDirectory.appendingPathComponent("packed-retraction-bundle.json"))
    }
}
