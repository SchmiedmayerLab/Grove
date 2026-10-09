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
    func builtGraphHoldsCanonicalBytes(_ goldenCase: GoldenCase) async throws {
        let graph = try await goldenCase.output().graph
        #expect(try graph.json == Self.canonicalEncoder.encode(graph.bundle))
        #expect(!String(decoding: graph.json, as: UTF8.self).contains("\\/"))
        let defaultTokens = try LosslessJSONValue(parsing: JSONEncoder().encode(graph.bundle))
        #expect(try LosslessJSONValue(parsing: graph.json) == defaultTokens, "the canonical bytes carry other tokens than the default encoding")
    }

    @Test("Two builds from the same inputs yield the same bytes, not only the same tokens")
    func builtBytesAreDeterministic() async throws {
        for goldenCase in GoldenCase.all.prefix(4) {
            let first = try await goldenCase.output().graph.json
            let second = try await goldenCase.output().graph.json
            #expect(first == second, "\(goldenCase.name)")
        }
    }

    @Test("Re-validation keeps exactly the given bytes and the same event", arguments: GoldenCase.all)
    func revalidationKeepsGivenBytes(_ goldenCase: GoldenCase) async throws {
        let graph = try await goldenCase.output().graph
        let restored = try ExchangeGraph(validating: graph.json, kind: graph.kind)
        #expect(restored.json == graph.json)
        #expect(restored.kind == graph.kind)
        #expect(restored.event == graph.event)
        #expect(restored.eventIdentifier == graph.eventIdentifier)
        #expect(restored.isSemanticallyEqual(to: graph))
        #expect(restored.bundle.entry?.count == graph.bundle.entry?.count)
    }

    @Test("Re-validation keeps bytes that are not the canonical encoding")
    func revalidationKeepsForeignBytes() async throws {
        let graph = try await #require(GoldenCase.all.first).output().graph
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
    func revalidationRefusesMembersTheModelDrops() async throws {
        let graph = try await #require(GoldenCase.all.first).output().graph
        func edited(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
            var bundle = try #require(try JSONSerialization.jsonObject(with: graph.json) as? [String: Any])
            try change(&bundle)
            return try JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        let refusal = ExchangeGraphError.invalidEntries("Serialized event carries content the model does not keep")
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

    /// The rules decide over the values the model holds, so bytes stating a value the model rewrote are refused: a
    /// profile canonical with an empty version, which the model drops and the IG refuses as a profile claim, and a
    /// decimal beyond the model's precision, which it rounds.
    @Test("Re-validation refuses values the FHIR model rewrites")
    func revalidationRefusesValuesTheModelRewrites() async throws {
        let graph = try await #require(GoldenCase.all.first).output().graph
        let json = String(decoding: graph.json, as: UTF8.self)
        let rewrites = [
            (#"healthkit-conversion-provenance""#, #"healthkit-conversion-provenance|""#),
            (#""value":72}"#, #""value":72.00000000000000000000000000000000000000001}"#)
        ]
        for (original, rewritten) in rewrites {
            let edited = json.replacingOccurrences(of: original, with: rewritten)
            #expect(edited != json)
            #expect(throws: ExchangeGraphError.invalidEntries("Serialized event carries content the model does not keep")) {
                try ExchangeGraph(validating: Data(edited.utf8), kind: graph.kind)
            }
        }
    }

    /// What re-validation compares: numbers by their exact value, every other scalar by its tokens.
    @Test("Kept content compares numbers by exact value and every other scalar as given")
    func keptContentComparesNumbersByExactValue() throws {
        func tokens(_ json: String) throws -> LosslessJSONValue {
            try LosslessJSONValue(parsing: Data(json.utf8))
        }
        for lexeme in ["72", "72.0", "7.2e1", "720E-1", "0.0072e+4"] {
            #expect(try tokens(lexeme).isKept(as: tokens("72")), "\(lexeme)")
        }
        #expect(try tokens("-0.0").isKept(as: tokens("0")))
        // An exponent of 2^32 or more in magnitude compares by its lexeme, so no scale computation overflows.
        for lexeme in ["7.2", "-72", "720", "72.00000000000000000000000000000000000000001", "72e4294967296", "1.5e-9223372036854775808"] {
            #expect(try !tokens(lexeme).isKept(as: tokens("72")), "\(lexeme)")
        }
        #expect(try !tokens(#"{"profile":"x|"}"#).isKept(as: tokens(#"{"profile":"x"}"#)))
        #expect(try !tokens(#"{"flag":true}"#).isKept(as: tokens(#"{"flag":"true"}"#)))
        #expect(try !tokens("[72,72]").isKept(as: tokens("[72]")))
        #expect(try !tokens("{}").isKept(as: tokens(#"{"value":72}"#)))
    }

    @Test("The validating initializer rejects bytes that are not strict JSON, and another kind")
    func validatingRejectsNonStrictJSON() async throws {
        let graph = try await #require(GoldenCase.all.first).output().graph
        var corrupted = graph.json
        corrupted.append(contentsOf: Array("}".utf8))
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(validating: corrupted, kind: graph.kind)
        }
        #expect(throws: ExchangeGraphError.self) {
            try ExchangeGraph(validating: graph.json, kind: graph.kind == .active ? .retraction : .active)
        }
    }

    @Test("The event is the Bundle's identifier")
    func eventIsTheBundleIdentifier() async throws {
        let graph = try await #require(GoldenCase.all.first).output().graph
        #expect(graph.event == graph.eventIdentifier.identifier.identifier)
        #expect(graph.event.value == graph.bundle.identifier?.value?.value?.string)
        #expect(graph.event.system.rawValue == graph.bundle.identifier?.system?.value?.url.absoluteString)
        #expect(graph.event.value.hasPrefix("e0:"))
    }
}

#endif
