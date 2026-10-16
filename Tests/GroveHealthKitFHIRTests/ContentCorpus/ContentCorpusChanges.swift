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


/// How a regenerated corpus differs from the checked-in one, line by line and token by token, read without the
/// input schema so a corpus written by any version compares.
///
/// Ids are append-only: an id names one input for as long as the corpus exists, so a regeneration may add
/// vectors but never drops an id, names two lines alike, or restates an existing id's input (`corpusRegenerates`
/// refuses to write such a corpus). Only a commit that changes how inputs are stated, and enumerates every
/// restated id, sets `GROVE_CONTENT_CORPUS_ALLOW_RESTATED_INPUTS` (under `xcodebuild`, with the `TEST_RUNNER_`
/// prefix) to the comma-separated id prefixes whose inputs it restates.
struct ContentCorpusChanges {
    /// One line read as tokens.
    private struct Tokens {
        /// The line's input.
        let input: LosslessJSONValue
        /// The line's output.
        let output: LosslessJSONValue
    }

    /// The environment variable that admits restated inputs for one regeneration.
    static let allowRestatedInputs = "GROVE_CONTENT_CORPUS_ALLOW_RESTATED_INPUTS"

    /// The id prefixes whose inputs this regeneration may restate.
    static var restatablePrefixes: [String] {
        (ProcessInfo.processInfo.environment[allowRestatedInputs] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// Ids the regeneration adds, in corpus order.
    private(set) var added: [String] = []
    /// Ids the checked-in corpus has and the regeneration lacks.
    private(set) var removed: [String] = []
    /// Ids whose input differs, with every differing path.
    private(set) var restated: [String] = []
    /// Ids whose output differs, with every differing path.
    private(set) var changed: [String] = []
    /// Ids the regeneration names on more than one line.
    private(set) var duplicated: [String] = []
    /// Every difference, one line each: `restated|changed <id> <path>: <old> -> <new>`.
    private(set) var differences: [String] = []
    /// How many lines were checked in.
    private(set) var checkedInCount = 0

    /// The report `content-corpus.changes.txt` states: a summary, then every added and removed id and every
    /// difference with both values in full.
    var report: String {
        let summary = [
            "content-corpus changes: \(checkedInCount) lines checked in",
            "added \(added.count), removed \(removed.count), duplicated \(duplicated.count), restated inputs \(restated.count), changed outputs \(changed.count)",
            ""
        ]
        return (summary + added.map { "added \($0)" } + removed.map { "removed \($0)" } + duplicated.map { "duplicated \($0)" } + differences)
            .map { $0 + "\n" }
            .joined()
    }

    /// The restated ids no allowed prefix covers.
    var unallowedRestatements: [String] {
        let prefixes = Self.restatablePrefixes
        return restated.filter { id in !prefixes.contains { id.hasPrefix($0) } }
    }

    /// Compares the regenerated lines with the checked-in corpus.
    init(checkedIn: Data, regenerated: [String]) throws {
        var old: [String: Tokens] = [:]
        var oldOrder: [String] = []
        for (number, bytes) in ContentCorpusStore.rawLines(checkedIn) {
            let (id, tokens) = try Self.tokens(of: bytes, number: number)
            old[id] = tokens
            oldOrder.append(id)
        }
        checkedInCount = oldOrder.count
        var seen: Set<String> = []
        for (index, line) in regenerated.enumerated() {
            let (id, new) = try Self.tokens(of: Data(line.utf8), number: index + 1)
            guard seen.insert(id).inserted else {
                duplicated.append(id)
                continue
            }
            guard let previous = old[id] else {
                added.append(id)
                continue
            }
            let restatement = Self.lines(TokenDiff.differences(expected: previous.input, actual: new.input), of: id, as: "restated")
            let change = Self.lines(TokenDiff.differences(expected: previous.output, actual: new.output), of: id, as: "changed")
            if !restatement.isEmpty {
                restated.append(id)
            }
            if !change.isEmpty {
                changed.append(id)
            }
            differences += restatement + change
        }
        removed = oldOrder.filter { !seen.contains($0) }
    }

    /// A line's id and its input and output tokens.
    private static func tokens(of bytes: Data, number: Int) throws -> (String, Tokens) {
        let line: LosslessJSONValue
        do {
            line = try LosslessJSONValue(parsing: bytes)
        } catch {
            throw ContentCorpusStore.MalformedLine(number: number, reason: String(describing: error))
        }
        guard let id = line["id"]?.text, let input = line["input"], let output = line["output"] else {
            throw ContentCorpusStore.MalformedLine(number: number, reason: "no id, input or output")
        }
        return (id, Tokens(input: input, output: output))
    }

    /// One report line per difference of `id`'s input or output.
    private static func lines(_ found: [TokenDiff.Difference], of id: String, as kind: String) -> [String] {
        found.map { "\(kind) \(id) \($0.change)" }
    }
}

#endif
