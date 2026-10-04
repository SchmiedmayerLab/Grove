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


/// Pins the bytes a graph exposes: its canonical encoding when built from a model, the given bytes
/// when re-validated, and the event identifier beside them.
@Suite
struct ExchangeGraphBytesTests {
    private static var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    @Test("A built graph holds the sorted-member, slash-unescaped encoding of its bundle", arguments: GoldenCase.all)
    func builtGraphHoldsCanonicalBytes(_ goldenCase: GoldenCase) throws {
        let graph = try goldenCase.output().graph
        #expect(try graph.json == Self.canonicalEncoder.encode(graph.bundle))
        #expect(!String(decoding: graph.json, as: UTF8.self).contains("\\/"))
        let defaultTokens = try LosslessJSONValue(parsing: JSONEncoder().encode(graph.bundle))
        #expect(try LosslessJSONValue(parsing: graph.json) == defaultTokens, "the canonical bytes carry other tokens than the default encoding")
    }

    @Test("Two builds from the same inputs yield the same bytes, not only the same tokens")
    func builtBytesAreDeterministic() throws {
        for goldenCase in GoldenCase.all.prefix(4) {
            let first = try goldenCase.output().graph.json
            let second = try goldenCase.output().graph.json
            #expect(first == second, "\(goldenCase.name)")
        }
    }

    @Test("Re-validation keeps exactly the given bytes and the same event", arguments: GoldenCase.all)
    func revalidationKeepsGivenBytes(_ goldenCase: GoldenCase) throws {
        let graph = try goldenCase.output().graph
        let restored = try ExchangeGraph(validating: graph.json, kind: graph.kind)
        #expect(restored.json == graph.json)
        #expect(restored.kind == graph.kind)
        #expect(restored.event == graph.event)
        #expect(restored.eventIdentifier == graph.eventIdentifier)
        #expect(restored.isSemanticallyEqual(to: graph))
        #expect(restored.bundle.entry?.count == graph.bundle.entry?.count)
    }

    @Test("Re-validation keeps bytes that are not the canonical encoding")
    func revalidationKeepsForeignBytes() throws {
        let graph = try #require(GoldenCase.all.first).output().graph
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted]
        let foreign = try pretty.encode(graph.bundle)
        #expect(foreign != graph.json)
        let restored = try ExchangeGraph(validating: foreign, kind: graph.kind)
        #expect(restored.json == foreign)
        #expect(restored.isSemanticallyEqual(to: graph))
    }

    /// The bytes are what travels, while the rules decide over the model, so a member the model drops is refused, at
    /// the Bundle and inside a resource alike; a decimal lexeme the model rewrites is not a dropped member.
    @Test("Re-validation refuses members the FHIR model does not keep")
    func revalidationRefusesMembersTheModelDrops() throws {
        let graph = try #require(GoldenCase.all.first).output().graph
        func edited(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
            var bundle = try #require(try JSONSerialization.jsonObject(with: graph.json) as? [String: Any])
            try change(&bundle)
            return try JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        let refusal = ExchangeGraphError.invalidEntries("Serialized event carries members the model does not keep")
        #expect(throws: refusal) {
            try ExchangeGraph(validating: try edited { $0["note"] = "not a Bundle element" }, kind: graph.kind)
        }
        #expect(throws: refusal) {
            try ExchangeGraph(validating: try edited { bundle in
                var entries = try #require(bundle["entry"] as? [[String: Any]])
                var resource = try #require(entries[0]["resource"] as? [String: Any])
                resource["unmodeled"] = ["value": 1]
                entries[0]["resource"] = resource
                bundle["entry"] = entries
            }, kind: graph.kind)
        }
        let rewritten = Data(String(decoding: graph.json, as: UTF8.self).replacingOccurrences(of: #""value":72}"#, with: #""value":72.0}"#).utf8)
        #expect(rewritten != graph.json)
        #expect(try ExchangeGraph(validating: rewritten, kind: graph.kind).json == rewritten)
    }

    @Test("The earlier spelling forwards to the validating initializer")
    func earlierSpellingForwards() throws {
        let graph = try #require(GoldenCase.all.first).output().graph
        let viaEarlierSpelling = try ExchangeGraph(kind: graph.kind, jsonData: graph.json)
        let viaValidating = try ExchangeGraph(validating: graph.json, kind: graph.kind)
        #expect(viaEarlierSpelling.json == viaValidating.json)
        #expect(viaEarlierSpelling.event == viaValidating.event)
        #expect(viaEarlierSpelling.kind == viaValidating.kind)
    }

    @Test("The validating initializer rejects what the earlier spelling rejects")
    func validatingRejectsNonStrictJSON() throws {
        let graph = try #require(GoldenCase.all.first).output().graph
        var corrupted = graph.json
        corrupted.append(contentsOf: Array("}".utf8))
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(validating: corrupted, kind: graph.kind)
        }
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(kind: graph.kind, jsonData: corrupted)
        }
        #expect(throws: ExchangeGraphError.self) {
            try ExchangeGraph(validating: graph.json, kind: graph.kind == .active ? .retraction : .active)
        }
    }

    @Test("The event is the Bundle's identifier")
    func eventIsTheBundleIdentifier() throws {
        let graph = try #require(GoldenCase.all.first).output().graph
        #expect(graph.event == graph.eventIdentifier.identifier.identifier)
        #expect(graph.event.value == graph.bundle.identifier?.value?.value?.string)
        #expect(graph.event.system.rawValue == graph.bundle.identifier?.system?.value?.url.absoluteString)
        #expect(graph.event.value.hasPrefix("e0:"))
    }

    @Test("The kind keeps its earlier top-level spelling")
    func kindKeepsEarlierSpelling() {
        let active: ExchangeGraphKind = .active
        let retraction: ExchangeGraph.Kind = .retraction
        #expect(active == ExchangeGraph.Kind.active)
        #expect(retraction == ExchangeGraphKind.retraction)
        #expect(active != retraction)
    }
}

#endif
