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
/// `id`, its `input` and its `output`, printed compactly with members sorted and output number lexemes kept. It is
/// regenerated exactly like the goldens, OUTSIDE the checkout: with `GROVE_GOLDEN_OUTPUT_DIR` set (under
/// `xcodebuild`, `TEST_RUNNER_GROVE_GOLDEN_OUTPUT_DIR`), the suite writes `content-corpus.jsonl` there, to be
/// copied in afterwards, and only in a commit whose diff is exactly the enumerated change of one fix.
enum ContentCorpusStore {
    /// One checked-in line: its key, its input, and the output it pins.
    struct Line {
        let id: String
        let input: ContentCorpusInput
        let output: LosslessJSONValue
    }

    struct MalformedLine: Error, CustomStringConvertible {
        let number: Int

        var description: String {
            "content-corpus.jsonl line \(number) is not an object with an id, an input and an output"
        }
    }

    struct MissingCorpus: Error, CustomStringConvertible {
        var description: String {
            "No content-corpus.jsonl is checked in; regenerate with GROVE_GOLDEN_OUTPUT_DIR and copy it into Resources/ContentCorpus"
        }
    }

    /// What a line states besides its output; read by Foundation, which keeps every string exactly.
    private struct Key: Decodable {
        let id: String
        let input: ContentCorpusInput
    }

    static let name = "content-corpus"
    static let fileExtension = "jsonl"

    static let outputDirectory: URL? = ProcessInfo.processInfo.environment["GROVE_GOLDEN_OUTPUT_DIR"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    static var isGenerating: Bool { outputDirectory != nil }

    /// Sorted members, unescaped slashes, and non-finite inputs as strings, since JSON has no literal for them.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    /// The checked-in corpus, whichever way the build system laid the resources out.
    static func checkedIn() throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "ContentCorpus")
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            throw MissingCorpus()
        }
        return try Data(contentsOf: url)
    }

    /// Reads the lines of `data` whose zero-based number leaves `shard.index` modulo `shard.count`, one at a time,
    /// so the corpus is never held as parsed tokens all at once.
    static func forEachLine(in data: Data, shard: (index: Int, count: Int) = (0, 1), _ body: (Line) throws -> Void) throws {
        for (number, slice) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).enumerated()
            where number % shard.count == shard.index {
            try autoreleasepool {
                try body(try line(Data(slice), number: number + 1))
            }
        }
    }

    /// Every line's id and input, in order, leaving the outputs unread.
    static func vectors(in data: Data) throws -> [ContentCorpusVector] {
        try data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).enumerated().map { number, slice in
            guard let key = try? decoder.decode(Key.self, from: Data(slice)) else {
                throw MalformedLine(number: number + 1)
            }
            return ContentCorpusVector(id: key.id, input: key.input)
        }
    }

    /// The input as the corpus prints it; two inputs compare by this text, so a NaN equals itself.
    static func inputText(_ input: ContentCorpusInput) throws -> String {
        String(decoding: try encoder.encode(input), as: UTF8.self)
    }

    /// The line a vector and its output print as.
    static func line(_ vector: ContentCorpusVector, output: LosslessJSONValue) throws -> String {
        let id = String(decoding: try encoder.encode(vector.id), as: UTF8.self)
        let input = try inputText(vector.input)
        return #"{"id":\#(id),"input":\#(input),"output":\#(output.canonicalText)}"#
    }

    /// Writes the regenerated corpus into the output directory.
    static func write(_ lines: [String]) throws {
        guard let directory = outputDirectory else {
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = lines.map { $0 + "\n" }.joined()
        try Data(text.utf8).write(to: directory.appendingPathComponent("\(name).\(fileExtension)"))
    }

    private static func line(_ data: Data, number: Int) throws -> Line {
        guard let key = try? decoder.decode(Key.self, from: data),
              let output = (try? LosslessJSONValue(parsing: data))?["output"] else {
            throw MalformedLine(number: number)
        }
        return Line(id: key.id, input: key.input, output: output)
    }
}


extension LosslessJSONValue {
    /// Compact JSON with members sorted by key and every number lexeme kept as read: two values print alike exactly
    /// when their tokens are equal, so a corpus line diffs by content.
    var canonicalText: String {
        var text = ""
        append(to: &text)
        return text
    }

    private static func append(_ string: String, to text: inout String) {
        text.append("\"")
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text.append("\\\"")
            case "\\": text.append("\\\\")
            case "\n": text.append("\\n")
            case "\r": text.append("\\r")
            case "\t": text.append("\\t")
            case _ where scalar.value < 0x20: text.append(String(format: "\\u%04x", scalar.value))
            default: text.unicodeScalars.append(scalar)
            }
        }
        text.append("\"")
    }

    private func append(to text: inout String) {
        switch self {
        case .object(let members):
            text.append("{")
            for (index, key) in members.keys.sorted().enumerated() {
                text.append(index == 0 ? "" : ",")
                Self.append(key, to: &text)
                text.append(":")
                members[key]?.append(to: &text)
            }
            text.append("}")
        case .array(let elements):
            text.append("[")
            for (index, element) in elements.enumerated() {
                text.append(index == 0 ? "" : ",")
                element.append(to: &text)
            }
            text.append("]")
        case .string(let string):
            Self.append(string, to: &text)
        case .number(let lexeme):
            text.append(lexeme)
        case .boolean(let flag):
            text.append(flag ? "true" : "false")
        case .null:
            text.append("null")
        }
    }
}

#endif
