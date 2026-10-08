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
import ModelsR4
import Testing


@Suite("WireJSONEncoder")
struct WireJSONEncoderTests {
    private struct Probe: Encodable {
        let text: String
        let decimals: [Decimal]
        let integers: [Int64]
        let flags: [Bool]
        let optionals: [String?]
        let url: URL
        let data: Data
        let nested: [String: [String]]
        let empty: [String: String]
    }

    private struct Nothing: Encodable {
        func encode(to encoder: any Encoder) throws {}
    }

    private struct Repeated: Encodable {
        enum Key: String, CodingKey {
            case value
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode("first", forKey: .value)
            try container.encode("last", forKey: .value)
        }
    }

    private static var reference: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func controlCharacters() -> String {
        var text = ""
        for value in 0..<0x20 {
            text.unicodeScalars.append(Unicode.Scalar(UInt8(value)))
        }
        return text + "\"\\/\u{7F}\u{80}\u{2028}\u{FEFF}😀e\u{0301}é"
    }

    @Test("Every golden graph's bytes are JSONEncoder's bytes, and its identifiers decode to the model's")
    func goldenGraphsMatchJSONEncoder() throws {
        for goldenCase in GoldenCase.all {
            let graph = try goldenCase.output().graph
            #expect(graph.json == (try Self.reference.encode(graph.bundle)), "\(goldenCase.name)")
            let entries = try #require(
                (try JSONSerialization.jsonObject(with: graph.json) as? [String: Any])?["entry"] as? [[String: Any]]
            )
            for (entry, json) in zip(graph.bundle.entry ?? [], entries) {
                let modelIdentifiers: [Identifier]
                switch entry.resource {
                case .observation(let resource): modelIdentifiers = resource.identifier ?? []
                case .device(let resource): modelIdentifiers = resource.identifier ?? []
                case .researchStudy(let resource): modelIdentifiers = resource.identifier ?? []
                case .researchSubject(let resource): modelIdentifiers = resource.identifier ?? []
                case .planDefinition(let resource): modelIdentifiers = resource.identifier ?? []
                case .patient(let resource): modelIdentifiers = resource.identifier ?? []
                default: continue
                }
                let rawIdentifiers = (json["resource"] as? [String: Any])?["identifier"] as? [[String: Any]] ?? []
                let decoded = try rawIdentifiers.map {
                    try JSONDecoder().decode(Identifier.self, from: JSONSerialization.data(withJSONObject: $0))
                }
                #expect(decoded == modelIdentifiers, "\(goldenCase.name)")
            }
        }
    }

    @Test("Strings, numbers, URLs, data, nulls and nesting are written as JSONEncoder writes them")
    func primitivesMatchJSONEncoder() throws {
        let probe = Probe(
            text: Self.controlCharacters(),
            decimals: ["72.0", "0.000100", "-1.5e3", "12345678901234567890.123", "0"].compactMap { Decimal(string: $0) },
            integers: [0, -1, .min, .max],
            flags: [true, false],
            optionals: [nil, "x"],
            url: try #require(URL(string: "https://example.org/a%20b?c=d#e")),
            data: Data([0, 1, 2, 0xFF]),
            nested: ["b": ["2", "1"], "B": [], "_a": ["x"], "a10": [], "a2": []],
            empty: [:]
        )
        #expect(try WireJSONEncoder.encode(probe) == (try Self.reference.encode(probe)))
    }

    @Test("A nested value that encodes nothing is an empty object, a top-level one is JSONEncoder's, and a repeated member keeps its last")
    func emptyAndRepeatedMatchJSONEncoder() throws {
        #expect(try WireJSONEncoder.encode([Nothing()]) == (try Self.reference.encode([Nothing()])))
        #expect(try WireJSONEncoder.encode(Nothing()) == nil)
        #expect(try WireJSONEncoder.encode(Repeated()) == (try Self.reference.encode(Repeated())))
    }

    @Test("Floating-point numbers and dates are left to JSONEncoder")
    func floatingPointIsUnsupported() throws {
        #expect(try WireJSONEncoder.encode([1.5]) == nil)
        #expect(try WireJSONEncoder.encode([Date(timeIntervalSince1970: 0)]) == nil)
    }

    @Test("The tree states what the bytes parse to")
    func treeMatchesTheBytes() throws {
        let graph = try #require(GoldenCase.all.first).output().graph
        let (json, tree) = try #require(try WireJSONEncoder.encodeKeepingTree(graph.bundle))
        let parsed = try JSONSerialization.jsonObject(with: json)
        #expect((tree as? NSObject)?.isEqual(parsed) == true)
    }
}

#endif
