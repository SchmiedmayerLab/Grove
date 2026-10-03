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
/// tokens its line pins, the grid that generates the corpus still states exactly the checked-in inputs, and every
/// output a conversion emits is one the catalog names for its source type.
///
/// The corpus was recorded from the content builders the rewrite replaces, so any change in content output fails
/// here with the vector and the first differing path. A deliberate change regenerates the corpus (see
/// `ContentCorpusStore`) in the one commit whose enumerated diff it is.
@Suite
struct ContentCorpusTests {
    /// The corpus splits into this many shards, which run in parallel.
    static let shards = 8

    /// Whether this platform can rebuild a vector: watchOS has no clinical records or CDA documents.
    static func isAvailableHere(_ id: String) -> Bool {
        #if os(watchOS)
        !id.hasPrefix("cda/") && !id.hasPrefix("clinical/")
        #else
        true
        #endif
    }

    @Test(.enabled(if: !ContentCorpusStore.isGenerating), arguments: 0..<shards)
    func everyLineIsReproduced(shard: Int) throws {
        var drifted: [String] = []
        var uncataloged: [String] = []
        var count = 0
        try ContentCorpusStore.forEachLine(in: ContentCorpusStore.checkedIn(), shard: (shard, Self.shards)) { line in
            guard Self.isAvailableHere(line.id) else {
                return
            }
            count += 1
            let actual: LosslessJSONValue
            if case .convert(let source) = line.input {
                let outcome = try ContentCorpusRecorder.outcome(of: source)
                uncataloged += try ContentCorpusInvariants.uncatalogedOutputs(of: outcome).map { "\(line.id): \($0)" }
                actual = try ContentCorpusRecorder.render(outcome)
            } else {
                actual = try ContentCorpusRecorder.output(for: line.input)
            }
            if let difference = TokenDiff.firstDifference(expected: line.output, actual: actual) {
                drifted.append("\(line.id) at \(difference)")
            }
        }
        #expect(count > 0, "shard \(shard) of the corpus is empty")
        #expect(drifted.isEmpty, "\(drifted.count) vectors drifted from the corpus: \(drifted.prefix(25))")
        #expect(uncataloged.isEmpty, "\(uncataloged.count) emitted outputs the catalog does not name: \(uncataloged.prefix(25))")
    }

    /// The generator and the file agree line for line, and ids are unique.
    @Test(.enabled(if: !ContentCorpusStore.isGenerating))
    func gridIsTheCheckedInCorpus() throws {
        let grid = ContentCorpusGrid.vectors.filter { Self.isAvailableHere($0.id) }
        let checkedIn = try ContentCorpusStore.vectors(in: ContentCorpusStore.checkedIn()).filter { Self.isAvailableHere($0.id) }
        let ids = grid.map(\.id)
        let stray = Set(checkedIn.map(\.id)).subtracting(ids).sorted().prefix(10)
        let missing = Set(ids).subtracting(checkedIn.map(\.id)).sorted().prefix(10)
        #expect(Set(ids).count == ids.count, "the grid names a vector twice")
        #expect(checkedIn.map(\.id) == ids, "lines without a vector: \(stray); vectors without a line: \(missing)")
        let changed = try zip(grid, checkedIn).compactMap { vector, line in
            try ContentCorpusStore.inputText(vector.input) == ContentCorpusStore.inputText(line.input) ? nil : vector.id
        }
        #expect(changed.isEmpty, "the grid states other inputs than the corpus: \(changed.prefix(10))")
    }

    /// With `GROVE_GOLDEN_OUTPUT_DIR` set, records every vector twice, requires identical tokens, and writes the
    /// corpus there. Regenerate on macOS (the gate's platform), never on watchOS, whose grid has no clinical documents.
    @Test(.enabled(if: ContentCorpusStore.isGenerating))
    func corpusRegenerates() throws {
        var lines: [String] = []
        var nondeterministic: [String] = []
        for vector in ContentCorpusGrid.vectors {
            try autoreleasepool {
                let output = try ContentCorpusRecorder.output(for: vector.input)
                if try ContentCorpusRecorder.output(for: vector.input) != output {
                    nondeterministic.append(vector.id)
                }
                lines.append(try ContentCorpusStore.line(vector, output: output))
            }
        }
        #expect(nondeterministic.isEmpty, "vectors that do not convert deterministically: \(nondeterministic)")
        try ContentCorpusStore.write(lines)
    }
}

#endif
