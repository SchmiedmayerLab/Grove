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
import ModelsR4
import Testing


/// Where the checked-in goldens live, and where a regeneration writes.
///
/// Goldens are regenerated OUTSIDE the checkout: `GROVE_GOLDEN_OUTPUT_DIR` (under `xcodebuild`, pass it as
/// `TEST_RUNNER_GROVE_GOLDEN_OUTPUT_DIR`) names a directory the suite writes every case into, and the files are
/// copied into `Resources/Goldens/` afterwards. Writing into the checkout while Xcode runs the tests makes it
/// re-resolve the package graph mid-run. A regeneration run compares nothing, so it fails on purpose: it can
/// never be mistaken for a green golden run.
enum GoldenStore {
    struct MissingGolden: Error, CustomStringConvertible {
        let name: String

        var description: String {
            "No golden '\(name).json' is checked in; regenerate with GROVE_GOLDEN_OUTPUT_DIR and copy it into Resources/Goldens"
        }
    }

    static let subdirectory = "Goldens"
    static let outlinesName = "outlines"

    static let outputDirectory: URL? = ProcessInfo.processInfo.environment["GROVE_GOLDEN_OUTPUT_DIR"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    static var isGenerating: Bool { outputDirectory != nil }

    /// Sorted members and no escaped slashes, so a regenerated golden diffs by content; the comparison reads tokens, not text.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Every checked-in golden's name, whichever way the build system laid the resources out: `.process` flattens the
    /// subdirectory, and a lookup under a subdirectory that is not there answers an empty array, not nil.
    static var checkedInNames: Set<String> {
        let urls = [subdirectory, nil]
            .compactMap { Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: $0) }
            .first { !$0.isEmpty } ?? []
        return Set(urls.map { $0.deletingPathExtension().lastPathComponent })
    }

    static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "json") else {
            throw MissingGolden(name: name)
        }
        return try Data(contentsOf: url)
    }

    static func outlines() throws -> [String: GoldenOutline] {
        try JSONDecoder().decode([String: GoldenOutline].self, from: data(named: outlinesName))
    }
}


/// The parts of an output the refactor is most likely to reorder or drop, pinned on their own so a failure names
/// them: every entry's fullUrl in Bundle order, each resource's identifier and extension arrays in order, and the
/// conversion's warnings in order.
struct GoldenOutline: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let fullUrl: String
        let resourceType: String
        /// `<type code>|<system>|<value>` per identifier, in array order.
        let identifiers: [String]
        /// Each extension's url, in array order.
        let extensions: [String]
    }

    let entries: [Entry]
    /// `GoldenOutput.renderedWarnings`.
    let warnings: [String]

    init(_ bundle: LosslessJSONValue, warnings: [String]) {
        self.warnings = warnings
        entries = (bundle["entry"]?.elements ?? []).map { entry in
            let resource = entry["resource"]
            return Entry(
                fullUrl: entry["fullUrl"]?.text ?? "",
                resourceType: resource?["resourceType"]?.text ?? "",
                identifiers: (resource?["identifier"]?.elements ?? []).map { identifier in
                    let typeCode = identifier["type"]?["coding"]?.elements?.first?["code"]?.text ?? "-"
                    return "\(typeCode)|\(identifier["system"]?.text ?? "")|\(identifier["value"]?.text ?? "")"
                },
                extensions: (resource?["extension"]?.elements ?? []).map { $0["url"]?.text ?? "" }
            )
        }
    }
}


/// Names the first path where two token trees differ.
private enum TokenDiff {
    /// The first path where two token trees differ, or nil when they are equal.
    static func firstDifference(expected: LosslessJSONValue, actual: LosslessJSONValue, at path: String = "$") -> String? {
        switch (expected, actual) {
        case let (.object(lhs), .object(rhs)):
            for key in Set(lhs.keys).union(rhs.keys).sorted() {
                guard let left = lhs[key] else {
                    return "\(path).\(key): golden has no such member, actual is \(rhs[key].map(describe) ?? "")"
                }
                guard let right = rhs[key] else {
                    return "\(path).\(key): missing, golden has \(describe(left))"
                }
                if let difference = firstDifference(expected: left, actual: right, at: "\(path).\(key)") {
                    return difference
                }
            }
            // Every value matched under a dictionary lookup, which finds canonically equivalent names alike.
            return expected == actual ? nil : "\(path): a member name differs in its Unicode scalars"
        case let (.array(lhs), .array(rhs)):
            for (index, pair) in zip(lhs, rhs).enumerated() {
                if let difference = firstDifference(expected: pair.0, actual: pair.1, at: "\(path)[\(index)]") {
                    return difference
                }
            }
            return lhs.count == rhs.count ? nil : "\(path): golden has \(lhs.count) elements, actual has \(rhs.count)"
        default:
            return expected == actual ? nil : "\(path): golden \(describe(expected)), actual \(describe(actual))"
        }
    }

    private static func describe(_ value: LosslessJSONValue) -> String {
        switch value {
        case .object(let members): "object(\(members.count) members)"
        case .array(let elements): "array(\(elements.count))"
        case .string(let text): "\"" + text.unicodeScalars.map { $0.isASCII ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined() + "\""
        case .number(let lexeme): lexeme
        case .boolean(let flag): "\(flag)"
        case .null: "null"
        }
    }
}


/// Pins the converter's current wire output, token for token, so the refactor can be proven identical.
///
/// Each case converts fixed inputs through the OLD API and compares the graph's stored JSON (`ExchangeGraph.json`,
/// the bytes a consumer uploads) with the checked-in golden over lossless tokens: member order is free, array order
/// and decimal lexemes are not. A failure names the first differing path.
@Suite
struct GoldenGraphTests {
    @Test(.enabled(if: !GoldenStore.isGenerating), arguments: GoldenCase.all)
    func matchesCheckedInGolden(_ goldenCase: GoldenCase) throws {
        let output = try goldenCase.output()
        let actual = try LosslessJSONValue(parsing: output.graph.json)
        let expected = try LosslessJSONValue(parsing: GoldenStore.data(named: goldenCase.name))
        let outline = try #require(GoldenStore.outlines()[goldenCase.name], "no outline is pinned for \(goldenCase.name)")

        #expect(
            GoldenOutline(actual, warnings: output.renderedWarnings) == outline,
            "\(goldenCase.name): entry, identifier, extension or warning order drifted"
        )
        #expect(
            GoldenOutline(expected, warnings: outline.warnings) == outline,
            "\(goldenCase.name): outlines.json does not describe the checked-in golden"
        )
        let scope = ExchangeEventContext.test()
        let mismatches = try output.reportMismatches(identityScope: scope.identityScope, repositoryScope: scope.repositoryScope)
        #expect(mismatches.isEmpty, "\(goldenCase.name) reports what its graph does not carry: \(mismatches)")
        if let difference = TokenDiff.firstDifference(expected: expected, actual: actual) {
            Issue.record("\(goldenCase.name) drifted from its golden at \(difference)")
        }
    }

    /// The goldens directory and `outlines.json` name exactly the cases: nothing is missing, and nothing lingers
    /// after a case is renamed or removed. The first check also keeps the lookup honest, as an empty listing fails it.
    @Test
    func everyCheckedInGoldenBelongsToACase() throws {
        let cases = Set(GoldenCase.all.map(\.name))
        let checkedIn = GoldenStore.checkedInNames
        #expect(checkedIn.isSuperset(of: cases), "cases without a golden: \(cases.subtracting(checkedIn).sorted())")
        let strays = checkedIn.subtracting(cases).subtracting([GoldenStore.outlinesName]).subtracting(GoldenCase.unavailableHere)
        #expect(strays.isEmpty, "goldens without a case: \(strays.sorted())")
        let strayOutlines = Set(try GoldenStore.outlines().keys).subtracting(cases).subtracting(GoldenCase.unavailableHere)
        #expect(strayOutlines.isEmpty, "outlines without a case: \(strayOutlines.sorted())")
    }

    /// Every case is named once, mints its own event, converts to the same tokens and warnings twice in one process,
    /// and re-encodes with sorted members to the same tokens as its wire bytes. With `GROVE_GOLDEN_OUTPUT_DIR` set,
    /// this is also the regeneration: each case's sorted-member JSON and the outlines are written there, and the run
    /// fails, as it compared nothing.
    @Test
    func everyCaseIsDeterministicAndPinnable() throws {
        var outlines: [String: GoldenOutline] = [:]
        var events: [String: String] = [:]
        for goldenCase in GoldenCase.all {
            let output = try goldenCase.output()
            let graph = output.graph
            let wire = try LosslessJSONValue(parsing: graph.json)
            let again = try goldenCase.output()
            #expect(try LosslessJSONValue(parsing: again.graph.json) == wire, "\(goldenCase.name) is not deterministic")
            #expect(again.renderedWarnings == output.renderedWarnings, "\(goldenCase.name) does not warn deterministically")
            let sorted = try GoldenStore.encoder.encode(graph.bundle)
            #expect(try LosslessJSONValue(parsing: sorted) == wire, "\(goldenCase.name): a sorted re-encode changes the tokens")

            let outline = GoldenOutline(wire, warnings: output.renderedWarnings)
            #expect(outlines.updateValue(outline, forKey: goldenCase.name) == nil, "\(goldenCase.name) is named twice")
            let event = graph.eventIdentifier.identifier.value
            #expect(events.updateValue(goldenCase.name, forKey: event) == nil, "\(goldenCase.name) shares its event with \(events[event] ?? "")")

            if let directory = GoldenStore.outputDirectory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try sorted.write(to: directory.appendingPathComponent("\(goldenCase.name).json"))
            }
        }
        if let directory = GoldenStore.outputDirectory {
            try GoldenStore.encoder.encode(outlines).write(to: directory.appendingPathComponent("\(GoldenStore.outlinesName).json"))
            Issue.record("Regenerated \(outlines.count) goldens into \(directory.path) and compared none: copy them into Resources/Goldens and rerun")
        }
    }

    /// A workout exports its session alone, events or not: one Observation, no members, one Provenance target.
    /// (The old converter refused every workout: its segment children claimed a profile the Provenance contract
    /// does not admit.)
    @Test(arguments: [false, true])
    func workoutsExportTheSessionAlone(withEvents: Bool) throws {
        let workout = try StoredSampleFixtures.stored(GoldenFixtures.workout(withEvents: withEvents), uuid: GoldenFixtures.uuid(0xA0))
        let context = try GoldenFixtures.context(sequence: 200)
        let conversion = try HealthKitConverter().convert(workout, context: context)
        let observations = conversion.bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        #expect(observations.count == 1)
        #expect(observations.first?.hasMember == nil)
        #expect(conversion.primary.identifiers.childOutputs.isEmpty)
        let provenance = try #require(conversion.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        #expect(provenance.target.count == 1)
    }

    /// A writer classified as an application whose bundle identifier is not one is a refusal; a writer with a blank
    /// name is merely no writer (`writer-blank-name-with-sync-identity` pins that graph).
    @Test
    func invalidWriterBundleIdentifierIsRefused() throws {
        var writer = GoldenFixtures.foreignWriter
        writer.bundleIdentifier = "not a bundle id"
        let sample = try GoldenFixtures.heartRate(uuid: GoldenFixtures.uuid(0xA1), writer: writer)
        let context = try GoldenFixtures.context(sequence: 201, .applicationWriter)
        #expect(throws: HealthKitConversionError.sourceApplicationInvalid) {
            try HealthKitConverter().convert(sample, context: context)
        }
    }

    /// The comparison is the exchange protocol's: member order free, array order and decimal lexemes fixed.
    @Test
    func tokenDifferencesAreNamedByPath() throws {
        func tokens(_ json: String) throws -> LosslessJSONValue {
            try LosslessJSONValue(parsing: Data(json.utf8))
        }
        let golden = try tokens(#"{"entry":[{"fullUrl":"a","resource":{"value":72}}],"timestamp":"t"}"#)
        let reordered = try tokens(#"{"timestamp":"t","entry":[{"resource":{"value":72},"fullUrl":"a"}]}"#)
        let lexeme = try tokens(#"{"entry":[{"fullUrl":"a","resource":{"value":72.0}}],"timestamp":"t"}"#)
        let longer = try tokens(#"{"entry":[{"fullUrl":"a","resource":{"value":72}},{"fullUrl":"b"}],"timestamp":"t"}"#)
        let renamed = try tokens(#"{"entry":[{"fullUrl":"a","resource":{"valueX":72}}],"timestamp":"t"}"#)
        #expect(TokenDiff.firstDifference(expected: golden, actual: reordered) == nil)
        #expect(TokenDiff.firstDifference(expected: golden, actual: lexeme) == "$.entry[0].resource.value: golden 72, actual 72.0")
        #expect(TokenDiff.firstDifference(expected: golden, actual: longer) == "$.entry: golden has 1 elements, actual has 2")
        #expect(TokenDiff.firstDifference(expected: golden, actual: renamed) == "$.entry[0].resource.value: missing, golden has 72")
        #expect(GoldenOutline(golden, warnings: []) == GoldenOutline(reordered, warnings: []))
        #expect(GoldenOutline(golden, warnings: []) != GoldenOutline(longer, warnings: []))
        #expect(GoldenOutline(golden, warnings: ["a"]) != GoldenOutline(golden, warnings: []))
    }

    /// Strings and member names compare scalar by scalar, as the guide's reference comparator does: a canonically
    /// equivalent spelling and a leading U+FEFF are different content, while a `\u` escape is the scalar it names.
    @Test
    func tokensCompareUnicodeScalars() throws {
        func tokens(_ json: String) throws -> LosslessJSONValue {
            try LosslessJSONValue(parsing: Data(json.utf8))
        }
        let precomposed = try tokens(#"{"name":"Sant\#u{E9}"}"#)
        let decomposed = try tokens(#"{"name":"Sante\#u{301}"}"#)
        #expect(precomposed != decomposed)
        #expect(TokenDiff.firstDifference(expected: precomposed, actual: decomposed) == #"$.name: golden "Sant\u{e9}", actual "Sante\u{301}""#)
        #expect(try tokens(#"{"Sant\#u{E9}":1}"#) != tokens(#"{"Sante\#u{301}":1}"#))
        #expect(
            TokenDiff.firstDifference(expected: try tokens(#"{"Sant\#u{E9}":1}"#), actual: try tokens(#"{"Sante\#u{301}":1}"#))
                == "$: a member name differs in its Unicode scalars"
        )
        let marked = try tokens(#"{"name":"\#u{FEFF}x"}"#)
        #expect(try tokens(#"{"name":"x"}"#) != marked)
        #expect(try tokens(#"{"name":"\uFEFFx"}"#) == marked)
        #expect(try tokens(#"["\#u{FEFF}a","\n\#u{FEFF}b"]"#) == .array([.string("\u{FEFF}a"), .string("\n\u{FEFF}b")]))
    }
}


extension LosslessJSONValue {
    var elements: [LosslessJSONValue]? { // swiftlint:disable:this discouraged_optional_collection
        guard case .array(let elements) = self else {
            return nil
        }
        return elements
    }

    var text: String? {
        guard case .string(let text) = self else {
            return nil
        }
        return text
    }

    subscript(member: String) -> LosslessJSONValue? {
        guard case .object(let members) = self else {
            return nil
        }
        return members[member]
    }
}


extension GoldenCase {
    /// Goldens generated on macOS for cases this platform cannot build.
    static var unavailableHere: Set<String> {
        #if os(watchOS)
        ["clinical-document"]
        #else
        []
        #endif
    }
}


#endif
