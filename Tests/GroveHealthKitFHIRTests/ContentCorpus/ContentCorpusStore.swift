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


/// Where the content corpus lives, how its lines read and print, and where a regeneration writes.
///
/// The corpus is `Resources/ContentCorpus/content-corpus.jsonl`: one line per vector, an object with the vector's
/// `id`, its `input` and its `output`, printed compactly with members sorted, output number lexemes kept, and
/// every invisible scalar (a byte order mark, a line separator) escaped. It is regenerated OUTSIDE the checkout:
/// with `GROVE_CONTENT_CORPUS_OUTPUT_DIR` set (under `xcodebuild`, `TEST_RUNNER_GROVE_CONTENT_CORPUS_OUTPUT_DIR`),
/// the suite writes `content-corpus.jsonl` and `content-corpus.changes.txt` there, to be copied in (the corpus
/// only) afterwards, and only in a commit whose diff is exactly the enumerated change of one fix.
enum ContentCorpusStore {
    /// One checked-in line: its key, its input, the output it pins, and its bytes as checked in.
    struct Line {
        /// The vector's key.
        let id: String
        /// The vector's input.
        let input: ContentCorpusInput
        /// The output the line pins.
        let output: LosslessJSONValue
        /// The line's bytes, without the newline.
        let bytes: Data

        /// The vector the line states.
        var vector: ContentCorpusVector {
            ContentCorpusVector(id: id, input: input)
        }
    }

    /// A line that is not an object with an id, an input this schema reads, and an output.
    struct MalformedLine: Error, CustomStringConvertible {
        /// The one-based line number.
        let number: Int
        /// What could not be read.
        let reason: String

        var description: String {
            "content-corpus.jsonl line \(number) is not an object with an id, an input and an output: \(reason)"
        }
    }

    /// What a line states besides its output; read by Foundation, which keeps every string exactly.
    private struct Key: Decodable {
        /// The line's key.
        let id: String
        /// The line's input.
        let input: ContentCorpusInput
    }

    /// The corpus's place in the bundle and its regeneration directory.
    static let resources = CheckedInResources.contentCorpus
    /// The corpus's file name.
    static let name = "content-corpus"
    /// The corpus's file extension.
    static let fileExtension = "jsonl"
    /// The change report a regeneration writes beside the corpus.
    static let changesFile = "content-corpus.changes.txt"

    /// Whether this run regenerates the corpus instead of verifying it.
    static var isGenerating: Bool {
        resources.isGenerating
    }

    /// Sorted members, unescaped slashes, and non-finite inputs as strings, since JSON has no literal for them.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return encoder
    }

    /// The decoder matching ``encoder``.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    /// The checked-in corpus, whichever way the build system laid the resources out.
    static func checkedIn() throws -> Data {
        try resources.data(named: name, withExtension: fileExtension)
    }

    /// The lines of `data` with their one-based numbers, without the newlines.
    static func rawLines(_ data: Data) -> [(number: Int, bytes: Data)] {
        data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).enumerated().map { ($0 + 1, Data($1)) }
    }

    /// Reads the lines of `data` whose zero-based number leaves `shard.index` modulo `shard.count`, one at a time,
    /// so the corpus is never held as parsed tokens all at once.
    static func forEachLine(
        in data: Data,
        shard: (index: Int, count: Int) = (0, 1),
        _ body: (Line) async throws -> Void
    ) async throws {
        for (number, bytes) in rawLines(data) where (number - 1) % shard.count == shard.index {
            let parsed = try autoreleasepool {
                try line(bytes, number: number)
            }
            try await body(parsed)
        }
    }

    /// Every line's id and input, in order, leaving the outputs unread.
    static func vectors(in data: Data) throws -> [ContentCorpusVector] {
        try rawLines(data).map { number, bytes in
            let key = try key(bytes, number: number)
            return ContentCorpusVector(id: key.id, input: key.input)
        }
    }

    /// The input as the corpus prints it; two inputs compare by this text, so a NaN equals itself.
    static func inputText(_ input: ContentCorpusInput) throws -> String {
        var text = ""
        for scalar in String(decoding: try encoder.encode(input), as: UTF8.self).unicodeScalars {
            // JSONEncoder leaves format characters raw; inside a string the escape states the same scalar.
            if LosslessJSONValue.isEscaped(scalar) {
                text += LosslessJSONValue.escape(scalar)
            } else {
                text.unicodeScalars.append(scalar)
            }
        }
        return text
    }

    /// The line a vector and its output print as.
    static func line(_ vector: ContentCorpusVector, output: LosslessJSONValue) throws -> String {
        let id = LosslessJSONValue.string(vector.id).canonicalText
        return #"{"id":\#(id),"input":\#(try inputText(vector.input)),"output":\#(output.canonicalText)}"#
    }

    /// Writes the regenerated corpus and its change report into the regeneration directory.
    static func write(_ lines: [String], changes: ContentCorpusChanges) throws {
        try resources.write(Data(lines.map { $0 + "\n" }.joined().utf8), toFile: "\(name).\(fileExtension)")
        try resources.write(Data(changes.report.utf8), toFile: changesFile)
    }

    /// The id and input of line `number`.
    private static func key(_ bytes: Data, number: Int) throws -> Key {
        do {
            return try decoder.decode(Key.self, from: bytes)
        } catch {
            throw MalformedLine(number: number, reason: String(describing: error))
        }
    }

    /// Line `number` read whole.
    private static func line(_ bytes: Data, number: Int) throws -> Line {
        let key = try key(bytes, number: number)
        let tokens: LosslessJSONValue
        do {
            tokens = try LosslessJSONValue(parsing: bytes)
        } catch {
            throw MalformedLine(number: number, reason: String(describing: error))
        }
        guard let output = tokens["output"] else {
            throw MalformedLine(number: number, reason: "no output")
        }
        return Line(id: key.id, input: key.input, output: output, bytes: bytes)
    }
}

#endif
