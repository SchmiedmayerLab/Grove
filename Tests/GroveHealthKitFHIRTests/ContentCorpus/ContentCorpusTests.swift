//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import Testing


/// The content corpus, oracle O2 of the HealthKit content rewrite: every checked-in vector converts to exactly the
/// tokens and bytes its line pins, the grid that generates the corpus still states exactly the checked-in inputs,
/// and every output a conversion emits is one the catalog names for its source type.
///
/// The corpus was recorded from the content builders the rewrite replaces, so any change in content output fails
/// here with the vector and the first differing path. A deliberate change regenerates the corpus (see
/// `ContentCorpusStore`) in the one commit whose enumerated diff it is; `content-corpus.changes.txt` lists that
/// diff. Regenerating the goldens leaves the corpus verified: each family has its own environment variable.
@Suite
struct ContentCorpusTests {
    /// The corpus splits into this many shards, which run in parallel.
    static let shards = 8

    /// The tokens a checked-in line's vector converts to now, checking that every emitted output is cataloged, or
    /// nil when this platform cannot rebuild the vector's record.
    private static func reproduction(of line: ContentCorpusStore.Line, uncataloged: inout [String]) async throws -> LosslessJSONValue? {
        do {
            guard case .convert(let source) = line.input else {
                return try await ContentCorpusRecorder.output(for: line.input)
            }
            let outcome = try await ContentCorpusRecorder.outcome(of: source)
            uncataloged += try ContentCorpusInvariants.uncatalogedOutputs(of: outcome, source: source).map { "\(line.id): \($0)" }
            return try ContentCorpusRecorder.render(outcome)
        } catch ContentCorpusSamples.RebuildError.unavailableHere {
            return nil
        }
    }

    /// Reproduces one shard. A vector whose record this platform does not have (watchOS has no clinical records or
    /// CDA documents) is skipped; every other vector must rebuild, convert to the pinned tokens, and print as the
    /// pinned bytes, which also catches what token equality cannot see (canonically equivalent strings).
    @Test(.enabled(if: !ContentCorpusStore.isGenerating), arguments: 0..<shards)
    func everyLineIsReproduced(shard: Int) async throws {
        var drifted: [String] = []
        var uncataloged: [String] = []
        var count = 0
        try await ContentCorpusStore.forEachLine(in: ContentCorpusStore.checkedIn(), shard: (shard, Self.shards)) { line in
            guard let actual = try await Self.reproduction(of: line, uncataloged: &uncataloged) else {
                return
            }
            count += 1
            if let difference = TokenDiff.firstDifference(expected: line.output, actual: actual) {
                drifted.append("\(line.id) at \(difference)")
            } else if try Data(ContentCorpusStore.line(line.vector, output: actual).utf8) != line.bytes {
                drifted.append("\(line.id): equal tokens, but the line prints other bytes (canonically equivalent text, or a restated input)")
            }
        }
        #expect(count > 0, "shard \(shard) of the corpus is empty")
        #expect(drifted.isEmpty, "\(drifted.count) vectors drifted from the corpus: \(drifted.prefix(25))")
        #expect(uncataloged.isEmpty, "\(uncataloged.count) emitted outputs the catalog does not name: \(uncataloged.prefix(25))")
    }

    /// The generator and the file agree line for line, and ids are unique; a failure names the first difference.
    @Test(.enabled(if: !ContentCorpusStore.isGenerating))
    func gridIsTheCheckedInCorpus() throws {
        let grid = ContentCorpusGrid.vectors
        let checkedIn = try ContentCorpusStore.vectors(in: ContentCorpusStore.checkedIn())
        let ids = grid.map(\.id)
        let duplicates = Dictionary(grouping: ids, by: \.self).filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "the grid names vectors twice: \(duplicates.prefix(10))")
        let lineIDs = checkedIn.map(\.id)
        if ids != lineIDs {
            let index = zip(ids, lineIDs).prefix { $0 == $1 }.count
            let vector = index < ids.count ? ids[index] : "no vector"
            let line = index < lineIDs.count ? lineIDs[index] : "no line"
            Issue.record("the grid's \(ids.count) vectors differ from the \(lineIDs.count) lines at line \(index + 1): \(vector), the corpus \(line)")
        }
        let restated = try zip(grid, checkedIn).compactMap { vector, line in
            try ContentCorpusStore.inputText(vector.input) == ContentCorpusStore.inputText(line.input) ? nil : vector.id
        }
        #expect(restated.isEmpty, "\(restated.count) vectors state other inputs than the corpus: \(restated.prefix(10))")
    }

    /// With `GROVE_CONTENT_CORPUS_OUTPUT_DIR` set, records every vector twice, requires identical tokens, compares
    /// the result with the checked-in corpus, and writes the corpus and `content-corpus.changes.txt` there. It
    /// writes nothing when a vector converts nondeterministically, or when the regeneration drops or duplicates an
    /// id or restates an input `GROVE_CONTENT_CORPUS_ALLOW_RESTATED_INPUTS` does not admit. Regenerate on macOS.
    @Test(.enabled(if: ContentCorpusStore.isGenerating))
    func corpusRegenerates() async throws {
        #if os(watchOS)
        Issue.record("regenerate the corpus on macOS: watchOS has no clinical records to rebuild")
        #else
        var lines: [String] = []
        var nondeterministic: [String] = []
        for vector in ContentCorpusGrid.vectors {
            let output = try await ContentCorpusRecorder.output(for: vector.input)
            if try await ContentCorpusRecorder.output(for: vector.input) != output {
                nondeterministic.append(vector.id)
            }
            lines.append(try ContentCorpusStore.line(vector, output: output))
        }
        try #require(nondeterministic.isEmpty, "vectors that do not convert deterministically: \(nondeterministic)")
        let changes = try ContentCorpusChanges(checkedIn: ContentCorpusStore.checkedIn(), regenerated: lines)
        try #require(changes.removed.isEmpty, "the regeneration drops ids: \(changes.removed.prefix(25))")
        try #require(changes.duplicated.isEmpty, "the regeneration names ids twice: \(changes.duplicated.prefix(25))")
        let unallowed = changes.unallowedRestatements
        try #require(unallowed.isEmpty, "the regeneration restates the inputs of \(unallowed.count) ids (\(unallowed.prefix(10))); see ContentCorpusChanges")
        try ContentCorpusStore.write(lines, changes: changes)
        #endif
    }
}

#endif
