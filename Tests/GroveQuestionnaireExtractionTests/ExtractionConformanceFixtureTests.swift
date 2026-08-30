//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
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
        let graph = try ObservationExtractionTests.projectedGraph()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try FileManager.default.createDirectory(
            at: Self.fixtureDirectory,
            withIntermediateDirectories: true
        )
        try encoder.encode(graph.bundle).write(
            to: Self.fixtureDirectory.appendingPathComponent("extraction-exchange-bundle.json")
        )
    }
}
